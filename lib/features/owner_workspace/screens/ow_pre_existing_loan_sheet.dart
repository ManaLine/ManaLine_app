import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/components/mana_text.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/bulk_onboarding_service.dart';
import '../state/customer_loan_entry.dart';

/// One pre-existing loan, typed out of a paper book.
///
/// SHARED, not copied. Two screens need it now -- the village book, where an
/// Owner works through a village at a time, and the global search, where a
/// customer has just been added and the next thing they want is that person's
/// existing balance. A second copy of a money form is how two screens end up
/// disagreeing about what interest is.
///
/// It collects; it does not write. [manaEnterPreExistingLoan] is the write,
/// and it goes through submitCustomerLoans -> app.import_migrated_loans ->
/// app.migrate_loan, which is the SAME path the bulk wizard uses. There is a
/// second door to migrate_loan that takes a customer_id directly; routing this
/// through the bulk one keeps the idempotency key, the row-level rejection
/// messages and the mlid resolution that the wizard already relies on, instead
/// of a second write path that has to be kept in step with it.

class ManaPreExistingLoanSheet extends ConsumerStatefulWidget {
  final String mlid;
  final String fullName;
  const ManaPreExistingLoanSheet(
      {super.key, required this.mlid, required this.fullName});

  @override
  ConsumerState<ManaPreExistingLoanSheet> createState() =>
      _ManaPreExistingLoanSheetState();
}

class _ManaPreExistingLoanSheetState extends ConsumerState<ManaPreExistingLoanSheet> {
  final _given = TextEditingController();
  final _repayment = TextEditingController();
  final _remaining = TextEditingController();
  final _instalment = TextEditingController();
  final _fee = TextEditingController();
  String _frequency = kManaRepaymentFrequencies.first;
  DateTime? _effective;
  DateTime? _graceEnd;

  List<ManaLoanProblem> _problems = const [];

  @override
  void dispose() {
    for (final c in [_given, _repayment, _remaining, _instalment, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  ManaLoanEntry? _build() {
    if (_effective == null) return null;
    return ManaLoanEntry(
      mlid: widget.mlid,
      amountGiven: _n(_given),
      repaymentAmount: _n(_repayment),
      remainingBalance: _n(_remaining),
      installmentAmount: _n(_instalment),
      // Absent, not zero: a zero fee changes the derived interest.
      processingFee: _fee.text.trim().isEmpty ? null : _n(_fee),
      repaymentType: _frequency,
      effectiveDate: _effective!,
      gracePeriodEndDate: _graceEnd,
    );
  }

  void _save() {
    final entry = _build();
    if (entry == null) return;
    final problems = entry.problems();
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }
    Navigator.of(context).pop(entry);
  }

  String _problemKey(ManaLoanProblem p) => switch (p) {
        ManaLoanProblem.negativeInterest => 'loan_problem_negative_interest',
        ManaLoanProblem.balanceAboveRepayment =>
          'loan_problem_balance_above_repayment',
        ManaLoanProblem.nothingOutstanding => 'loan_problem_nothing_outstanding',
        ManaLoanProblem.noInstalment => 'loan_problem_no_instalment',
        ManaLoanProblem.unknownFrequency => 'loan_problem_unknown_frequency',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            ManaText.raw(widget.fullName, style: ManaType.sheetTitle),
            ManaText.raw(ref.t('loan_details'), style: ManaType.note),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(ref.t('balance_only_note'), style: ManaType.note),
            const SizedBox(height: ManaSpacing.md),

            _money(_given, 'amount_given'),
            _money(_repayment, 'repayment_amount'),
            _money(_remaining, 'remaining_balance'),
            _money(_instalment, 'installment_amount'),
            _money(_fee, 'processing_fee'),

            const SizedBox(height: ManaSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              isExpanded: true,
              decoration:
                  InputDecoration(labelText: ref.t('repayment_type')),
              items: [
                for (final f in kManaRepaymentFrequencies)
                  DropdownMenuItem(value: f, child: ManaText.raw(f)),
              ],
              onChanged: (v) => setState(() => _frequency = v ?? _frequency),
            ),

            _date(ref.t('effective_date'), _effective,
                (d) => setState(() => _effective = d)),
            _date(ref.t('grace_period_end_date'), _graceEnd,
                (d) => setState(() => _graceEnd = d)),

            // EVERY problem, not the first. Fixing one number at a time and
            // being told about the next only after saving again is how a form
            // becomes a guessing game.
            if (_problems.isNotEmpty) ...[
              const SizedBox(height: ManaSpacing.md),
              for (final p in _problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: ManaText.raw(ref.t(_problemKey(p)),
                      style: ManaType.noteBad),
                ),
            ],

            const SizedBox(height: ManaSpacing.lg),
            FilledButton(
              // The date is the one field with no sensible default, so it
              // gates the button rather than being reported as a problem.
              onPressed: _effective == null ? null : _save,
              child: ManaText.raw(ref.t('save')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _money(TextEditingController c, String labelKey) => Padding(
        padding: const EdgeInsets.only(bottom: ManaSpacing.sm),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: ref.t(labelKey)),
          // Clears the stale complaints the moment a figure changes: leaving
          // them up while the Owner edits reads as the fix not working.
          onChanged: (_) {
            if (_problems.isNotEmpty) setState(() => _problems = const []);
          },
        ),
      );

  Widget _date(String label, DateTime? value, ValueChanged<DateTime> onPicked) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: ManaText.raw(label, style: ManaType.note),
        subtitle: ManaText.raw(
            value == null ? ref.t('choose_a_date') : manaDisplayDate(value)),
        trailing: const Icon(Icons.calendar_today_outlined, size: 18),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
          );
          if (picked != null) onPicked(picked);
        },
      );
}

/// Collect one pre-existing loan and save it, returning whether it landed.
///
/// The idempotency key is minted once when the entry is constructed and reused
/// by every retry -- see ManaLoanEntry -- which is what makes a timeout on a
/// village connection safe rather than a second loan.
Future<bool> manaEnterPreExistingLoan(
  BuildContext context,
  WidgetRef ref, {
  required String businessId,
  required String mlid,
  required String fullName,
}) async {
  final entry = await showModalBottomSheet<ManaLoanEntry>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ManaPreExistingLoanSheet(mlid: mlid, fullName: fullName),
  );
  if (entry == null || !context.mounted) return false;

  final outcome = await NetworkErrorHandler.run(context, () async {
    return ref.read(bulkOnboardingServiceProvider).submitCustomerLoans(
          businessId: businessId,
          rows: [entry.toRow()],
          idempotencyKey: entry.idempotencyKey,
        );
  });
  if (outcome == null || !context.mounted) return false;

  if (outcome.errors.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(outcome.errors.first.message)),
    );
    return false;
  }
  return true;
}
