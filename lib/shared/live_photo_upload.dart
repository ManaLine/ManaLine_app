import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'photo_compression.dart';

/// Uploads captured live-photo bytes to the `live-photos` bucket
/// (migration 0023) and returns the object PATH, which is what belongs in
/// `loans.live_photo_url` / `persons.profile_photo_url`.
///
/// IT USED TO RETURN A SIGNED URL, VALID FOR A YEAR. That URL went into the
/// database, and a signed URL carries its own authorisation — so every one of
/// those rows was a link anybody who saw it could fetch for twelve months
/// with no login, no RLS and no way to revoke it short of deleting the
/// object. These are photographs of people's faces, taken as fraud evidence
/// at their own doorstep.
///
/// A path authorises nothing. ManaStoredFile.signedUrl mints a link when a
/// screen actually needs to show the image, and it is dead within minutes.
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

    return path;
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

    return path;
  }
}

/// The same choke point for `customer-documents` — the bucket behind
/// `customer_documents.file_url`.
///
/// The `<customer_id>/…` prefix is not cosmetic: the bucket's storage policies
/// read the customer id back out of the object name to decide whether the
/// caller covers that customer, so a path that does not start with the
/// customer's uuid is rejected rather than silently stored somewhere unreadable.
class CustomerDocumentUpload {
  static Future<String> upload({
    required Uint8List bytes,
    required String customerId,
    required String documentType,
    required int stamp, // manaNowIst().millisecondsSinceEpoch — see below
  }) async {
    final db = Supabase.instance.client;
    // Documents accumulate rather than overwrite: a customer can have an
    // Aadhaar photo AND an address proof AND a re-take of either. The stamp is
    // passed in rather than read here so this stays testable and so the IST
    // rule is applied by the caller that owns a clock, not re-derived.
    final slug = documentType.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final path = '$customerId/$slug-$stamp.jpg';

    final compressed =
        ManaPhotoCompressor.compress(bytes, ManaPhotoPreset.document);

    await db.storage.from('customer-documents').uploadBinary(
          path,
          compressed,
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );

    // The path, not a signed URL — identity documents least of all should be
    // sitting in a column as a year-long public link. See LivePhotoUpload.
    return path;
  }
}
