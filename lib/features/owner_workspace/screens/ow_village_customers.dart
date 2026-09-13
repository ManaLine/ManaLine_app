import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/components/mana_amount.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/bulk_onboarding_service.dart';
import '../state/customer_loan_entry.dart';
import '../state/village_book_summary.dart';

/// One village's customers, one per page, with their loans.
///
/// Seventeen people is a sitting an Owner can finish. Two hundred is not, which
/// is why the book is entered village by village -- and it is how the paper
/// book and the collection round are organised anyway.
class VillageCustomersScreen extends ConsumerStatefulWidget {
  final String businessId;

  /// What to call this village on screen. The out-of-area group passes its own
  /// heading rather than a village name.
  final String title;

  /// This village's rows, as the book list already fetched them. Passed in
  /// rather than re-queried: the list has them, and a second round trip on a
  /// village connection to redraw what is already on screen is latency for
  /// nothing.
  final List<ManaLoanPosition> positions;

  const VillageCustomersScreen({
    super.key,
    required this.businessId,
    required this.title,
    required this.positions,
  });

  @override
  ConsumerState<VillageCustomersScreen> createState() =>
      _VillageCustomersScreenState();
}

class _VillageCustomersScreenState
    extends ConsumerState<VillageCustomersScreen> {
  late final PageController _pages = PageController();
  late List<ManaLoanPosition> _positions = widget.positions;
  int _index = 0;

  /// MLIDs saved in this sitting, so a page says so rather than looking
  /// identical before and after.
  final Set<String> _savedNow = <String>{};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// The village's people, A to Z, each with whatever loans they already have.
  ///
  /// Distinct by person: the rows are per LOAN, so somebody with two loans
  /// appears twice in the source and must appear once here.
  List<_Customer> get _customers {
    final byPerson = <String, _Customer>{};
    for (final row in _positions) {
      final existing = byPerson[row.personId];
      byPerson[row.personId] = _Customer(
        personId: row.personId,
        mlid: row.mlid,
        fullName: row.fullName,
        loans: [...?existing?.loans, if (row.hasLoan) row],
      );
    }
    final list = byPerson.values.toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return list;
  }

  Future<void> _reload() async {
    final rows = await NetworkErrorHandler.run(context, () async {
      return ref
          .read(bulkOnboardingServiceProvider)
          .customerPositions(widget.businessId);
    });
    if (rows == null || !mounted) return;
    // Re-filtered to this village by the same key the list grouped on, so a
    // customer whose village changed under us does not silently appear here.
    final mine = widget.positions.isEmpty
        ? <ManaLoanPosition>[]
        : rows
            .where((r) =>
                r.village == widget.positions.first.village &&
                r.inOperatingArea == widget.positions.first.inOperatingArea)
            .toList();
    setState(() => _positions = mine);
  }

  Future<void> _addLoan(_Customer who) async {
    final entry = await showModalBottomSheet<ManaLoanEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LoanSheet(mlid: who.mlid, fullName: who.fullName),
    );
    if (entry == null || !mounted) return;

    final outcome = await NetworkErrorHandler.run(context, () async {
      return ref.read(bulkOnboardingServiceProvider).submitCustomerLoans(
            businessId: widget.businessId,
            rows: [entry.toRow()],
            // The key the entry was born with. Reused by every retry, which is
            // what makes a timeout safe -- see ManaLoanEntry.
            idempotencyKey: entry.idempotencyKey,
          );
    });
    if (outcome == null || !mounted) return;

    if (outcome.errors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(outcome.errors.first.message)),
      );
      return;
    }
    setState(() => _savedNow.add(who.mlid));
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final customers = _customers;

    return Scaffold(
      appBar: ManaAppBar(title: widget.title),
      body: SafeArea(
        child: customers.isEmpty
            ? Center(
                child: ManaText.raw(ref.t('nobody_in_this_stage_yet'),
                    style: ManaType.secondary),
              )
            : Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: customers.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (context, i) => _page(customers[i]),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: ManaSpacing.md),
                    child: ManaText.raw(
                      ref
                          .t('person_of_total')
                          .replaceAll('{n}', '${_index + 1}')
                          .replaceAll('{total}', '${customers.length}'),
                      style: ManaType.note,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _page(_Customer who) => ListView(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        children: [
          ManaText.raw(who.fullName, style: ManaType.sheetTitle),
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(who.mlid, style: ManaType.note),
          const SizedBox(height: ManaSpacing.lg),

          // What this person already carries. Shown before the button, because
          // the question an Owner asks at this page is "have I done them yet".
          if (who.loans.isNotEmpty) ...[
            ManaText.raw(
              ref
                  .t('loans_already_entered')
                  .replaceAll('{count}', '${who.loans.length}'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.xs),
            for (final loan in who.loans)
              Card(
                child: ListTile(
                  dense: true,
                  title: ManaAmount.compact(loan.balance,
                      semanticLabel: ref.t('remaining_balance')),
                  subtitle: ManaText.raw(
                    loan.lastCollection == null
                        ? ref.t('no_collections_yet')
                        : manaDisplayDate(loan.lastCollection),
                    style: ManaType.note,
                  ),
                ),
              ),
            const SizedBox(height: ManaSpacing.md),
          ],

          if (_savedNow.contains(who.mlid)) ...[
            ManaText.raw(ref.t('entered_in_this_sitting'),
                style: TextStyle(color: ManaColors.statusGood, fontSize: 13)),
            const SizedBox(height: ManaSpacing.sm),
          ],

          FilledButton.icon(
            onPressed: () => _addLoan(who),
            icon: const Icon(Icons.add, size: 18),
            label: ManaText.raw(ref.t('add_loan')),
          ),
        ],
      );
}

class _Customer {
  final String personId;
  final String mlid;
  final String fullName;
  final List<ManaLoanPosition> loans;
  const _Customer({
    required this.personId,
    required this.mlid,
    required this.fullName,
    required this.loans,
  });
}

/// The loan itself.
///
/// BALANCE AS IT STANDS TODAY, and no instalment history. MigrationPlan carries
/// an emiHistory flag precisely because some books record a running balance and
/// no history at all, and this door is for the Owner typing from paper on a
/// phone. app.migrate_loan derives what was collected as
/// `repayment - remaining`, so a balance alone is a complete, correct loan --
/// what it cannot do is reproduce the individual instalments, and the sheet
/// says so rather than letting somebody assume it has.
class _LoanSheet extends ConsumerStatefulWidget {
  final String mlid;
  final String fullName;
  const _LoanSheet({required this.mlid, required this.fullName});

  @override
  ConsumerState<_LoanSheet> createState() => _LoanSheetState();
}

class _LoanSheetState extends ConsumerState<_LoanSheet> {
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
