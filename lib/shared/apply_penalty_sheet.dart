import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../design/components/mana_amount.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import 'network_error_handler.dart';
import 'translation_service.dart';

/// Apply a penalty. One number.
///
/// The old dialog asked for a penalty OPTION first -- Flat Amount, % of
/// Overdue Installment, % of Remaining Balance -- and only then for a figure.
/// Nobody thinks that way at a doorstep: the Owner decides this customer owes
/// another two hundred rupees. All three options ended in a rupee figure
/// anyway, and the server CEILs whatever arrives, so the choice only ever
/// changed which word was filed beside the amount.
///
/// app.apply_loan_penalty now defaults the option to 'Flat Amount'. The column
/// keeps its history; the person is simply not asked.
///
/// Returns true when a penalty was actually applied. The caller reloads on
/// true -- a penalty joins remaining_balance, so the round's figures move.
Future<bool> showApplyPenaltySheet(
  BuildContext context,
  WidgetRef ref, {
  required String loanId,
  required String customerName,
  required int outstandingBalance,
}) async {
  final applied = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _ApplyPenaltyBody(
      loanId: loanId,
      customerName: customerName,
      outstandingBalance: outstandingBalance,
    ),
  );
  return applied ?? false;
}

class _ApplyPenaltyBody extends ConsumerStatefulWidget {
  final String loanId;
  final String customerName;
  final int outstandingBalance;

  const _ApplyPenaltyBody({
    required this.loanId,
    required this.customerName,
    required this.outstandingBalance,
  });

  @override
  ConsumerState<_ApplyPenaltyBody> createState() => _ApplyPenaltyBodyState();
}

class _ApplyPenaltyBodyState extends ConsumerState<_ApplyPenaltyBody> {
  final _amount = TextEditingController();
  bool _saving = false;

  int get _value => int.tryParse(_amount.text.trim()) ?? 0;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (_value <= 0) return;
    setState(() => _saving = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      // p_penalty_option is defaulted server-side; the amount is the whole
      // input. The RPC enforces what the client cannot -- Owner of this
      // business, or an Agent with can_apply_penalty (off by default,
      // BR-236) -- and refuses a closed or fully repaid loan.
      await Supabase.instance.client.schema('app').rpc('apply_loan_penalty', params: {
        'p_loan_id': widget.loanId,
        'p_penalty_amount': _value,
      });
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    // Only close on success. A refusal -- closed loan, missing permission,
    // not yet past grace -- has already shown the server's own reason, and
    // dismissing the sheet would hide it.
    if (ok == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ManaSpacing.lg,
        0,
        ManaSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + ManaSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(ref.t('apply_penalty'), style: ManaType.cardTitle),
          const SizedBox(height: 2),
          ManaText.raw(
            '${widget.customerName} · ${ref.t('balance')} ${manaRupees(widget.outstandingBalance)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ManaType.note,
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: ref.t('penalty_amount'),
              prefixText: '₹ ',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: ManaSpacing.xs),
          // Said plainly, because it is the consequence people get wrong: a
          // penalty is not a note against the loan, it is money the customer
          // now owes.
          ManaText.raw(
            _value > 0
                ? '${ref.t('balance')} ${manaRupees(widget.outstandingBalance)} → '
                    '${manaRupees(widget.outstandingBalance + _value)}'
                : ref.t('penalty_adds_to_balance_note'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ManaType.note.copyWith(color: ManaColors.statusBad),
          ),
          const SizedBox(height: ManaSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_value > 0 && !_saving) ? _apply : null,
              child: _saving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(
                      _value > 0
                          ? '${ref.t('apply_penalty')} ${manaRupees(_value)}'
                          : ref.t('apply_penalty'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
