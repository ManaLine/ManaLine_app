import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../state/business_transfer_state.dart';

/// P4 Business Transfer.
///
/// One screen for both sides, because a person can be on either at once — an
/// Owner handing one business over may simultaneously be offered another. Two
/// screens would mean two places to look for the same kind of thing.
///
/// Offers made and offers received are separated visually, because the actions
/// are not interchangeable: cancelling something you offered and accepting
/// something offered to you are opposite decisions, and putting them in one
/// undifferentiated list is how someone taps the wrong one.
class BusinessTransferScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BusinessTransferScreen({super.key, required this.businessId});

  @override
  ConsumerState<BusinessTransferScreen> createState() =>
      _BusinessTransferScreenState();
}

class _BusinessTransferScreenState
    extends ConsumerState<BusinessTransferScreen> {
  final _mlid = TextEditingController();
  final _note = TextEditingController();
  TransferCandidate? _found;
  bool _busy = false;
  String? _lookupError;

  @override
  void dispose() {
    _mlid.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final id = _mlid.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _busy = true;
      _found = null;
      _lookupError = null;
    });

    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(businessTransferApiServiceProvider).findByMlid(id);
    });

    if (!mounted) return;
    setState(() {
      _busy = false;
      _found = result;
      // A wrong MLID is the likeliest mistake here, and it must not look like
      // a network failure.
      if (result == null) _lookupError = 'No one found with MLID "$id".';
    });
  }

  Future<void> _offer() async {
    final person = _found;
    if (person == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('transfer_this_business_question')),
        content: ManaText.raw(
          '${person.fullName} (${person.mlid}) will be asked to accept. '
          'Nothing changes until they do.\n\n'
          'When they accept, this business leaves your account completely — '
          'including your agent role in it.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: ManaText.raw(ref.t('send_offer'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final done = await NetworkErrorHandler.run(context, () async {
      await ref.read(businessTransferApiServiceProvider).offer(
            businessId: widget.businessId,
            toPersonId: person.personId,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      return true;
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (done == true) {
        _found = null;
        _mlid.clear();
        _note.clear();
      }
    });
    if (done == true) ref.invalidate(businessTransfersProvider);
  }

  Future<void> _respond(BusinessTransfer t, bool accept) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText(accept ? 'take over this business?' : 'decline?'),
        content: ManaText.raw(accept
            ? 'You become the owner of ${t.businessName}, including its '
                'agents, customers, investors and everything they owe. '
                'This cannot be undone from here.'
            : '${t.counterparty} will be told you declined.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: ManaText.raw(accept ? 'Accept' : 'Decline')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final done = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(businessTransferApiServiceProvider)
          .respond(transferId: t.transferId, accept: accept);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (done == true) ref.invalidate(businessTransfersProvider);
  }

  Future<void> _cancel(BusinessTransfer t) async {
    setState(() => _busy = true);
    final done = await NetworkErrorHandler.run(context, () async {
      await ref.read(businessTransferApiServiceProvider).cancel(t.transferId);
      return true;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (done == true) ref.invalidate(businessTransfersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final transfers = ref.watch(businessTransfersProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: ManaText.raw(ref.t('business_transfer')),
      ),
      body: SafeArea(
        child: transfers.when(
          loading: () => const ManaSkeletonList(itemCount: 3, itemHeight: 110),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.xl),
              child: ManaText.raw('$e',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: ManaColors.statusBad)),
            ),
          ),
          data: (all) {
            final incoming =
                all.where((t) => t.isIncoming && t.isPending).toList();
            final outgoing =
                all.where((t) => !t.isIncoming && t.isPending).toList();

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(businessTransfersProvider),
              child: ListView(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                children: [
                  if (incoming.isNotEmpty) ...[
                    ManaText.raw(ref.t('offered_to_you'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: ManaSpacing.sm),
                    for (final t in incoming)
                      _OfferCard(
                        transfer: t,
                        busy: _busy,
                        primaryLabel: 'accept',
                        onPrimary: () => _respond(t, true),
                        secondaryLabel: 'decline',
                        onSecondary: () => _respond(t, false),
                      ),
                    const SizedBox(height: ManaSpacing.lg),
                  ],
                  if (outgoing.isNotEmpty) ...[
                    ManaText.raw(ref.t('waiting_to_be_accepted'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: ManaSpacing.sm),
                    for (final t in outgoing)
                      _OfferCard(
                        transfer: t,
                        busy: _busy,
                        secondaryLabel: 'cancel offer',
                        onSecondary: () => _cancel(t),
                      ),
                    const SizedBox(height: ManaSpacing.lg),
                  ],

                  ManaText.raw(ref.t('hand_business_to_someone'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: ManaSpacing.xs),
                  ManaText.raw(
                    ref.t('transfer_business_note'),
                    style: TextStyle(
                        fontSize: 13, color: ManaColors.textSecondary),
                  ),
                  const SizedBox(height: ManaSpacing.sm),
                  TextField(
                    controller: _mlid,
                    decoration: InputDecoration(
                      labelText: ref.t('their_mlid_field'),
                      hintText: 'MLPI...',
                    ),
                    onSubmitted: (_) => _find(),
                  ),
                  const SizedBox(height: ManaSpacing.sm),
                  OutlinedButton(
                    onPressed: _busy ? null : _find,
                    child: ManaText.raw(ref.t('find_person')),
                  ),
                  if (_lookupError != null) ...[
                    const SizedBox(height: ManaSpacing.sm),
                    ManaText.raw(_lookupError!,
                        style: TextStyle(
                            fontSize: 13, color: ManaColors.statusBad)),
                  ],
                  if (_found != null) ...[
                    const SizedBox(height: ManaSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(ManaSpacing.md),
                      decoration: BoxDecoration(
                        color: ManaColors.brandFaint,
                        borderRadius: BorderRadius.circular(ManaRadius.md),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ManaText.raw(_found!.fullName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          ManaText.raw(_found!.mlid,
                              style: const TextStyle(fontSize: 13)),
                          if (_found!.mobile.isNotEmpty)
                            ManaText.raw(_found!.mobile,
                                style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: ManaSpacing.sm),
                    TextField(
                      controller: _note,
                      decoration: InputDecoration(
                        labelText: ref.t('note_optional_field'),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: ManaSpacing.sm),
                    ElevatedButton(
                      onPressed: _busy ? null : _offer,
                      child: ManaText.raw(ref.t('send_offer')),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: ManaSpacing.lg),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final BusinessTransfer transfer;
  final bool busy;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _OfferCard({
    required this.transfer,
    required this.busy,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.surface,
        borderRadius: BorderRadius.circular(ManaRadius.md),
        border: Border.all(color: ManaColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(transfer.businessName,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          ManaText.raw(transfer.mlbi,
              style: TextStyle(
                  fontSize: 13, color: ManaColors.textSecondary)),
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(
            transfer.isIncoming
                ? 'From ${transfer.counterparty} (${transfer.counterpartyMlid})'
                : 'To ${transfer.counterparty} (${transfer.counterpartyMlid})',
            style: const TextStyle(fontSize: 13),
          ),
          if (transfer.note != null && transfer.note!.isNotEmpty) ...[
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw('"${transfer.note}"',
                style: TextStyle(
                    fontSize: 13, color: ManaColors.textSecondary)),
          ],
          const SizedBox(height: ManaSpacing.sm),
          // Wrap, not Row: two buttons with translated labels beside each
          // other is the shape that overflows at 2.0x on a 360dp screen.
          Wrap(
            spacing: ManaSpacing.sm,
            runSpacing: ManaSpacing.xs,
            children: [
              if (primaryLabel != null)
                ElevatedButton(
                  onPressed: busy ? null : onPrimary,
                  child: ManaText(primaryLabel!),
                ),
              if (secondaryLabel != null)
                OutlinedButton(
                  onPressed: busy ? null : onSecondary,
                  child: ManaText(secondaryLabel!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
