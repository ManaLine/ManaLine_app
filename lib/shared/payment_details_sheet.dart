import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_fit_text.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import 'payment_details_state.dart';
import 'stored_file.dart';
import 'translation_service.dart';

/// What an agent holds up at a door — design document 2.2.1.
///
/// THIS IS SHOWN TO SOMEBODY ELSE, which is the whole of its design. Every
/// other screen in this app is read by the person holding the phone; this one
/// is turned around and pointed at a customer standing outside in daylight,
/// who then has to scan it with their own phone. That is why the QR gets the
/// entire width, why there is no chrome competing with it, and why the screen
/// brightness matters more than the layout.
///
/// A QR is read by a MACHINE. It does not degrade gracefully — a code that is
/// slightly too small or slightly too soft does not scan at all, and the agent
/// finds out while the customer is waiting. So it is drawn as large as the
/// surface allows and never scaled down to make room for anything.
class PaymentDetailsSheet extends ConsumerWidget {
  final String businessId;
  const PaymentDetailsSheet({super.key, required this.businessId});

  static Future<void> open(BuildContext context, {required String businessId}) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => PaymentDetailsSheet(businessId: businessId),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(paymentDetailsProvider(businessId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(ManaSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => Padding(
            padding: const EdgeInsets.all(ManaSpacing.xxl),
            child: Center(
              child: ManaText.raw(ref.t('could_not_load_pull_to_retry'),
                  style: ManaType.secondary),
            ),
          ),
          data: (details) => _Body(details: details),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final PaymentDetails details;
  const _Body({required this.details});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (details.isEmpty) {
      // Two sentences: what is missing, and who can fix it. An agent cannot
      // add a QR themselves, so an empty screen that only said "nothing here"
      // would leave them with no next step at a door.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_2_outlined,
                size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('no_payment_details_yet'),
                textAlign: TextAlign.center, style: ManaType.secondary),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(ref.t('ask_owner_to_add_qr'),
                textAlign: TextAlign.center, style: ManaType.note),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ManaText.raw(ref.t('payment_details'), style: ManaType.sheetTitle),
        const SizedBox(height: ManaSpacing.md),
        if (details.qrPath != null && details.qrPath!.isNotEmpty)
          _Qr(path: details.qrPath!),
        if (details.upiIds.isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(ref.t('upi_ids'), style: ManaType.note),
          const SizedBox(height: ManaSpacing.xs),
          for (final id in details.upiIds) _UpiRow(id: id),
        ],
      ],
    );
  }
}

class _Qr extends StatelessWidget {
  final String path;
  const _Qr({required this.path});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      // A PATH, not a URL, is what the database stores — a signed URL in a
      // column is a link anybody who sees it can fetch until it expires. This
      // mints one that dies in minutes, at the moment the image is needed.
      future: ManaStoredFile.signedUrl(
        bucket: 'business-payment-qr',
        stored: path,
      ),
      builder: (context, snap) {
        // SQUARE, and as wide as the sheet allows. A QR scans by its module
        // size: shrinking it to leave room for something else is the one
        // change that stops it working, and nothing about that failure is
        // visible on this screen.
        return AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              // White behind it, always, whatever the theme. A QR inverted by
              // a dark background is unreadable to most scanners, and this
              // sheet is the one surface in the app that a STRANGER'S phone
              // has to read.
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(ManaSpacing.sm),
            child: snap.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : snap.data == null
                    ? Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: ManaColors.textSecondary),
                      )
                    : Image.network(snap.data!, fit: BoxFit.contain),
          ),
        );
      },
    );
  }
}

class _UpiRow extends ConsumerWidget {
  final String id;
  const _UpiRow({required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      // Tap to copy. A customer typing a handle off somebody else's screen
      // mistypes it, and a payment sent to a mistyped VPA either bounces or
      // reaches a stranger.
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: id));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: ManaText.raw(ref.t('copied'))),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
        child: Row(
          children: [
            // Flexible, so a long handle shrinks rather than pushing the copy
            // icon off a 360dp row.
            Flexible(child: ManaFitText(id, style: ManaType.emphasis)),
            const SizedBox(width: ManaSpacing.sm),
            Icon(Icons.copy_outlined, size: 18, color: ManaColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
