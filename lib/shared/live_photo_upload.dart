import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'photo_compression.dart';

/// Uploads captured live-photo bytes to the `live-photos` bucket
/// (migration 0023) and returns a signed URL suitable for storing in
/// `loans.live_photo_url` / `persons.profile_photo_url`.
///
/// A signed URL (not a public URL — the bucket is private) is used since
/// these are fraud-prevention photos of real people, not general assets.
/// Signed URLs expire (`expiresInSeconds`) — if a screen needs to display
/// the photo long after upload, re-sign a fresh URL rather than assuming
/// the stored URL stays valid indefinitely. This is a real constraint of
/// the private-bucket choice, not an oversight — flagged for whoever
/// builds the "view past loan photos" screen later.
///
/// COMPRESSION HAPPENS HERE, not at the call sites. Loan photos are permanent
/// and one accumulates per loan, so an uncompressed upload is a cost that
/// never goes away. Putting it at the choke point means a new screen cannot
/// forget it; putting it in each caller means it only takes one to.
class LivePhotoUpload {
  static Future<String> upload({
    required Uint8List bytes,
    required String businessId,
    required String pathSegment, // e.g. 'loans/<temp-id>' or 'persons/<person-id>'
    ManaPhotoPreset preset = ManaPhotoPreset.loan,
    int expiresInSeconds = 60 * 60 * 24 * 365, // 1 year — see class doc caveat
  }) async {
    final db = Supabase.instance.client;
    final path = '$businessId/$pathSegment.jpg';

    // Throws PhotoTooLargeException / PhotoUnreadableException, which the
    // capture screens surface as "take it again". Deliberately not caught
    // here: uploading the original instead would defeat the whole point, and
    // silently succeeding with a 4MB file is exactly the kind of quiet wrong
    // this codebase avoids.
    final compressed = ManaPhotoCompressor.compress(bytes, preset);

    await db.storage.from('live-photos').uploadBinary(
          path,
          compressed,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );

    return db.storage.from('live-photos').createSignedUrl(path, expiresInSeconds);
  }
}

/// The same choke point for `profile-photos`.
///
/// Profile photos are overwritten rather than accumulated, so they are not the
/// storage cost driver — but they are uploaded from four different screens,
/// and before this each one called `storage.uploadBinary` directly with
/// whatever the picker returned.
class ProfilePhotoUpload {
  static Future<String> upload({
    required Uint8List bytes,
    required String personId,
    int expiresInSeconds = 60 * 60 * 24 * 365,
  }) async {
    final db = Supabase.instance.client;
    // photo.jpg, not profile.jpg: this is the path LR-007, OW-014 and OW-016
    // have always written. Changing it would orphan every photo already
    // uploaded and break the "a retry overwrites the original" behaviour
    // those screens rely on.
    final path = '$personId/photo.jpg';

    final compressed =
        ManaPhotoCompressor.compress(bytes, ManaPhotoPreset.profile);

    await db.storage.from('profile-photos').uploadBinary(
          path,
          compressed,
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );

    return db.storage.from('profile-photos').createSignedUrl(path, expiresInSeconds);
  }
}
