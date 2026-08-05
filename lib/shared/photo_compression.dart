import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// P4 photo compression — the client half of the storage cost model.
///
/// WHY THIS EXISTS: loan photos are permanent (one per loan, never deleted)
/// and were being uploaded at full sensor resolution. Every ImagePicker call
/// in the app passed `imageQuality: 85` with no `maxWidth`, and the live-photo
/// path uploaded whatever the camera produced. Storage was the accumulating
/// cost the subscription tiers are priced against, and nothing was bounding
/// it.
///
/// PRESETS, from the pricing model:
///   * loan photos    — 1024px longest edge, JPEG 75, target ~200KB
///   * profile photos —  800px longest edge, JPEG 70, target ~150KB
///
/// Profile photos are overwritten each time, so they do not accumulate; loan
/// photos do, which is why the loan preset is the one that matters for cost.
///
/// REJECT RATHER THAN SHIP SOMETHING HUGE. If the image cannot be brought
/// under the hard limit even at the lowest quality this will try, [compress]
/// throws. An image that will not compress is almost always a poor
/// verification photo anyway — a dark, noisy frame is exactly what defeats
/// JPEG — so refusing it and asking for a retake is better than storing a
/// megabyte of noise forever.
///
/// PURE DART, deliberately. The `image` package has no native code, so it
/// cannot repeat the AGP 9 build failure that removed file_picker.
class ManaPhotoPreset {
  /// Longest edge, in pixels. The image is scaled down to fit; it is never
  /// scaled UP, because enlarging a small photo adds bytes and no detail.
  final int maxEdge;

  /// Starting JPEG quality.
  final int quality;

  /// The size we aim for. Overshooting this is not fatal — [hardLimitBytes]
  /// is.
  final int targetBytes;

  /// The bucket's own ceiling. Encoding that cannot get under this is
  /// rejected, so the client never hands the server something the server
  /// would refuse.
  final int hardLimitBytes;

  const ManaPhotoPreset({
    required this.maxEdge,
    required this.quality,
    required this.targetBytes,
    required this.hardLimitBytes,
  });

  /// One per loan, permanent. The accumulating cost.
  static const loan = ManaPhotoPreset(
    maxEdge: 1024,
    quality: 75,
    targetBytes: 200 * 1024,
    hardLimitBytes: 1024 * 1024,
  );

  /// Overwritten each time, so it does not accumulate.
  static const profile = ManaPhotoPreset(
    maxEdge: 800,
    quality: 70,
    targetBytes: 150 * 1024,
    hardLimitBytes: 512 * 1024,
  );

  /// One per business, shown at 40px in the header — so it never needs to be
  /// large. It gets its own preset because logos are picked from the gallery,
  /// where a user is most likely to choose something at full resolution.
  static const logo = ManaPhotoPreset(
    maxEdge: 512,
    quality: 80,
    targetBytes: 100 * 1024,
    hardLimitBytes: 512 * 1024,
  );
}

class PhotoTooLargeException implements Exception {
  final String message;
  const PhotoTooLargeException(this.message);
  @override
  String toString() => message;
}

class PhotoUnreadableException implements Exception {
  final String message;
  const PhotoUnreadableException(this.message);
  @override
  String toString() => message;
}

class ManaPhotoCompressor {
  /// Quality steps tried in order when the first encode overshoots the
  /// target. Stops at 40 — below that a face photo stops being usable as
  /// verification, which is the entire point of storing it.
  static const _fallbackQualities = <int>[60, 50, 40];

  /// Resizes and re-encodes [bytes] as JPEG under [preset].
  ///
  /// Returns the encoded JPEG. Throws [PhotoUnreadableException] if the bytes
  /// are not a decodable image, and [PhotoTooLargeException] if no quality
  /// step gets under the hard limit.
  static Uint8List compress(Uint8List bytes, ManaPhotoPreset preset) {
    // decodeImage does not merely return null on rubbish input — it walks its
    // decoders looking for a match, and a malformed file makes one of them
    // throw before any of them declines. A truncated download surfaced as a
    // RangeError from the GIF decoder, which would reach the user as a crash
    // rather than "take it again". Both outcomes are the same thing to a
    // caller, so both become PhotoUnreadableException.
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      throw const PhotoUnreadableException(
          'That photo could not be read. Please take it again.');
    }
    if (decoded == null) {
      throw const PhotoUnreadableException(
          'That photo could not be read. Please take it again.');
    }

    // Only ever downscale. Scaling a 400px photo up to 1024px would add bytes
    // and no detail, which is the opposite of the point.
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final working = longest > preset.maxEdge
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? preset.maxEdge : null,
            height: decoded.height > decoded.width ? preset.maxEdge : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    var out = Uint8List.fromList(img.encodeJpg(working, quality: preset.quality));
    if (out.length <= preset.targetBytes) return out;

    for (final q in _fallbackQualities) {
      out = Uint8List.fromList(img.encodeJpg(working, quality: q));
      if (out.length <= preset.targetBytes) return out;
    }

    // Missing the soft target is acceptable; passing the bucket's hard limit
    // is not, because the upload would simply fail server-side and the user
    // would see a storage error instead of "take it again".
    if (out.length > preset.hardLimitBytes) {
      throw PhotoTooLargeException(
        'This photo is too large even after compressing '
        '(${(out.length / 1024).round()}KB). Please take it again in better '
        'light.',
      );
    }
    return out;
  }
}
