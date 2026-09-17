import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_amount.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../features/owner_workspace/state/loan_wizard_state.dart'
    show ManaFloatPosition;
import 'bf_request_card.dart';
import 'translation_service.dart';

/// What to do when the till is short, chosen by WHO is standing in front of it.
///
/// THE FINDING, in the Owner's words: "owner tried to issue loan with BF 0,
/// app asked to send request -- it's a blunder, according to role app should
/// behave, ask owner topup BF, ask agent to request to owner."
///
/// They are right, and the reason it happened is worth recording. The float
/// check is against the COLLECTING AGENT's cash -- correct, because that is
/// the hand the money leaves -- and the one remedy ever written was the
/// Agent's, because an Agent is who the refusal was designed for. An Owner
/// who names themselves as collection agent then meets an Agent's screen and
/// is offered a request to themselves. On the Stf book that is exactly what
/// happened: business BF 0, agent float 0, the same person on both sides.
///
/// THREE BRANCHES, NOT TWO. "Owner tops up" only works when the business has
/// the cash. When it does not there is nobody above the Owner to ask, and the
/// honest answer is to name where money enters a book rather than to offer a
/// button that would be refused.
///
/// NOT AN ERROR BOX. Nothing here is wrong: a loan that cannot be funded today
/// is a requirement that is not met. It carries the warn tone, not the bad
/// one, and the screen that shows it must not also raise a failure.
class ManaFloatGateCard extends ConsumerStatefulWidget {
  final ManaFloatPosition position;

  /// Amount Given -- what has to leave the agent's hand.
  final int needed;

  /// Who is collecting. Named rather than called "the agent", because on an
  /// Owner's screen it is usually one of several people and may be themselves.
  final String agentName;

  /// The draft a REFUSED loan was parked in. Null at the step-3 gate, where
  /// nothing has been spent yet and there is nothing to park -- and saying
  /// "saved as a draft" there would be a promise about a row that does not
  /// exist.
  final String? savedDraftId;

  /// The Owner's remedy. Returns true when the top-up landed and the wizard
  /// may carry on.
  final Future<bool> Function(int amount) onTopUp;

  /// The Agent's remedy, unchanged.
  final Future<bool> Function(int amount, String? reason) onRequest;

  const ManaFloatGateCard({
    super.key,
    required this.position,
    required this.needed,
    required this.agentName,
    required this.onTopUp,
    required this.onRequest,
    this.savedDraftId,
  });

  @override
  ConsumerState<ManaFloatGateCard> createState() => _ManaFloatGateCardState();
}

class _ManaFloatGateCardState extends ConsumerState<ManaFloatGateCard> {
  late final TextEditingController _amount = TextEditingController(
    // The shortfall, not the whole loan: the agent already holds what they
    // hold, and topping up the full amount on top of it would pull cash out
    // of the business that nobody needed.
    text: '${widget.needed - widget.position.agentAvailable}',
  );
  bool _working = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int get _shortfall => widget.needed - widget.position.agentAvailable;

  Future<void> _topUp() async {
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) return;
    setState(() => _working = true);
    final ok = await widget.onTopUp(amount);
    if (!mounted) return;
    setState(() => _working = false);
    if (!ok) return;
    // No snackbar on success: the wizard has already moved to the next step,
    // and a message about BF arriving over a guarantor form is noise.
  }

  @override
  Widget build(BuildContext context) {
    // The Agent's branch is the card that was already written for them, with
    // its own prefill and its own draft line. Reused rather than reproduced.
    if (!widget.position.viewerIsOwner) {
      return ManaBfRequestCard(
        available: widget.position.agentAvailable,
        required: widget.needed,
        savedDraftId: widget.savedDraftId,
        onSend: widget.onRequest,
      );
    }

    final canTopUp = widget.position.businessBf >= _shortfall;

    return Container(
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.statusWarnFaint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // THE TWO NUMBERS FIRST, and as money rather than as a sentence.
          // ManaAmount carries the 16sp floor and the tabular figures; these
          // are the figures the decision turns on.
          ManaText.raw(
            ref
                .t('loan_needs_note')
                .replaceAll('{needed}', manaRupees(widget.needed))
                .replaceAll('{name}', widget.agentName)
                .replaceAll('{available}',
                    manaRupees(widget.position.agentAvailable)),
            style: ManaType.strong,
          ),
          const SizedBox(height: ManaSpacing.sm),

          if (!widget.position.hasAssignment) ...[
            // Never set up is not the same as spent. An agent with no
            // assignment row has not run out of anything.
            ManaText.raw(
              ref
                  .t('agent_not_set_up_note')
                  .replaceAll('{name}', widget.agentName),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.sm),
          ],

          if (canTopUp) ...[
            ManaText.raw(
              ref
                  .t('top_up_agent_bf_note')
                  .replaceAll('{name}', widget.agentName),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.sm),
            // Row of a flexible field and a button: the field absorbs, the
            // button keeps its intrinsic width. A fixed child beside a
            // flexible one is this project's recurring overflow, and this is
            // the shape that causes it.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: ref.t('amount'),
                      prefixText: '₹ ',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                FilledButton(
                  onPressed: _working ? null : _topUp,
                  child: _working
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(ref.t('top_up_agent_bf')),
                ),
              ],
            ),
          ] else ...[
            // NO BUTTON, deliberately. app.grant_agent_bf would refuse this
            // and say so, and offering a control that cannot work is how the
            // request-to-yourself got shipped in the first place.
            ManaText.raw(ref.t('business_bf_empty_headline'),
                style: ManaType.strong),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              ref.t('business_bf_empty_note').replaceAll(
                  '{available}', manaRupees(widget.position.businessBf)),
              style: ManaType.note,
            ),
          ],
        ],
      ),
    );
  }
}
