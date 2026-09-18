import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../design/components/mana_app_bar.dart';
import '../design/components/mana_fit_text.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import 'network_error_handler.dart';
import 'payment_details_state.dart';
import 'stored_file.dart';
import 'translation_service.dart';

/// Where the Owner puts the QR and the UPI IDs — design document 2.2.1.
///
/// Set once here, shown at every door by the agent. It lives under business
/// settings rather than under Areas or Agents because it belongs to the book:
/// a business collects into its own account whoever happens to be walking the
/// round.
///
/// FROM THE GALLERY, NOT THE CAMERA. Every other image in this app is a live
/// capture, deliberately — a face photographed at a doorstep is evidence, and
/// `LiveFaceCaptureScreen` has no gallery path on purpose. A QR is the
/// opposite: it already exists as a file in the Owner's payment app, and
/// photographing a screen would introduce exactly the blur that stops it
/// scanning.
class PaymentDetailsEditor extends ConsumerStatefulWidget {
  final String businessId;
  const PaymentDetailsEditor({super.key, required this.businessId});

  static Future<void> open(BuildContext context,
          {required String businessId}) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PaymentDetailsEditor(businessId: businessId),
      ));

  @override
  ConsumerState<PaymentDetailsEditor> createState() =>
      _PaymentDetailsEditorState();
}

class _PaymentDetailsEditorState extends ConsumerState<PaymentDetailsEditor> {
  final _newId = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _newId.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(paymentDetailsProvider(widget.businessId));

  Future<void> _pickQr() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    setState(() => _busy = true);
    // PNG stays PNG when it already fits. The service decides, not this
    // screen, so the rule lives in one place -- but the extension is what
    // tells it, and a picker on Android reports the real one.
    final isPng = picked.path.toLowerCase().endsWith('.png');
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(paymentDetailsApiServiceProvider).uploadQr(
            businessId: widget.businessId,
            bytes: Uint8List.fromList(bytes),
            isPng: isPng,
          );
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) _refresh();
  }

  Future<void> _removeQr() async {
    setState(() => _busy = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(paymentDetailsApiServiceProvider)
          .clearQr(widget.businessId);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) _refresh();
  }

  Future<void> _setIds(List<String> ids) async {
    setState(() => _busy = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(paymentDetailsApiServiceProvider)
          .setUpiIds(widget.businessId, ids);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) _refresh();
  }

  Future<void> _addId(List<String> existing) async {
    final value = _newId.text.trim();
    // Checked here to name the problem before a round trip; the database has
    // the final say via businesses_upi_ids_look_like_vpas.
    if (!manaLooksLikeUpiId(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('upi_id_invalid'))),
      );
      return;
    }
    if (existing.contains(value)) {
      _newId.clear();
      return;
    }
    _newId.clear();
    await _setIds([...existing, value]);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(paymentDetailsProvider(widget.businessId));

    return Scaffold(
      appBar: ManaAppBar(
        title: ref.t('payment_details'),
        homeRoute: '/ow-001',
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: ManaText.raw(ref.t('could_not_load_pull_to_retry'),
                style: ManaType.secondary),
          ),
          data: (details) => ListView(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            children: [
              ManaText.raw(ref.t('payment_qr'), style: ManaType.strong),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(ref.t('qr_keep_it_sharp'), style: ManaType.note),
              const SizedBox(height: ManaSpacing.sm),
              _QrPreview(path: details.qrPath),
              const SizedBox(height: ManaSpacing.sm),
              // Wrap, not Row. Two buttons and a long Telugu label do not
              // share a 360dp line, and this project has shipped that overflow
              // four times.
              Wrap(
                spacing: ManaSpacing.sm,
                runSpacing: ManaSpacing.xs,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _pickQr,
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: ManaText.raw(details.qrPath == null
                        ? ref.t('upload_qr')
                        : ref.t('replace_qr')),
                  ),
                  if (details.qrPath != null)
                    TextButton(
                      onPressed: _busy ? null : _removeQr,
                      child: ManaText.raw(ref.t('remove_qr')),
                    ),
                ],
              ),

              const SizedBox(height: ManaSpacing.xl),
              ManaText.raw(ref.t('upi_ids'), style: ManaType.strong),
              const SizedBox(height: ManaSpacing.xs),
              for (final id in details.upiIds)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: ManaFitText(id),
                  trailing: IconButton(
                    icon: Icon(Icons.close, color: ManaColors.statusBad),
                    onPressed: _busy
                        ? null
                        : () => _setIds(
                            details.upiIds.where((e) => e != id).toList()),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newId,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: ref.t('upi_id'),
                        hintText: ref.t('upi_id_hint'),
                      ),
                      onSubmitted: (_) => _addId(details.upiIds),
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: ref.t('add_upi_id'),
                    onPressed: _busy ? null : () => _addId(details.upiIds),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrPreview extends StatelessWidget {
  final String? path;
  const _QrPreview({required this.path});

  @override
  Widget build(BuildContext context) {
    if (path == null || path!.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: ManaColors.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Icon(Icons.qr_code_2_outlined,
              size: 40, color: ManaColors.textSecondary),
        ),
      );
    }
    return FutureBuilder<String?>(
      future: ManaStoredFile.signedUrl(
        bucket: 'business-payment-qr',
        stored: path,
      ),
      builder: (context, snap) => Container(
        height: 160,
        // White behind it here too: the Owner is checking the thing an agent
        // will hold up, and it must look the same in both places.
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(ManaSpacing.sm),
        child: snap.data == null
            ? const Center(child: CircularProgressIndicator())
            : Image.network(snap.data!, fit: BoxFit.contain),
      ),
    );
  }
}
