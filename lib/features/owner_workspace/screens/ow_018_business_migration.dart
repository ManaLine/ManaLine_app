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

  Widget _bfCard(MigrationSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          children: [
            _row('Investment principal', s.investmentPrincipal),
            _row('Given out on old loans', -s.totalGiven),
            _row('Already collected back', s.totalCollected),
            const Divider(),
            Row(
              children: [
                const Expanded(
                  child: ManaText('BF — cash in hand',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ManaAmount(s.bf, semanticLabel: 'Brought forward, cash in hand'),
              ],
            ),
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

  Widget _row(String label, double amount) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: ManaText.raw(label, style: const TextStyle(fontSize: 13))),
            ManaText.raw(_currency.format(amount),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );
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
  final _repay = TextEditingController();
  final _remaining = TextEditingController();
  final _installment = TextEditingController();
  final _fee = TextEditingController(text: '0');
  final _grace = TextEditingController(text: '0');
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
    for (final c in [_given, _repay, _remaining, _installment, _fee, _grace]) {
      c.dispose();
    }
    super.dispose();
  }

  double? get _givenV => double.tryParse(_given.text.trim());
  double? get _repayV => double.tryParse(_repay.text.trim());
  double? get _remainingV => double.tryParse(_remaining.text.trim());
  double? get _instV => double.tryParse(_installment.text.trim());
  double get _feeV => double.tryParse(_fee.text.trim()) ?? 0;

  /// Same arithmetic the server does, shown live so the Owner can see the
  /// consequence before saving rather than after.
  double? get _collected =>
      (_repayV != null && _remainingV != null) ? _repayV! - _remainingV! : null;
  double? get _interest =>
      (_repayV != null && _givenV != null) ? _repayV! - _givenV! - _feeV : null;
  double? get _bfEffect =>
      (_givenV != null && _collected != null) ? _collected! - _givenV! : null;

  String? get _validationError {
    if (_customer == null) return 'Choose the customer this loan belongs to.';
    if (_givenV == null || _repayV == null || _remainingV == null || _instV == null) {
      return null; // incomplete, not wrong
    }
    if (_givenV! <= 0 || _repayV! <= 0 || _instV! <= 0) {
      return 'Amounts must be greater than zero.';
    }
    if (_remainingV! < 0 || _remainingV! > _repayV!) {
      return 'Remaining balance must be between 0 and the repayment amount.';
    }
    if (_givenV! + _feeV > _repayV!) {
      return 'Amount given plus fee cannot exceed the repayment amount — that would make interest negative.';
    }
    return null;
  }

  bool get _canSave =>
      _customer != null &&
      _givenV != null &&
      _repayV != null &&
      _remainingV != null &&
      _instV != null &&
      _validationError == null &&
      !_saving;

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(businessManagementApiServiceProvider).migrateLoan(
            businessId: widget.businessId,
            customerId: _customer!.customerId,
            amountGiven: _givenV!,
            repaymentAmount: _repayV!,
            remainingBalance: _remainingV!,
            effectiveDate: _effectiveDate,
            repaymentType: _frequency,
            installmentAmount: _instV!,
            gracePeriodDays: int.tryParse(_grace.text.trim()) ?? 0,
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
            _amountField(_repay, 'Repayment Amount * — total repayable'),
            _amountField(_remaining, 'Remaining Balance * — still owed today'),
            _amountField(_installment, 'Instalment Amount *'),
            _amountField(_fee, 'Processing Fee'),
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
            TextField(
              controller: _grace,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Grace Period (days)'),
            ),
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
            _derived('Interest on this loan', _interest),
            _derived('Effect on BF', _bfEffect, signed: true),
            if (_remainingV != null && _instV != null && _instV! > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ManaText.raw(
                  '${(_remainingV! / _instV!).ceil()} instalments will be created, '
                  'starting today.',
                  style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _derived(String label, double? value, {bool signed = false}) => Padding(
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
