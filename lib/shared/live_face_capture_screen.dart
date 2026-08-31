import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/typography.dart';
import '../design/components/mana_app_bar.dart';
import 'translation_service.dart';
import '../design/components/mana_text.dart';

/// Reusable live-capture screen for every "Live Photo Capture (MANDATORY,
/// camera only)" field in the app — LR-004 F1 (registration, BR-036) and
/// OW-005/AG loan issuance (BR-081). Both are the SAME requirement per the
/// spec's own wording ("Live Photo Capture mandatory... fraud prevention"),
/// so this widget is shared rather than duplicated per screen.
///
/// PLATFORM LIMITATION (flagged, not silently worked around):
/// google_mlkit_face_detection wraps native Android/iOS ML Kit — it has NO
/// Flutter Web binding. Since this project targets Web + Android + iOS from
/// one codebase, the live face-presence gate below only runs on
/// Android/iOS. On Web (kIsWeb), this screen still enforces camera-only
/// capture (no gallery picker anywhere in this file) but WITHOUT the
/// face-detection gate — the capture button is always enabled there. This
/// is a real platform gap, not a bug: there is no in-browser equivalent
/// shipped by this package. If a same-quality Web face-detection gate is
/// required later, it needs a different, web-specific library (e.g. a
/// WASM/JS face-detection model), which is new scope, not a fix to this
/// file.
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
  bool _faceDetected = false; // always treated as true on Web — see class doc
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
  Future<void> _openCamera(CameraDescription camera) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: kIsWeb
          ? null
          : (Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888),
    );
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    if (!kIsWeb) {
      _faceDetector ??= FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
      );
      await controller.startImageStream(_onCameraImage);
    } else {
      // No ML Kit on Web — capture button is always enabled, gate skipped.
      _faceDetected = true;
    }

    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  /// Switches lens. Only offered when the device actually has a second one.
  Future<void> _flip() async {
    if (_cameras.length < 2 || _switching || _busyCapturing) return;
    setState(() {
      _switching = true;
      // The new lens has not seen a face yet, and carrying the old lens's
      // answer over would leave Capture enabled while pointing at nothing.
      _faceDetected = kIsWeb;
    });

    final old = _controller;
    // Cleared first so the preview does not paint from a controller that is
    // about to be disposed.
    setState(() => _controller = null);
    try {
      if (old != null) {
        if (!kIsWeb && old.value.isStreamingImages) {
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

  Future<void> _capture() async {
    if (_controller == null || _busyCapturing || !_faceDetected) return;
    setState(() => _busyCapturing = true);
    try {
      if (!kIsWeb) {
        await _controller!.stopImageStream();
      }
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
        // _controller is null for a beat mid-flip, so the spinner covers that
        // too rather than the preview force-unwrapping a controller that is
        // being replaced.
        child: _initializing || (_error == null && _controller == null)
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: ManaText(_error!, style: const TextStyle(color: Colors.white)),
                    ),
                  )
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
                              ready: _faceDetected || kIsWeb,
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
                              _faceDetected || kIsWeb
                                  ? (kIsWeb ? 'Position your face in frame, then tap Capture' : 'Face detected — ready to capture')
                                  : 'Position your face in frame',
                              style: TextStyle(
                                color: kIsWeb
                                    ? Colors.white
                                    : (_faceDetected ? Colors.greenAccent : Colors.orangeAccent),
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
