import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components/mana_amount.dart';
import '../../design/components/mana_app_bar.dart';
import '../../design/components/mana_text.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/tokens/typography.dart';
import '../mana_time.dart';
import '../translation_service.dart';
import 'mana_outbox.dart';
import 'mana_outbox_provider.dart';

/// Collections waiting to be saved.
///
/// The Owner's picture: "queue it until live, like WhatsApp messages.
/// Meanwhile user can delete, rewrite those queued entries." This is that
/// list -- what has not gone yet, why, and the two things that can be done
/// about it.
///
/// It exists because a queue nobody can see is indistinguishable from a
/// collection that was lost. The agent told a customer their money was
/// received; they are entitled to see that it is still on its way.
class ManaOutboxScreen extends ConsumerStatefulWidget {
  const ManaOutboxScreen({super.key});

  @override
  ConsumerState<ManaOutboxScreen> createState() => _ManaOutboxScreenState();
}

class _ManaOutboxScreenState extends ConsumerState<ManaOutboxScreen> {
  List<ManaOutboxEntry> _entries = const [];
  bool _loading = true;
  bool _flushing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final entries = await ref.read(manaOutboxProvider).pending();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _retryAll() async {
    setState(() => _flushing = true);
    await ref.read(manaOutboxProvider).flush();
    if (!mounted) return;
    setState(() => _flushing = false);
    await _load();
  }

  Future<void> _delete(ManaOutboxEntry e) async {
    // Asked, and named. Deleting a queued collection means the customer's
    // payment is not recorded anywhere, and the agent is the only person who
    // knows it happened.
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: ManaText.raw(ref.t('discard_queued_collection')),
        content: ManaText.raw(
          ref
              .t('discard_queued_collection_note')
              .replaceAll('{name}', e.customerName)
              .replaceAll('{amount}', manaRupees(e.collectedAmount)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: ManaText.raw(ref.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: ManaText.raw(ref.t('discard')),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await ref.read(manaOutboxProvider).remove(e.id);
    await _load();
  }

  Future<void> _edit(ManaOutboxEntry e) async {
    final controller = TextEditingController(text: '${e.collectedAmount}');
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: ManaText.raw(e.customerName),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: ref.t('collected_amount_field'),
            prefixText: '₹ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: ManaText.raw(ref.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v > 0) Navigator.pop(dialogContext, v);
            },
            child: ManaText.raw(ref.t('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted) return;

    // The edit replaces the entry under a NEW idempotency key -- see
    // ManaOutbox.edit. Re-sending a changed amount under the old key would
    // return the server's ORIGINAL answer and the correction would silently
    // not happen.
    await ref.read(manaOutboxProvider).edit(
      e.id,
      collectedAmount: amount,
      payload: {...e.payload, 'collected_amount': amount},
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(
        title: ref.t('waiting_to_be_saved'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _flushing ? null : _retryAll,
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                // Empty is the NORMAL state and should read as good news, not
                // as an error or an absence.
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(ManaSpacing.xxl),
                      child: ManaText.raw(ref.t('nothing_waiting_to_be_saved'),
                          textAlign: TextAlign.center,
                          style: ManaType.secondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    itemCount: _entries.length,
                    itemBuilder: (context, i) => _row(_entries[i]),
                  ),
      ),
    );
  }

  Widget _row(ManaOutboxEntry e) {
    final refused = e.state == ManaOutboxState.refused;
    final sending = e.state == ManaOutboxState.sending;
    final stuck = e.isStuck(attemptsAllowed: 3);

    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(
              switch (e.state) {
                ManaOutboxState.sending => Icons.upload_outlined,
                ManaOutboxState.refused => Icons.error_outline,
                _ => Icons.schedule,
              },
              color: refused
                  ? ManaColors.statusBad
                  : stuck
                      ? ManaColors.statusWarn
                      : ManaColors.textSecondary,
            ),
            title: ManaText.raw(e.customerName),
            subtitle: ManaText.raw(
              [
                manaRupees(e.collectedAmount),
                manaDisplayDate(DateTime.tryParse(e.createdAt) ?? manaNowIst()),
              ].join(' · '),
              style: ManaType.note,
            ),
            trailing: ManaText.raw(
              ref.t(switch (e.state) {
                ManaOutboxState.sending => 'outbox_sending',
                ManaOutboxState.refused => 'outbox_refused',
                _ => stuck ? 'outbox_stuck' : 'outbox_waiting',
              }),
              style: TextStyle(
                fontSize: 12,
                color: refused
                    ? ManaColors.statusBad
                    : stuck
                        ? ManaColors.statusWarn
                        : ManaColors.textSecondary,
              ),
            ),
          ),
          // THE SERVER'S OWN SENTENCE, not a paraphrase.
          // app.record_collection raises sixteen refusals and every one is
          // written to be read by a person. It is the only thing telling the
          // agent what to do next.
          if (e.lastError != null && (refused || stuck))
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.sm),
              child: ManaText.raw(e.lastError!,
                  style: refused ? ManaType.noteBad : ManaType.note),
            ),
          if (e.canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ManaSpacing.sm, 0, ManaSpacing.sm, ManaSpacing.xs),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _edit(e),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: ManaText.raw(ref.t('edit')),
                  ),
                  TextButton.icon(
                    onPressed: () => _delete(e),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: ManaText.raw(ref.t('discard')),
                  ),
                ],
              ),
            )
          else if (sending)
            // Locked, and said out loud rather than by absent buttons. During
            // an attempt nobody can tell "never arrived" from "arrived, reply
            // lost", and a change made now could reach the server under a key
            // it has already answered.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.sm),
              child: ManaText.raw(ref.t('outbox_sending_locked_note'),
                  style: ManaType.note),
            ),
        ],
      ),
    );
  }
}
