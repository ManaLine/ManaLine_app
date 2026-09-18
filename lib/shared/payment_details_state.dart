import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'photo_compression.dart';

/// The QR and UPI IDs a customer pays into — design document 2.2.1,
/// "Insert QR & UPI Id's to display ( In jpg < 1mb)".
///
/// The other half of 2.2.2. The app has been able to RECORD that money arrived
/// by GPay, PhonePe or Paytm since 2026-09-17, and had no way for anybody to
/// actually pay that way: an agent at a door could write down an online
/// payment but not show the customer where to send it.
///
/// OWNER WRITES, AGENT READS. Both live on `businesses`, which already carries
/// exactly those two rules — `businesses_owner_all` and
/// `businesses_member_select` — so nothing new was needed to authorise either
/// side.
class PaymentDetailsApiService {
  SupabaseClient get _db => Supabase.instance.client;

  Future<PaymentDetails> fetch(String businessId) async {
    final row = await _db
        .from('businesses')
        .select('upi_qr_path, upi_ids')
        .eq('business_id', businessId)
        .single();
    return PaymentDetails(
      qrPath: row['upi_qr_path'] as String?,
      upiIds: ((row['upi_ids'] as List?) ?? const []).cast<String>(),
    );
  }

  /// Uploads a QR and records its path.
  ///
  /// PNG GOES UP UNTOUCHED when it is already within the bucket's 1 MB. A QR
  /// is read by a machine, not a person: JPEG's artefacts sit exactly on the
  /// high-contrast edges the code is made of, and a re-encode buys nothing if
  /// the file already fits. Anything else is compressed with the `qr` preset,
  /// which is the highest quality in the app for the same reason.
  Future<String> uploadQr({
    required String businessId,
    required Uint8List bytes,
    required bool isPng,
  }) async {
    final underLimit = bytes.lengthInBytes <= ManaPhotoPreset.qr.hardLimitBytes;
    final keepAsPng = isPng && underLimit;
    final payload =
        keepAsPng ? bytes : ManaPhotoCompressor.compress(bytes, ManaPhotoPreset.qr);

    // The extension has to match what was actually sent, because the bucket
    // enforces the MIME type and would refuse a PNG announced as a JPEG.
    final path = '$businessId/payment-qr.${keepAsPng ? 'png' : 'jpg'}';
    await _db.storage.from('business-payment-qr').uploadBinary(
          path,
          payload,
          fileOptions: FileOptions(
            contentType: keepAsPng ? 'image/png' : 'image/jpeg',
            upsert: true,
          ),
        );

    await _db
        .from('businesses')
        .update({'upi_qr_path': path}).eq('business_id', businessId);
    return path;
  }

  /// Forgets the QR.
  ///
  /// The column is cleared and the object is left in the bucket. Deleting it
  /// would be the only irreversible thing in this flow, and an Owner who
  /// removes a QR by accident on a village connection deserves to be able to
  /// re-point at it. `upsert: true` above means re-uploading overwrites rather
  /// than accumulating, so nothing piles up.
  Future<void> clearQr(String businessId) => _db
      .from('businesses')
      .update({'upi_qr_path': null}).eq('business_id', businessId);

  /// Replaces the whole list.
  ///
  /// The server has the final say: `businesses_upi_ids_look_like_vpas` refuses
  /// any element that is not `something@something`. This sends the list as the
  /// Owner arranged it, because the order is the order the slip shows.
  Future<void> setUpiIds(String businessId, List<String> ids) => _db
      .from('businesses')
      .update({'upi_ids': ids}).eq('business_id', businessId);
}

class PaymentDetails {
  final String? qrPath;
  final List<String> upiIds;

  const PaymentDetails({this.qrPath, this.upiIds = const []});

  /// True when there is nothing to show a customer.
  ///
  /// Both halves are optional and independent: a business may have a QR and no
  /// typed handle, or handles and no QR. Only the absence of both is an empty
  /// screen.
  bool get isEmpty => (qrPath == null || qrPath!.isEmpty) && upiIds.isEmpty;
}

/// Whether a string is a plausible UPI virtual payment address.
///
/// THE SAME RULE THE DATABASE USES, deliberately — `app.upi_ids_are_valid`.
/// Loose on purpose: one `@`, something either side, no whitespace. Banks
/// invent handle suffixes constantly, so a stricter pattern would refuse valid
/// addresses and the refusal would land on an Owner who typed their own ID
/// correctly. This copy exists to say so before a round trip, not to be the
/// authority.
bool manaLooksLikeUpiId(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(value.trim());

final paymentDetailsApiServiceProvider =
    Provider<PaymentDetailsApiService>((ref) => PaymentDetailsApiService());

final paymentDetailsProvider =
    FutureProvider.autoDispose.family<PaymentDetails, String>(
  (ref, businessId) =>
      ref.read(paymentDetailsApiServiceProvider).fetch(businessId),
);
