import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

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
class LivePhotoUpload {
  static Future<String> upload({
    required Uint8List bytes,
    required String businessId,
    required String pathSegment, // e.g. 'loans/<temp-id>' or 'persons/<person-id>'
    int expiresInSeconds = 60 * 60 * 24 * 365, // 1 year — see class doc caveat
  }) async {
    final db = Supabase.instance.client;
    final path = '$businessId/$pathSegment.jpg';

    await db.storage.from('live-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );

    return db.storage.from('live-photos').createSignedUrl(path, expiresInSeconds);
  }
}
