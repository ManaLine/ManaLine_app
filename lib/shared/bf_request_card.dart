import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_amount.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import 'translation_service.dart';

/// What an Agent sees when a loan is refused for float.
///
/// Before this, the refusal was a red sentence and nothing else. The Agent is
/// standing in a village with a customer in front of them; "Insufficient agent
/// BF" told them what had happened and gave them nothing to do about it. The
/// only route was a phone call the app knew nothing about, leaving the Owner
/// with no record that anyone had asked.
///
/// So the two numbers are shown plainly -- what is in hand, what this loan
/// needs -- and the ask is prefilled with the difference, because that is the
/// figure the Agent would otherwise be working out on the spot. It stays
/// editable: an Agent who knows the next three loans in the round will ask for
/// enough to cover all of them.
class ManaBfRequestCard extends ConsumerStatefulWidget {
  final int available;
  final int required;

  /// The draft the refused loan was parked in, when it was saved. Shown so the
  /// Agent knows their typing is not gone; absent when the save itself failed,
  /// in which case saying nothing is honest.
  final String? savedDraftId;
  final Future<bool> Function(int amount, String? reason) onSend;

  const ManaBfRequestCard({
    super.key,
    required this.available,
    required this.required,
    required this.onSend,
    this.savedDraftId,
  });

  @override
  ConsumerState<ManaBfRequestCard> createState() => _ManaBfRequestCardState();
}

class _ManaBfRequestCardState extends ConsumerState<ManaBfRequestCard> {
  late final TextEditingController _amount;
  final _reason = TextEditingController();
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    // The shortfall, not the whole loan: the Agent already holds `available`,
    // and asking for the full amount on top of it would over-fund the round
    // and pull cash out of the Owner's till that nobody needed.
    final shortfall = widget.required - widget.available;
    _amount = TextEditingController(text: '${shortfall > 0 ? shortfall : widget.required}');
  }

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = int.tryParse(_amount.text.trim());
    if (value == null || value <= 0) return;
    setState(() => _sending = true);
    final ok = await widget.onSend(value, _reason.text.trim().isEmpty ? null : _reason.text.trim());
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.statusBadFaint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(
            'BF = ${manaRupees(widget.available)}   ·   '
            'This loan needs ${manaRupees(widget.required)}',
            style: ManaType.bad,
          ),
          if (widget.savedDraftId != null) ...[
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              'Saved as a draft. Nothing you entered is lost — it is waiting in '
              'Draft Transactions.',
              style: ManaType.note,
            ),
          ],
          const SizedBox(height: ManaSpacing.md),
          if (_sent)
            ManaText.raw(
              'Asked the Owner. You will be told whether it was granted.',
              style: ManaType.note,
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Request amount',
                      prefixText: '₹ ',
                    ),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ElevatedButton(
                  onPressed: _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(ref.t('send')),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ],
      ),
    );
  }
}
