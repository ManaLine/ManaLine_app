import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mana_line/shared/photo_compression.dart';

void main() {
  /// A noisy image, not a flat colour. A solid fill compresses to almost
  /// nothing at any quality, so it would make every size assertion pass
  /// regardless of whether the resize or the quality steps actually ran.
  Uint8List noisyJpeg(int w, int h, {int seed = 7, int quality = 100}) {
    final rnd = Random(seed);
    final im = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        im.setPixelRgb(x, y, rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
      }
    }
    return Uint8List.fromList(img.encodeJpg(im, quality: quality));
  }

  group('resizing', () {
    test('a large photo is brought down to the preset edge', () {
      final out = ManaPhotoCompressor.compress(
          noisyJpeg(2400, 1800), ManaPhotoPreset.loan);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, ManaPhotoPreset.loan.maxEdge);
      expect(decoded.height, 768); // aspect ratio preserved
    });

    test('a tall photo is measured on its longest edge', () {
      final out = ManaPhotoCompressor.compress(
          noisyJpeg(1200, 2400), ManaPhotoPreset.profile);
      final decoded = img.decodeImage(out)!;
      expect(decoded.height, ManaPhotoPreset.profile.maxEdge);
    });

    test('a small photo is never enlarged', () {
      // Scaling up adds bytes and no detail, which is the opposite of the
      // point of this class.
      final out = ManaPhotoCompressor.compress(
          noisyJpeg(300, 200), ManaPhotoPreset.loan);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, 300);
      expect(decoded.height, 200);
    });
  });

  group('size', () {
    test('a full-resolution photo lands under the bucket limit', () {
      // This is the case the whole feature exists for: a phone camera photo
      // that was previously uploaded untouched.
      final original = noisyJpeg(3000, 4000);
      final out =
          ManaPhotoCompressor.compress(original, ManaPhotoPreset.loan);
      expect(out.length, lessThan(ManaPhotoPreset.loan.hardLimitBytes));
      expect(out.length, lessThan(original.length));
    });

    test('a profile photo lands under its own, smaller limit', () {
      final out = ManaPhotoCompressor.compress(
          noisyJpeg(3000, 4000), ManaPhotoPreset.profile);
      expect(out.length, lessThan(ManaPhotoPreset.profile.hardLimitBytes));
    });

    test('a logo lands under its limit', () {
      final out = ManaPhotoCompressor.compress(
          noisyJpeg(3000, 3000), ManaPhotoPreset.logo);
      expect(out.length, lessThan(ManaPhotoPreset.logo.hardLimitBytes));
    });
  });

  group('refusal', () {
    test('bytes that are not an image are refused with a plain message', () {
      expect(
        () => ManaPhotoCompressor.compress(
            Uint8List.fromList([1, 2, 3, 4, 5]), ManaPhotoPreset.loan),
        throwsA(isA<PhotoUnreadableException>()),
      );
    });
  });

  group('presets', () {
    test('every preset targets below its own hard limit', () {
      // A target above the hard limit would mean the first encode "succeeds"
      // at a size the bucket rejects, and the quality steps would never run.
      for (final p in [
        ManaPhotoPreset.loan,
        ManaPhotoPreset.profile,
        ManaPhotoPreset.logo,
      ]) {
        expect(p.targetBytes, lessThan(p.hardLimitBytes));
        expect(p.quality, inInclusiveRange(1, 100));
        expect(p.maxEdge, greaterThan(0));
      }
    });

    test('hard limits match the bucket ceilings set in the migration', () {
      // storage.buckets.file_size_limit is set to exactly these numbers. If
      // they drift, the client starts accepting photos the server refuses and
      // the user sees a storage error instead of "take it again".
      expect(ManaPhotoPreset.loan.hardLimitBytes, 1048576); // live-photos
      expect(ManaPhotoPreset.profile.hardLimitBytes, 524288); // profile-photos
      expect(ManaPhotoPreset.logo.hardLimitBytes, 524288); // business-logos
    });
  });
}
