import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
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
      final s = await ref
          .read(businessManagementApiServiceProvider)
          .fetchMigrationSummary(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _summary = s;
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

  Future<void> _reopen() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const ManaText('reopen migration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ManaText.raw(
                'This business has already been started. Reopening lets you '
                'enter pre-existing records again. The reason is recorded in '
                'the audit log.',
                style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason (required)'),
                onChanged: (_) => setLocal(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const ManaText('cancel')),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const ManaText('reopen'),
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
        title: const ManaText('finish migration?'),
        content: const ManaText.raw(
          'Pre-existing record entry will be closed and the business marked '
          'Active. You can reopen migration later if something was missed, '
          'but every reopen is recorded.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const ManaText('cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const ManaText('finish')),
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
      appBar: AppBar(title: const ManaText('pre-existing business')),
      floatingActionButton: (s != null && !s.migrationLocked)
          ? FloatingActionButton.extended(
              onPressed: _addLoan,
              icon: const Icon(Icons.add),
              label: const ManaText('add existing loan'),
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
                        if (!s.migrationLocked)
                          OutlinedButton(
                            onPressed: _lock,
                            child: const ManaText('finish migration'),
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
          const Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
          const SizedBox(height: ManaSpacing.md),
          const Center(child: ManaText('could not load migration status')),
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: ManaColors.statusBad)),
          const SizedBox(height: ManaSpacing.md),
          Center(child: ElevatedButton(onPressed: _load, child: const ManaText('retry'))),
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
                  child: ManaText(s.migrationLocked ? 'migration closed' : 'migration open',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                ManaStatusPill(
                  label: s.migrationLocked ? 'Locked' : 'Open',
                  status: s.migrationLocked ? ManaStatus.neutral : ManaStatus.good,
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              s.migrationLocked
                  ? 'This business was started on '
                      '${s.businessStartedAt == null ? 'an earlier date' : DateFormat('d MMM yyyy').format(s.businessStartedAt!)}. '
                      'Reopen migration to enter records from the old book.'
                  : 'Enter the loans that were already running when you joined. '
                      'Each one records what you gave out and what has come back.',
              style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.md),
            if (s.migrationLocked)
              OutlinedButton(onPressed: _reopen, child: const ManaText('reopen migration')),
            if (!s.migrationLocked)
              ManaText.raw('${s.migratedLoanCount} pre-existing loans entered',
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
        title: const ManaText('declare opening bf'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ManaText.raw(
              'Count the cash box today and enter that figure. Everything '
              'before today is out of scope — the count already reflects it.\n\n'
              'This locks when you finish migration and cannot be changed '
              'afterwards.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Cash in hand *'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const ManaText('cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: const ManaText('declare'),
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
                const Expanded(
                  child: ManaText('BF — cash in hand',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ManaAmount(s.bf, semanticLabel: 'Brought forward, cash in hand'),
              ],
            ),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              s.hasDeclaredBf
                  ? 'Declared on ${DateFormat('d MMM yyyy').format(s.openingBfDeclaredOn!)}'
                    '${s.migrationLocked ? ' — locked' : ''}'
                  : 'Not declared yet. Count the cash box and enter it below.',
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
                label: ManaText(
                    s.hasDeclaredBf ? 'change opening bf' : 'declare opening bf'),
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
                  const Expanded(
                    child: ManaText.raw('Line balance — still with customers',
                        style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                  ),
                  ManaAmount(s.lineBalance, size: ManaAmountSize.compact),
                ],
              ),
            ),
            const SizedBox(height: ManaSpacing.xs),
            const ManaText.raw(
              'Line balance is deliberately outside BF — that money is out on '
              'the line, not in the cash box.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
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
      appBar: AppBar(title: const ManaText('add existing loan')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            const ManaText.raw(
              'Enter the loan as it stands today. The repayment schedule is '
              'created from today forward for whatever is still owed — past '
              'instalments are not recreated, so the customer\'s Line Score '
              'starts from here.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            DropdownButtonFormField<CustomerSummary>(
              initialValue: _customer,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Customer *'),
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
            _amountField(_given, 'Amount Given * — cash you handed over'),
            _amountField(_interest, 'Interest *'),
            _amountField(_fee, 'Processing Fee'),
            _computedRow('Total Issued', _issuedV,
                'the whole obligation = given + interest + fee'),
            const SizedBox(height: ManaSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(labelText: 'Repayment Frequency'),
              items: const ['Daily', 'Weekly', 'Monthly']
                  .map((f) => DropdownMenuItem(value: f, child: ManaText.raw(f)))
                  .toList(),
              onChanged: (v) => setState(() => _frequency = v ?? 'Weekly'),
            ),
            const SizedBox(height: ManaSpacing.md),
            _amountField(_pending, 'Pending Instalments * — how many are left'),
            _amountField(_emi, 'Instalment Amount (EMI) *'),
            _amountField(_penalty, 'Penalty Outstanding'),
            _computedRow('Remaining Balance', _remainingV,
                'still owed today = pending x EMI + penalty'),
            _computedRow('Already Paid', _collected,
                'total issued - remaining balance'),
            const SizedBox(height: ManaSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const ManaText('original start date'),
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
                  style: const TextStyle(fontSize: 13, color: ManaColors.statusBad)),
            ],
            const SizedBox(height: ManaSpacing.lg),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const ManaText('save existing loan'),
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
            const ManaText('what this records',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: ManaSpacing.sm),
            _derived('Already collected', _collected),
            _derived('Still owed', _remainingV),
            if (_pendingV != null && _pendingV! > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ManaText.raw(
                  '$_pendingV instalments will be created. They begin only once '
                  'the migration is finished, not today.',
                  style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
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
