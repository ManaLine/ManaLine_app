import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/typography.dart';
import '../design/components/mana_app_bar.dart';
import 'translation_service.dart';
import '../design/components/mana_text.dart';
import 'photo_compression.dart' show ManaPhotoPreset;

/// Reusable live-capture screen for every "Live Photo Capture (MANDATORY,
/// camera only)" field in the app — LR-004 F1 (registration, BR-036) and
/// OW-005/AG loan issuance (BR-081). Both are the SAME requirement per the
/// spec's own wording ("Live Photo Capture mandatory... fraud prevention"),
/// so this widget is shared rather than duplicated per screen.
///
/// PLATFORM LIMITATION (flagged, not silently worked around):
/// google_mlkit_face_detection wraps native Android/iOS ML Kit — it has NO
/// Flutter Web binding, so the live face-presence gate below only runs on
/// Android/iOS.
///
/// The bigger gap is not ML Kit — it is `camera` itself. `camera` has no
/// web implementation in this dependency set: `availableCameras()` throws
/// before any face-detection logic is ever reached. An earlier version of
/// this file assumed the opposite (that the camera opened on web and only
/// the ML Kit gate was missing) and shipped nine `kIsWeb` branches built on
/// that false premise — e.g. `_faceDetected = kIsWeb`, treating "on web" as
/// "a face is present". That code compiled and read correctly, and would
/// have thrown on the first browser visit to this screen.
///
/// So on Web this screen never touches `CameraController` at all. It shows
/// the same chrome with a single "choose a photo" action backed by
/// `file_selector` instead of a live viewfinder, and says so on screen —
/// see `_pickPhoto` and the web branch of `build()`. The picked bytes are
/// routed through the exact same `cropToFaceCircle` call the camera path
/// uses, so nothing that arrives via upload skips the processing a live
/// capture would have gone through. On Android/iOS, camera-only capture
/// (no gallery picker) is still enforced exactly as before.
///
/// WHAT THIS DETECTS: exactly ONE face present and roughly centered in
/// frame. This is presence/liveness-adjacent (a live camera stream, not a
/// static gallery image, per BR-036's actual requirement), NOT identity
/// verification / face-match against a stored ID photo — the spec does not
/// require the latter anywhere (confirmed: no "face match" or "facial
/// recognition" language exists in any locked spec doc).
class LiveFaceCaptureScreen extends ConsumerStatefulWidget {
  const LiveFaceCaptureScreen({super.key});

  /// Pushes this screen and returns the captured JPEG bytes, or null if
  /// the user backed out without capturing.
  static Future<Uint8List?> capture(BuildContext context) {
    return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const LiveFaceCaptureScreen(), fullscreenDialog: true),
    );
  }

  @override
  ConsumerState<LiveFaceCaptureScreen> createState() => _LiveFaceCaptureScreenState();
}

class _LiveFaceCaptureScreenState extends ConsumerState<LiveFaceCaptureScreen> {
  CameraController? _controller;
  FaceDetector? _faceDetector;
  bool _initializing = true;
  bool _faceDetected = false; // native only — the web branch never reads this
  bool _busyCapturing = false;
  bool _detecting = false; // reentrancy guard for the image-stream callback

  /// Every lens this device has, and which one is live. Kept so the flip
  /// button can exist at all — this screen used to resolve the front camera
  /// once at startup and had no way back to any other.
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _switching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Web never has a `camera` implementation to open — see the class doc.
    // `availableCameras()` would throw here on every browser, so this skips
    // straight to the upload UI instead of attempting (and failing) a
    // camera open first.
    if (kIsWeb) {
      setState(() => _initializing = false);
      return;
    }
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw CameraException('no_cameras', 'This device reports no cameras.');
      }
      // Front by default: this is a selfie for identity, and it is what the
      // person will want nine times in ten. The rear lens is one tap away —
      // see _flip — because the tenth time is an Agent holding the handset up
      // to somebody standing in front of them, and before this there was no
      // way to do that at all.
      final frontIndex =
          _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _cameraIndex = frontIndex >= 0 ? frontIndex : 0;

      await _openCamera(_cameras[_cameraIndex]);
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not open camera. Check camera permission is granted. ($e)';
      });
    }
  }

  /// Opens one lens and starts the face-presence stream on it.
  ///
  /// Shared by first start and by [_flip] so the two cannot drift — a flip
  /// that forgot to restart the stream would leave the Capture button
  /// permanently disabled, which is indistinguishable from a broken camera.
  // Only ever called on Android/iOS — _init returns before this on Web, and
  // _flip (the only other caller) is only reachable from the camera UI that
  // Web never builds. So this no longer needs a kIsWeb branch of its own:
  // the `camera` plugin it drives has no web implementation to branch for.
  Future<void> _openCamera(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup:
          Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    _faceDetector ??= FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );
    await controller.startImageStream(_onCameraImage);

    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  /// Switches lens. Only offered when the device actually has a second one
  /// — native only; Web never populates `_cameras`, so the flip button
  /// never renders there (see build()).
  Future<void> _flip() async {
    if (_cameras.length < 2 || _switching || _busyCapturing) return;
    setState(() {
      _switching = true;
      // The new lens has not seen a face yet, and carrying the old lens's
      // answer over would leave Capture enabled while pointing at nothing.
      _faceDetected = false;
    });

    final old = _controller;
    // Cleared first so the preview does not paint from a controller that is
    // about to be disposed.
    setState(() => _controller = null);
    try {
      if (old != null) {
        if (old.value.isStreamingImages) {
          await old.stopImageStream();
        }
        await old.dispose();
      }
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      await _openCamera(_cameras[_cameraIndex]);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not switch camera. ($e)');
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _onCameraImage(CameraImage image) {
    if (_detecting || _faceDetector == null || _controller == null) return;
    _detecting = true;
    _processImage(image).whenComplete(() => _detecting = false);
  }

  Future<void> _processImage(CameraImage image) async {
    try {
      final camera = _controller!.description;
      final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return;

      final plane = image.planes.first;
      final inputImage = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );

      final faces = await _faceDetector!.processImage(inputImage);
      if (!mounted) return;
      final detected = faces.length == 1;
      if (detected != _faceDetected) {
        setState(() => _faceDetected = detected);
      }
    } catch (_) {
      // A single failed frame isn't fatal — the next stream frame retries.
      // Do not flip _faceDetected on a transient processing error.
    }
  }

  // Native camera capture. Never called on Web — see _init and build().
  Future<void> _capture() async {
    if (_controller == null || _busyCapturing || !_faceDetected) return;
    setState(() => _busyCapturing = true);
    try {
      await _controller!.stopImageStream();
      final file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.of(context).pop(cropToFaceCircle(bytes));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyCapturing = false;
        _error = 'Capture failed: $e';
      });
    }
  }

  /// Web's stand-in for _capture: a "choose a photo" picker instead of a
  /// live viewfinder, feeding the SAME crop/validation call and the SAME
  /// Navigator.pop result path _capture uses — see the class doc for why
  /// there must be exactly one of those, not two.
  Future<void> _pickPhoto() async {
    if (_busyCapturing) return;
    setState(() => _busyCapturing = true);
    try {
      const group = XTypeGroup(
        label: 'photo',
        extensions: ['jpg', 'jpeg', 'png'],
      );
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) {
        // Cancelled — not an error, matches _capture's own return-early style.
        if (mounted) setState(() => _busyCapturing = false);
        return;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;

      // Web's input is an arbitrary file from disk, not a bounded camera
      // frame — the extension filter above is cosmetic (any renamed file
      // passes it), so nothing before this point has actually looked at
      // what was picked. Two checks the native path never needs:
      //
      // 1) Size, BEFORE decoding. `cropToFaceCircle`'s pixel-by-pixel loop
      //    runs synchronously on the main isolate; decoding and cropping an
      //    arbitrarily large file (a multi-hundred-megapixel photo, a
      //    screenshot of a whole desktop) can visibly hang the tab with no
      //    feedback. Native has no such exposure because `ResolutionPreset
      //    .medium` bounds every frame before it ever reaches this file.
      //    The cap reuses `ManaPhotoPreset.loan.hardLimitBytes` rather than
      //    inventing a new number: this exact photo is uploaded through
      //    `live_photo_upload.dart` under `ManaPhotoPreset.loan`, so 1MB is
      //    already the ceiling the `live-photos` bucket enforces on the
      //    *compressed* result — a raw upload already past that figure is
      //    certainly not a normal doorstep face photo.
      if (bytes.length > ManaPhotoPreset.loan.hardLimitBytes) {
        setState(() {
          _busyCapturing = false;
          _error =
              'That file is too large (${(bytes.length / 1024).round()}KB). '
              'Please choose a smaller photo.';
        });
        return;
      }

      // 2) Decodability, BEFORE calling cropToFaceCircle. cropToFaceCircle
      //    deliberately falls back to returning undecodable bytes as-is —
      //    right for a live camera frame, where a failed decode is a rare
      //    glitch and an uncropped photo beats no photo at a doorstep. It is
      //    wrong here: an uploaded file that fails to decode is almost
      //    always not a photo at all (a PDF or text file renamed .jpg), and
      //    that fallback would silently store it as this customer's face
      //    photo with no error ever shown. So the web upload path checks
      //    decodability itself and refuses before reaching that fallback;
      //    cropToFaceCircle's own behaviour is untouched for the native
      //    caller that still needs it.
      if (img.decodeImage(bytes) == null) {
        setState(() {
          _busyCapturing = false;
          _error = 'That file is not a readable image. Please choose a '
              'different photo.';
        });
        return;
      }

      Navigator.of(context).pop(cropToFaceCircle(bytes));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyCapturing = false;
        _error = 'Could not open the selected photo: $e';
      });
    }
  }

  @override
  void dispose() {
    _faceDetector?.close();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Black, on purpose: this is a camera surface, and app chrome over a
      // viewfinder makes the preview look like a bug. The colours are the
      // exception the shared bar allows for exactly this.
      appBar: ManaAppBar(
        // live_photo, a key that exists. The old title was
        // ManaText('live photo capture') -- a key with SPACES that is in no
        // translation table, so it fell through to the key text and every
        // language got English.
        title: ref.t('live_photo'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: _initializing
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ManaText(_error!, style: const TextStyle(color: Colors.white)),
                    ),
                  )
                : kIsWeb
                    ? _buildWebPicker()
                    // _controller is null for a beat mid-flip, so the spinner
                    // covers that too rather than the preview
                    // force-unwrapping a controller that is being replaced.
                    : _controller == null
                        ? const Center(child: CircularProgressIndicator())
                        : Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(child: CameraPreview(_controller!)),
                      // The circle is not decoration: it is exactly what gets
                      // kept. Everything dimmed is discarded at capture, so
                      // what is framed is what is stored -- see
                      // cropToFaceCircle. Without it the preview promised a
                      // whole room and the file delivered one.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _FaceCircleMask(
                              ready: _faceDetected,
                            ),
                          ),
                        ),
                      ),
                      // Only when there is somewhere to flip TO. A button that
                      // does nothing on a single-camera handset is worse than
                      // no button.
                      if (_cameras.length > 1)
                        Positioned(
                          top: 16,
                          right: 16,
                          child: IconButton.filledTonal(
                            onPressed: _switching || _busyCapturing ? null : _flip,
                            icon: Icon(_switching
                                ? Icons.hourglass_empty
                                : Icons.cameraswitch_outlined),
                            tooltip: ref.t('switch_camera'),
                          ),
                        ),
                      Positioned(
                        bottom: 32,
                        child: Column(
                          children: [
                            ManaText(
                              _faceDetected
                                  ? 'Face detected — ready to capture'
                                  : 'Position your face in frame',
                              style: TextStyle(
                                color: _faceDetected ? Colors.greenAccent : Colors.orangeAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _faceDetected && !_busyCapturing ? _capture : null,
                              icon: const Icon(Icons.camera_alt, size: 28),
                              label: ManaText.raw(
                                _busyCapturing ? 'capturing...' : 'capture',
                                style: ManaType.sheetTitle,
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ManaColors.accent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: ManaColors.accent.withValues(alpha: 0.4),
                                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                                minimumSize: const Size(200, 56),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  /// Web's whole screen body: no viewfinder, because there is no camera to
  /// show one from (see class doc). Same black chrome, a plain explanation
  /// of why this control is different here, and the one action that feeds
  /// _pickPhoto — which rejoins _capture's own validation/result path.
  Widget _buildWebPicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            const ManaText.raw(
              'Live capture needs a phone camera. On a computer, choose a '
              'recent photo instead — the same photo rules apply.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _busyCapturing ? null : _pickPhoto,
              icon: const Icon(Icons.photo_library_outlined, size: 28),
              label: ManaText.raw(
                _busyCapturing ? 'opening...' : 'choose a photo',
                style: ManaType.sheetTitle,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: ManaColors.accent,
                foregroundColor: Colors.white,
                disabledBackgroundColor: ManaColors.accent.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                minimumSize: const Size(200, 56),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The captured frame, reduced to the circle the person was framed in.
///
/// The preview showed the whole camera frame, so what was stored was the
/// whole room: the doorstep, whoever else was standing there, the inside of
/// somebody's house. A face photo for identity should be a face, and every
/// pixel beyond it is somebody's else's business collected by accident.
///
/// Square crop about the centre first — the frame is portrait and the face is
/// centred, which is the same assumption the face-presence gate already
/// makes — then everything outside the inscribed circle is cleared. Returned
/// as PNG because the corners have to actually be transparent; a JPEG would
/// paint them black and quietly keep the same rectangle.
///
/// Falls back to the original bytes if they cannot be decoded. A photo that
/// is not cropped is worth more than no photo at a doorstep.
///
/// That reasoning holds for `_capture`'s camera frames (a decode failure
/// there is a rare hardware/codec glitch) and does NOT hold for
/// `_pickPhoto`'s web uploads (an undecodable upload is almost always not a
/// photo at all) — which is why `_pickPhoto` decodes and refuses bad input
/// itself before ever calling this function, rather than this fallback being
/// changed. Do not remove or tighten this fallback to "fix" the web case;
/// the native caller still depends on it exactly as written.
Uint8List cropToFaceCircle(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final square = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );

  final r = side / 2;
  for (var y = 0; y < square.height; y++) {
    for (var x = 0; x < square.width; x++) {
      final dx = x - r + 0.5;
      final dy = y - r + 0.5;
      if (dx * dx + dy * dy > r * r) {
        square.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(square));
}

/// Dims everything the capture will throw away, and rings what it keeps.
///
/// The ring turns green on the same condition the Capture button enables on,
/// so "am I allowed to press it yet" is answered where the person is already
/// looking rather than in a line of text below.
class _FaceCircleMask extends CustomPainter {
  final bool ready;
  const _FaceCircleMask({required this.ready});

  @override
  void paint(Canvas canvas, Size size) {
    // Matches cropToFaceCircle: the largest circle inside the centred square.
    final side = size.shortestSide;
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = side / 2;

    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: centre, radius: radius))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.6));
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ready ? Colors.greenAccent : Colors.white70,
    );
  }

  @override
  bool shouldRepaint(_FaceCircleMask oldDelegate) => oldDelegate.ready != ready;
}
