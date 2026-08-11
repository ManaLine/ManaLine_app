import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_amount.dart';
import '../../../shared/network_error_handler.dart';
import '../state/business_management_state.dart';
import '../state/customer_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// OW-018 — Pre-Existing Business Migration.
///
/// For a business that was already running before it joined MANA LINE.
/// The Owner states the old book: what is out with customers, and what has
/// already come back.
///
/// BF (confirmed with the Owner 2026-07-31) is CASH IN HAND:
///   BF = investment principal − amount given out + already collected
/// The money still owed by customers is the Line Balance and sits OUTSIDE
/// BF, because BF everywhere else in this app means a figure that can be
/// physically counted (day-ledger opening, agent BF, Zero Difference).
///
/// Gated on `migration_locked = false` (GLOBAL BR-159). A business that has
/// already pressed Start Business can be reopened deliberately — Owner PIN
/// path, typed reason, audit row — mirroring Reopen Closed Day.
class BusinessMigrationScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BusinessMigrationScreen({super.key, required this.businessId});

  @override
  ConsumerState<BusinessMigrationScreen> createState() => _BusinessMigrationScreenState();
}

class _BusinessMigrationScreenState extends ConsumerState<BusinessMigrationScreen> {
  MigrationSummary? _summary;
  int? _investorPayableBalance;
  int? _businessProfit;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(businessManagementApiServiceProvider);
      final s = await api.fetchMigrationSummary(businessId: widget.businessId);
      // Independent of BF and Line Balance above — see the two RPCs' own
      // doc comments in the P3 migration for why these are separate figures.
      final payable = await api.fetchInvestorPayableBalance(businessId: widget.businessId);
      final profit = await api.fetchBusinessProfit(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _investorPayableBalance = payable;
        _businessProfit = profit;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openBulkOnboarding() async {
    await context.push('/ow-bulk-onboarding', extra: widget.businessId);
    await _load();
  }

  Future<void> _reopen() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: ManaText.raw(ref.t('reopen_migration')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManaText.raw(
                ref.t('reopen_migration_note'),
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: InputDecoration(labelText: ref.t('reason_required_field')),
                onChanged: (_) => setLocal(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: ManaText.raw(ref.t('cancel'))),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, controller.text.trim()),
              child: ManaText.raw(ref.t('reopen')),
            ),
          ],
        ),
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(businessManagementApiServiceProvider)
          .reopenMigration(businessId: widget.businessId, reason: reason);
      return true;
    });
    if (ok == true) await _load();
  }

  Future<void> _lock() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('finish_migration_question')),
        content: ManaText.raw(ref.t('finish_migration_note')),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: ManaText.raw(ref.t('finish'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(businessManagementApiServiceProvider)
          .lockMigration(businessId: widget.businessId);
      return true;
    });
    if (ok == true) await _load();
  }

  Future<void> _addLoan() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _MigrateLoanScreen(businessId: widget.businessId)),
    );
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: AppBar(title: ManaText.raw(ref.t('pre_existing_business'))),
      floatingActionButton: (s != null && !s.migrationLocked)
          ? FloatingActionButton.extended(
              onPressed: _addLoan,
              icon: const Icon(Icons.add),
              label: ManaText.raw(ref.t('add_existing_loan')),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorState(_error!)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      children: [
                        _statusCard(s!),
                        const SizedBox(height: ManaSpacing.lg),
                        _bfCard(s),
                        const SizedBox(height: ManaSpacing.lg),
                        _profitCard(),
                        const SizedBox(height: ManaSpacing.lg),
                        if (!s.migrationLocked) ...[
                          OutlinedButton.icon(
                            onPressed: _openBulkOnboarding,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: ManaText.raw(ref.t('bulk_onboarding_wizard')),
                          ),
                          const SizedBox(height: ManaSpacing.md),
                        ],
                        if (!s.migrationLocked)
                          OutlinedButton(
                            onPressed: _lock,
                            child: ManaText.raw(ref.t('finish_migration')),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _errorState(String message) => ListView(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        children: [
          Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
          const SizedBox(height: ManaSpacing.md),
          Center(child: ManaText.raw(ref.t('could_not_load_migration_status'))),
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: ManaColors.statusBad)),
          const SizedBox(height: ManaSpacing.md),
          Center(child: ElevatedButton(onPressed: _load, child: ManaText.raw(ref.t('retry')))),
        ],
      );

  Widget _statusCard(MigrationSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ManaText.raw(ref.t(s.migrationLocked ? 'migration_closed' : 'migration_open'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(width: ManaSpacing.xs),
                Flexible(
                    child: ManaStatusPill(
                  label: ref.t(s.migrationLocked ? 'locked' : 'open_status'),
                  status: s.migrationLocked ? ManaStatus.neutral : ManaStatus.good,
                )),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              s.migrationLocked
                  ? ref.t('migration_locked_note').replaceAll(
                      '{date}',
                      s.businessStartedAt == null
                          ? ref.t('an_earlier_date')
                          : DateFormat('d MMM yyyy').format(s.businessStartedAt!))
                  : ref.t('migration_open_note'),
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.md),
            if (s.migrationLocked)
              OutlinedButton(onPressed: _reopen, child: ManaText.raw(ref.t('reopen_migration'))),
            if (!s.migrationLocked)
              ManaText.raw(
                  ref.t('pre_existing_loans_entered_note').replaceAll('{count}', '${s.migratedLoanCount}'),
                  style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// Declaring BF is a one-way act — the server refuses it once migration is
  /// locked — so the sheet says so before the Owner commits.
  Future<void> _declareBf(MigrationSummary s) async {
    final controller = TextEditingController(
        text: s.openingBfDeclaredAmount != null ? '${s.openingBfDeclaredAmount}' : '');
    final entered = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: ManaText.raw(ref.t('declare_opening_bf')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(
              ref.t('declare_opening_bf_note'),
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: ref.t('cash_in_hand_field')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: ManaText.raw(ref.t('declare')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (entered == null || entered < 0) return;
    if (!mounted) return;

    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(businessManagementApiServiceProvider).setOpeningBf(
            businessId: widget.businessId,
            amount: entered,
          );
      return true;
    });
    if (ok == true) await _load();
  }

  Widget _bfCard(MigrationSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          children: [
            // The old card listed Investment principal / Given out /
            // Collected above a divider, as if those summed to BF. They never
            // did — BF is read independently — and for a business funded by
            // its own retained profit, investment principal is 0, so the
            // breakdown visibly contradicted the total.
            //
            // BF is now what the Owner declared after counting the cash box,
            // so the card states that figure and when it was stated.
            Row(
              children: [
                Expanded(
                  child: ManaText.raw(ref.t('bf_cash_in_hand'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: ManaSpacing.xs),
                Flexible(child: ManaAmount(s.bf, semanticLabel: ref.t('bf_semantic_label'))),
              ],
            ),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              s.hasDeclaredBf
                  ? ref.t('bf_declared_on_note').replaceAll(
                          '{date}', DateFormat('d MMM yyyy').format(s.openingBfDeclaredOn!)) +
                      (s.migrationLocked ? ref.t('bf_locked_suffix') : '')
                  : ref.t('bf_not_declared_note'),
              style: TextStyle(
                fontSize: 13,
                color: s.hasDeclaredBf
                    ? ManaColors.textSecondary
                    : ManaColors.statusBad,
              ),
            ),
            if (!s.migrationLocked) ...[
              const SizedBox(height: ManaSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => _declareBf(s),
                icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                label: ManaText.raw(
                    ref.t(s.hasDeclaredBf ? 'change_opening_bf' : 'declare_opening_bf')),
              ),
            ],
            const Divider(),
            const SizedBox(height: ManaSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: ManaSpacing.sm, vertical: ManaSpacing.xs),
              decoration: BoxDecoration(
                color: ManaColors.brandFaint,
                borderRadius: BorderRadius.circular(ManaRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ManaText.raw(ref.t('line_balance_label'),
                        style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                  ),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(child: ManaAmount(s.lineBalance, size: ManaAmountSize.compact)),
                ],
              ),
            ),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              ref.t('line_balance_note'),
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }


  /// Two figures that are NOT BF and NOT Line Balance:
  ///   Investor Payable — what the business owes back to investors (principal
  ///   still standing plus interest not yet paid or compounded away).
  ///   Business Profit — interest+fee income minus expenses minus the
  ///   lifetime interest cost of investor capital.
  /// Kept as a separate card so neither is mistaken for cash in hand.
  Widget _profitCard() {
    final payable = _investorPayableBalance;
    final profit = _businessProfit;
    if (payable == null && profit == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('profit_and_investor_payable'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: ManaSpacing.sm),
            if (payable != null)
              Row(
                children: [
                  Expanded(child: ManaText.raw(ref.t('owed_back_to_investors'))),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(child: ManaAmount(payable, size: ManaAmountSize.compact)),
                ],
              ),
            if (profit != null) ...[
              const SizedBox(height: ManaSpacing.xs),
              Row(
                children: [
                  Expanded(child: ManaText.raw(ref.t('business_profit'))),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(
                    child: ManaAmount(profit,
                        size: ManaAmountSize.compact,
                        tone: profit < 0 ? ManaAmountTone.negative : ManaAmountTone.positive),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Pre-existing loan entry
// ============================================================================

class _MigrateLoanScreen extends ConsumerStatefulWidget {
  final String businessId;
  const _MigrateLoanScreen({required this.businessId});

  @override
  ConsumerState<_MigrateLoanScreen> createState() => _MigrateLoanScreenState();
}

class _MigrateLoanScreenState extends ConsumerState<_MigrateLoanScreen> {
  CustomerSummary? _customer;
  final _given = TextEditingController();
  final _interest = TextEditingController();
  final _fee = TextEditingController(text: '0');
  final _pending = TextEditingController();
  final _emi = TextEditingController();
  final _penalty = TextEditingController(text: '0');
  String _frequency = 'Weekly';
  DateTime _effectiveDate = DateTime.now().subtract(const Duration(days: 30));
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(customerListProvider.notifier).load(widget.businessId);
    });
  }

  @override
  void dispose() {
    for (final c in [_given, _interest, _fee, _pending, _emi, _penalty]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _givenV => int.tryParse(_given.text.trim());
  int? get _interestV => int.tryParse(_interest.text.trim());
  int get _feeV => int.tryParse(_fee.text.trim()) ?? 0;
  int? get _pendingV => int.tryParse(_pending.text.trim());
  int? get _emiV => int.tryParse(_emi.text.trim());
  int get _penaltyV => int.tryParse(_penalty.text.trim()) ?? 0;

  /// The whole obligation, DERIVED: the cash actually handed over plus the
  /// interest and fee that were withheld from it. Entering 19,600 given with
  /// 4,000 interest and 400 fee makes this 24,000, which is what the customer
  /// repays -- the 4,400 never left the till and so never returns to it as
  /// fresh cash. It reaches the business through the instalments instead.
  int? get _issuedV => (_givenV != null && _interestV != null)
      ? _givenV! + _interestV! + _feeV
      : null;

  /// Remaining balance is DERIVED, never typed. Typing it independently is
  /// what let the two halves of this form disagree -- a repayment of 10,000
  /// with 14,000 still owed was accepted into the fields and only caught at
  /// the very bottom of the screen.
  int? get _remainingV => (_pendingV != null && _emiV != null)
      ? _pendingV! * _emiV! + _penaltyV
      : null;

  /// What the customer has already handed over: the whole obligation minus
  /// what is still owed today.
  int? get _collected =>
      (_issuedV != null && _remainingV != null) ? _issuedV! - _remainingV! : null;

  String? get _validationError {
    if (_customer == null) return 'Choose the customer this loan belongs to.';
    if (_givenV == null || _interestV == null || _pendingV == null || _emiV == null) {
      return null; // incomplete, not wrong
    }
    if (_givenV! <= 0 || _emiV! <= 0) {
      return 'Amounts must be greater than zero.';
    }
    if (_interestV! < 0 || _feeV < 0) {
      return 'Interest and fee cannot be negative.';
    }
    if (_pendingV! <= 0) {
      return 'There must be at least one pending instalment.';
    }
    if (_penaltyV < 0) {
      return 'Penalty cannot be negative.';
    }
    if (_remainingV! > _issuedV!) {
      return 'The pending instalments come to ${_currency.format(_remainingV!)}, '
          'which is more than the ${_currency.format(_issuedV!)} issued.';
    }
    return null;
  }

  bool get _canSave =>
      _customer != null &&
      _givenV != null &&
      _interestV != null &&
      _pendingV != null &&
      _emiV != null &&
      _validationError == null &&
      !_saving;

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(businessManagementApiServiceProvider).migrateLoan(
            businessId: widget.businessId,
            customerId: _customer!.customerId,
            amountGiven: _givenV!,
            repaymentAmount: _issuedV!,
            remainingBalance: _remainingV!,
            effectiveDate: _effectiveDate,
            repaymentType: _frequency,
            installmentAmount: _emiV!,
            processingFee: _feeV,
          );
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customerListProvider).customers;
    return Scaffold(
      appBar: AppBar(title: ManaText.raw(ref.t('add_existing_loan'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            ManaText.raw(
              ref.t('add_existing_loan_note'),
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            DropdownButtonFormField<CustomerSummary>(
              initialValue: _customer,
              isExpanded: true,
              decoration: InputDecoration(labelText: ref.t('customer_required_field')),
              items: customers
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: ManaText.raw('${c.fullName} · ${c.mlid}',
                            style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _customer = v),
            ),
            const SizedBox(height: ManaSpacing.md),
            _amountField(_given, ref.t('amount_given_cash_field')),
            _amountField(_interest, ref.t('interest_required_field')),
            _amountField(_fee, ref.t('processing_fee_field')),
            _computedRow(ref.t('total_issued'), _issuedV, ref.t('total_issued_hint')),
            const SizedBox(height: ManaSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: InputDecoration(labelText: ref.t('repayment_frequency_field')),
              items: [
                DropdownMenuItem(value: 'Daily', child: ManaText.raw(ref.t('daily'))),
                DropdownMenuItem(value: 'Weekly', child: ManaText.raw(ref.t('weekly'))),
                DropdownMenuItem(value: 'Monthly', child: ManaText.raw(ref.t('monthly'))),
              ],
              onChanged: (v) => setState(() => _frequency = v ?? 'Weekly'),
            ),
            const SizedBox(height: ManaSpacing.md),
            _amountField(_pending, ref.t('pending_instalments_field')),
            _amountField(_emi, ref.t('instalment_amount_emi_field')),
            _amountField(_penalty, ref.t('penalty_outstanding_field')),
            _computedRow(ref.t('remaining_balance_label'), _remainingV, ref.t('remaining_balance_hint')),
            _computedRow(ref.t('already_paid'), _collected, ref.t('already_paid_hint')),
            const SizedBox(height: ManaSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: ManaText.raw(ref.t('original_start_date')),
              subtitle: ManaText.raw(DateFormat('d MMM yyyy').format(_effectiveDate)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _effectiveDate,
                  // Backdating is the whole point here, unlike OW-005.
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _effectiveDate = picked);
              },
            ),
            const Divider(height: ManaSpacing.xxl),
            _derivedCard(),
            if (_validationError != null && _customer != null) ...[
              const SizedBox(height: ManaSpacing.md),
              ManaText.raw(_validationError!,
                  style: TextStyle(fontSize: 13, color: ManaColors.statusBad)),
            ],
            const SizedBox(height: ManaSpacing.lg),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('save_existing_loan')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: ManaSpacing.md),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        ),
      );

  /// A value the Owner cannot type. Rendered like a disabled field so it reads
  /// as part of the form, but there is no controller behind it -- the number
  /// can only ever be what the inputs above imply.
  Widget _computedRow(String label, int? value, String hint) => Padding(
        padding: const EdgeInsets.only(bottom: ManaSpacing.md),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            helperText: hint,
            helperMaxLines: 2,
            filled: true,
            fillColor: ManaColors.surfaceSunken,
          ),
          child: ManaText.raw(
            value == null ? '—' : _currency.format(value),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      );

  Widget _derivedCard() {
    return Card(
      color: ManaColors.inkFaint,
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('what_this_records'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: ManaSpacing.sm),
            _derived(ref.t('already_collected'), _collected),
            _derived(ref.t('still_owed'), _remainingV),
            if (_pendingV != null && _pendingV! > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ManaText.raw(
                  ref.t('instalments_created_note').replaceAll('{count}', '$_pendingV'),
                  style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _derived(String label, int? value, {bool signed = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: ManaText.raw(label, style: const TextStyle(fontSize: 13))),
            ManaText.raw(
              value == null
                  ? '—'
                  : '${signed && value > 0 ? '+' : ''}${_currency.format(value)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: (signed && value != null && value < 0)
                    ? ManaColors.statusBad
                    : ManaColors.textPrimary,
              ),
            ),
          ],
        ),
      );
}
