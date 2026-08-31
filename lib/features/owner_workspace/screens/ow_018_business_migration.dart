import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/use_my_location_button.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/location_api_service.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_amount.dart';
import '../../../shared/network_error_handler.dart';
import '../state/business_management_state.dart';
import '../state/customer_state.dart';
import '../../../design/components/mana_info_hint.dart';


/// Whether a mobile number entered on the pre-existing-business path may be
/// saved.
///
/// Blank is allowed HERE AND NOWHERE ELSE: `persons.mobile_number` is
/// nullable and `app.register_new_customer` NULLIFs an empty string, because
/// an old paper book routinely has no phone number for its older customers.
/// While the form demanded one, the only way to enter such a customer was to
/// invent a number, and an invented number collides with whoever really owns
/// it under `uq_persons_mobile_number`.
///
/// A PARTIAL number is still refused. Six digits is a typo, not a decision to
/// leave the field out, and letting it through would store a number that can
/// never be dialled.
bool migrationMobileAcceptable(String raw) {
  final trimmed = raw.trim();
  return trimmed.isEmpty || trimmed.length == 10;
}

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
  DateTime? _figuresAsOf;
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
      //
      // Stated AT THE CUT-OFF for a migrated book, never at today. Investor
      // interest keeps accruing after the cut-off, so today's payable is not
      // the number the Owner can check against a book that stops in March —
      // on sri satyanarayana it read Rs 38,70,308 against a book saying
      // Rs 24,85,582, and nothing on the screen said the dates differed.
      final snapshot = await api.fetchMigrationSnapshot(businessId: widget.businessId);
      final payable = await api.fetchInvestorPayableBalance(
          businessId: widget.businessId, asOf: snapshot?.cutoff);
      // Profit is the Owner's declared figure once a snapshot exists. What the
      // app derives is missing whatever the book knows and the tables do not
      // — the interest on loans that had already closed, most of all — and
      // that gap is already carried as profit_carry_forward.
      final profit = snapshot != null
          ? snapshot.declaredProfit
          : await api.fetchBusinessProfit(businessId: widget.businessId);
      if (!mounted) return;
      setState(() {
        _summary = s;
        _investorPayableBalance = payable;
        _businessProfit = profit;
        _figuresAsOf = snapshot?.cutoff;
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
          // Scrolls if it does not fit -- see ow_011_day_closure.dart.
          scrollable: true,
          title: ManaText.raw(ref.t('reopen_migration')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManaText.raw(
                ref.t('reopen_migration_note'),
                style: ManaType.note,
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
      appBar: ManaAppBar(title: ref.t('pre_existing_business')),
      // "Add a Customer" rather than "Add Existing Loan": the form takes the
      // person and their loan together, and the person is the part an Owner
      // is thinking about when they open this screen. Branch behaviour,
      // main's translation wiring.
      floatingActionButton: (s != null && !s.migrationLocked)
          ? FloatingActionButton.extended(
              onPressed: _addLoan,
              icon: const Icon(Icons.person_add_alt_1),
              label: ManaText.raw(ref.t('add_a_customer')),
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
                      // Room for the FAB to float over. Without it the
                      // extended button sat on top of Finish Migration, which
                      // is the last thing an Owner needs to reach on this
                      // screen and the one they cannot scroll past.
                      padding: EdgeInsets.fromLTRB(
                        ManaSpacing.lg,
                        ManaSpacing.lg,
                        ManaSpacing.lg,
                        (s != null && !s.migrationLocked)
                            ? ManaSpacing.lg + 88
                            : ManaSpacing.lg,
                      ),
                      children: [
                        _statusCard(s!),
                        const SizedBox(height: ManaSpacing.lg),
                        _bfCard(s),
                        const SizedBox(height: ManaSpacing.lg),
                        _profitCard(),
                        const SizedBox(height: ManaSpacing.lg),
                        if (!s.migrationLocked) ...[
                          // The spreadsheet is the fallback, not the front
                          // door. Most Owners here have never used Excel,
                          // and a sheet also fails all-or-nothing — one bad
                          // row in a thousand rejects the lot. Entering
                          // people one at a time is slower per customer and
                          // far more likely to finish, so the one-at-a-time
                          // path is the button on the screen (the FAB) and
                          // this is demoted to a plain link beneath it.
                          ManaText.raw(
                            'Adding customers one at a time is the reliable way — each '
                            'one is saved on its own, so a mistake in the tenth never '
                            'undoes the first nine. The spreadsheet below is only worth '
                            'it if you already keep your book in Excel.',
                            style: ManaType.fine,
                          ),
                          const SizedBox(height: ManaSpacing.sm),
                          TextButton.icon(
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
              style: ManaType.noteBad),
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
                      style: ManaType.cardTitle),
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
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.md),
            if (s.migrationLocked)
              OutlinedButton(onPressed: _reopen, child: ManaText.raw(ref.t('reopen_migration'))),
            if (!s.migrationLocked)
              ManaText.raw(
                  ref.t('pre_existing_loans_entered_note').replaceAll('{count}', '${s.migratedLoanCount}'),
                  style: ManaType.small),
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
        // Scrolls if it does not fit -- see ow_011_day_closure.dart.
        scrollable: true,
        title: ManaText.raw(ref.t('declare_opening_bf')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(
              ref.t('declare_opening_bf_note'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.md),
            // Whole rupees, and the keyboard says so. It offered a decimal
            // point before, and a decimal typed into it parsed to null through
            // int.tryParse below — the dialog closed having declared nothing,
            // with no error to explain why. Money columns are numeric(_,0);
            // paise cannot be stored.
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: InputDecoration(
                labelText: ref.t('cash_in_hand_field'),
                prefixText: '₹ ',
              ),
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
                      style: ManaType.strong),
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
                        style: ManaType.note),
                  ),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(child: ManaAmount(s.lineBalance, size: ManaAmountSize.compact)),
                ],
              ),
            ),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              ref.t('line_balance_note'),
              style: ManaType.note,
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
            ManaText.raw(ref.t('profit_and_investor_payable'), style: ManaType.strong),
            // Without the date these read as "now" and get compared against a
            // book that stopped months ago.
            if (_figuresAsOf != null)
              ManaText.raw(
                'As on ${_figuresAsOf!.day} '
                '${const [
                  'Jan','Feb','Mar','Apr','May','Jun',
                  'Jul','Aug','Sep','Oct','Nov','Dec'
                ][_figuresAsOf!.month - 1]} ${_figuresAsOf!.year}',
                style: ManaType.fine,
              ),
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

  // --- Register-the-person-here mode ------------------------------------
  //
  // WHY THIS EXISTS: migrating a book used to mean an Excel sheet, and most
  // Owners here have never used a spreadsheet. This is the same job as one
  // form: the person and the loan they already owe, entered together, saved
  // together, one customer at a time.
  //
  // It is NOT a second way to create a customer — it calls exactly the same
  // registration RPC that OW-004 does, so MLID generation, the Aadhaar
  // uniqueness check and the address rows are all identical. The only thing
  // added is that the loan is written straight afterwards, against the id
  // that call returns.
  //
  // Each person is saved on their own. That is the whole point compared to
  // the bulk sheet: with 1,000 rows in one transaction a single bad row
  // discards all of them, whereas here the tenth entry failing leaves the
  // first nine safely saved.
  bool _newPerson = false;
  final _fullName = TextEditingController();
  final _fatherHusband = TextEditingController();
  final _mobile = TextEditingController();
  final _aadhaar = TextEditingController();
  final _doorNo = TextEditingController();
  final _pinCode = TextEditingController();
  final _villageSearch = TextEditingController();
  String? _gender;
  String? _villageId;
  List<ManaVillage> _villageResults = [];
  bool _villageSearchAttempted = false;
  final _given = TextEditingController();
  final _interest = TextEditingController();
  final _fee = TextEditingController(text: '0');
  final _balance = TextEditingController();
  final _emi = TextEditingController();
  String _frequency = 'Weekly';
  // IST, not the handset clock — a migrated loan's effective_date is the
  // business day it is booked against. See lib/shared/mana_time.dart.
  DateTime _effectiveDate = manaNowIst().subtract(const Duration(days: 30));
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
    _fullName.dispose();
    _fatherHusband.dispose();
    _mobile.dispose();
    _aadhaar.dispose();
    _doorNo.dispose();
    _pinCode.dispose();
    _villageSearch.dispose();
    _given.dispose();
    _interest.dispose();
    _fee.dispose();
    _balance.dispose();
    _emi.dispose();
    for (final c in [
      _given, _interest, _fee, _balance, _emi,
      _fullName, _fatherHusband, _mobile, _aadhaar, _doorNo, _pinCode, _villageSearch,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Villages for the typed PIN.
  ///
  /// Through LocationApiService, which is the only place `locations` is
  /// supposed to be read. This site had drifted: it was the one village search
  /// in the app with no `status = 'Active'` filter, so it offered RETIRED
  /// villages as though they were current — and person_addresses.village_id is
  /// a FK, so choosing one writes a real address pointing at a dead row.
  Future<void> _searchVillages(String query) async {
    final pin = _pinCode.text.trim();
    if (pin.length != 6) {
      setState(() {
        _villageResults = [];
        _villageSearchAttempted = false;
      });
      return;
    }
    final villages = await ref
        .read(locationApiServiceProvider)
        .searchByPin(pinCode: pin, query: query, limit: 20);
    if (!mounted) return;
    setState(() {
      _villageResults = villages;
      _villageSearchAttempted = true;
    });
  }

  /// The person half of the form. Same fields, same order and the same
  /// registration RPC as OW-004's Add Customer sheet — this is not a second
  /// way to create a person, only a second place to do it from.
  List<Widget> _personFields() => [
        TextField(
          controller: _fullName,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full Name *'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _fatherHusband,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Father / Husband Name *'),
          onChanged: (_) => setState(() {}),
        ),
        DropdownButtonFormField<String>(
          // isExpanded: a DropdownButton sizes to its widest item and
          // overflows rather than shrinking -- measured at 1.0x on OW-002.
          isExpanded: true,
          initialValue: _gender,
          decoration: const InputDecoration(labelText: 'Gender *'),
          items: const [
            DropdownMenuItem(value: '1', child: ManaText('male')),
            DropdownMenuItem(value: '0', child: ManaText('female')),
            // '2' has been a legal gender_digit since the migration wizard
            // landed (persons_gender_digit_check allows 0/1/2). Offering only
            // two forced whoever entered the book to file a third person as
            // one of the other two, and the MLID carries that digit for life.
            DropdownMenuItem(value: '2', child: ManaText('other')),
          ],
          onChanged: (v) => setState(() => _gender = v),
        ),
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          // OPTIONAL on this path only. app.register_new_customer NULLIFs it
          // and persons.mobile_number is nullable, because a pre-existing
          // book routinely has no phone number for its older customers. The
          // form demanded one anyway, so the only way to enter such a
          // customer was to invent a number — which then collides with the
          // real owner of that number under uq_persons_mobile_number.
          decoration: const InputDecoration(
            labelText: 'Mobile Number (optional)',
            suffixIcon: ManaInfoHint(
                'Leave blank if the old book does not have one. Do not invent a number.'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _aadhaar,
          keyboardType: TextInputType.number,
          maxLength: 12,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          // Optional here and nowhere else, deliberately: this is the
          // Owner-only pre-existing-member path, the sole Aadhaar-exempt
          // route per ADDENDUM v4. Without an Aadhaar the person gets an
          // MLTI instead of an MLPI.
          decoration: const InputDecoration(
            labelText: 'Aadhaar Number (optional)',
            suffixIcon: ManaInfoHint('Leave blank if you do not have it — they will get an MLTI id.'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _doorNo,
          // Also optional, and for the same reason — the RPC's own comment
          // says a migrated customer's paper record rarely has a door number.
          decoration: const InputDecoration(labelText: 'Door / House No (optional)'),
          onChanged: (_) => setState(() {}),
        ),
        UseMyLocationButton(
          onCaptured: (place) {
            setState(() {
              if (place.pinCode != null) _pinCode.text = place.pinCode!;
              // Not the geocoder's name. At a doorstep it usually returns the
              // colony, which no PIN's directory holds, so the box filled
              // itself with a term that could never match. The PIN is kept and
              // the box cleared; the PIN's villages are offered instead.
              _villageSearch.clear();
              _villageId = null;
            });
            if (_pinCode.text.trim().length == 6) _searchVillages('');
          },
        ),
        TextField(
          controller: _pinCode,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'PIN Code *'),
          onChanged: (_) {
            setState(() => _villageId = null);
            _searchVillages(_villageSearch.text);
          },
        ),
        TextField(
          controller: _villageSearch,
          decoration: const InputDecoration(labelText: 'Search Village/Town *'),
          onChanged: (v) {
            setState(() => _villageId = null);
            _searchVillages(v);
          },
        ),
        if (_villageResults.isNotEmpty)
          ..._villageResults.map((v) => ListTile(
                dense: true,
                title: ManaText.raw(v.name),
                subtitle: ManaText.raw(v.placeLabel, style: ManaType.fine),
                trailing: _villageId == v.locationId
                    ? Icon(Icons.check, color: ManaColors.statusGood)
                    : null,
                onTap: () => setState(() {
                  _villageId = v.locationId;
                  _villageSearch.text = v.name;
                }),
              )),
        if (_villageSearchAttempted && _villageResults.isEmpty && _villageId == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ManaSpacing.sm),
            child: ManaText.raw(
              'No village found for this PIN code. Add it from Customer '
              'Management first, then come back.',
              style: TextStyle(fontSize: 12, color: ManaColors.statusBad),
            ),
          ),
      ];

  bool get _personComplete =>
      _fullName.text.trim().length >= 2 &&
      _fatherHusband.text.trim().length >= 2 &&
      _gender != null &&
      migrationMobileAcceptable(_mobile.text) &&
      _pinCode.text.trim().length == 6 &&
      _villageId != null;

  int? get _givenV => int.tryParse(_given.text.trim());
  int? get _interestV => int.tryParse(_interest.text.trim());
  int get _feeV => int.tryParse(_fee.text.trim()) ?? 0;

  int? get _emiV => int.tryParse(_emi.text.trim());

  /// The whole obligation, DERIVED: the cash actually handed over plus the
  /// interest and fee that were withheld from it. Entering 19,600 given with
  /// 4,000 interest and 400 fee makes this 24,000, which is what the customer
  /// repays -- the 4,400 never left the till and so never returns to it as
  /// fresh cash. It reaches the business through the instalments instead.
  int? get _issuedV => (_givenV != null && _interestV != null)
      ? _givenV! + _interestV! + _feeV
      : null;

  /// Remaining balance is TYPED, in rupees, exactly as the old book states it.
  ///
  /// It used to be derived as `pending instalments x EMI`, which is wrong for
  /// a real book: 14% of loans in the Owner's own ledger have a PART-PAID
  /// instalment, and that formula cannot express one. A customer who owes
  /// 6,250 against a 500 instalment came out as either 6,000 or 6,500, and the
  /// difference was silently written into the loan.
  ///
  /// Derived-vs-typed is settled the same way the spreadsheet import settles
  /// it (app.import_migrated_loans): typed wins for a cut-off loan, and where
  /// an instalment history exists the replay derives it instead. This screen
  /// enters one loan at a time with no history behind it, so it is the typed
  /// case.
  int? get _remainingV => int.tryParse(_balance.text.trim());

  /// How many instalments the schedule will hold, CEILING — the same rule
  /// app.migrate_loan applies server-side, shown here so the number on screen
  /// is the number that gets written. A 6,250 balance against a 500 instalment
  /// is 13 rows, the last one short, not 12.
  int? get _instalmentsToCreate => (_remainingV != null && _emiV != null && _emiV! > 0)
      ? (_remainingV! / _emiV!).ceil()
      : null;

  /// What the customer has already handed over: the whole obligation minus
  /// what is still owed today.
  int? get _collected =>
      (_issuedV != null && _remainingV != null) ? _issuedV! - _remainingV! : null;

  String? get _validationError {
    if (_newPerson) {
      if (!_personComplete) return null; // incomplete, not wrong
    } else if (_customer == null) {
      return 'Choose the customer this loan belongs to.';
    }
    if (_givenV == null || _interestV == null || _remainingV == null || _emiV == null) {
      return null; // incomplete, not wrong
    }
    if (_givenV! <= 0 || _emiV! <= 0) {
      return 'Amounts must be greater than zero.';
    }
    if (_interestV! < 0 || _feeV < 0) {
      return 'Interest and fee cannot be negative.';
    }
    if (_remainingV! < 0) {
      return 'The remaining balance cannot be negative.';
    }
    if (_remainingV! > _issuedV!) {
      return 'The balance still owed, ${manaRupees(_remainingV!)}, is more '
          'than the ${manaRupees(_issuedV!)} this loan was issued for.';
    }
    return null;
  }

  bool get _canSave =>
      (_newPerson ? _personComplete : _customer != null) &&
      _givenV != null &&
      _interestV != null &&
      _remainingV != null &&
      _emiV != null &&
      _validationError == null &&
      !_saving;

  /// Registers the person if this is a new one, then records their loan.
  ///
  /// Two calls, in order, NOT one transaction — deliberately. If the loan
  /// write fails the customer still exists, which is recoverable: the Owner
  /// picks them from the dropdown and enters the loan again. The reverse
  /// (rolling the person back) would throw away a successful registration
  /// because of a typo in an amount. So the failure message below says
  /// exactly that, rather than a bare error.
  ///
  /// [andAnother] keeps the form open with the loan fields cleared, because
  /// migrating a book is fifty of these in a row, not one.
  /// Everything this is about to write, on one screen, before it is written.
  ///
  /// Migrating a book is fifty of these in a row, and the figures that matter
  /// are DERIVED — the total issued, what counts as already collected, how
  /// many instalment rows appear. Those were only visible as small computed
  /// lines mixed in among the inputs, which is exactly where a mistyped digit
  /// hides. Nothing is saved until this is confirmed.
  Future<void> _pickEffectiveDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      // Backdating is the whole point here, unlike OW-005.
      firstDate: DateTime(2000),
      // "Today" is the IST business day, same clock as the default.
      lastDate: manaNowIst(),
    );
    if (picked != null && mounted) setState(() => _effectiveDate = picked);
  }

  Future<bool> _confirmPreview() async {
    final person = _newPerson ? _fullName.text.trim() : (_customer?.fullName ?? '');
    final village = _newPerson ? _villageSearch.text.trim() : null;

    // Landscape, or a large text size, leaves the dialog short enough that
    // only the first two rows show. It scrolled, but nothing said so — the
    // point of a confirmation is that the whole of it gets read, so the
    // thumb is pinned visible whenever there is more below the fold.
    final scrollController = ScrollController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ManaText.raw('Check This Loan'),
        content: Scrollbar(
          controller: scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(person, style: ManaType.heavy),
              if (village != null && village.isNotEmpty)
                ManaText.raw(village,
                    style: ManaType.fine),
              if (_newPerson)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ManaText.raw('A new person will be registered.',
                      style: TextStyle(fontSize: 12, color: ManaColors.statusWarn)),
                ),
              const Divider(),
              _previewRow('Cash given', _givenV),
              _previewRow('Interest', _interestV),
              _previewRow('Processing fee', _feeV),
              _previewRow('Total to repay', _issuedV, bold: true),
              const Divider(),
              _previewRow('Already collected', _collected),
              _previewRow('Still owed', _remainingV, bold: true),
              const Divider(),
              ManaText.raw(
                '$_frequency · ${manaRupees(_emiV ?? 0)} each · '
                '${_instalmentsToCreate ?? 0} instalments',
                style: ManaType.small,
              ),
              ManaText.raw(
                'Issued ${_effectiveDate.toIso8601String().split("T").first}',
                style: ManaType.fine,
              ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const ManaText.raw('Go Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const ManaText.raw('Save This Loan'),
          ),
        ],
      ),
    );
    scrollController.dispose();
    return confirmed == true;
  }

  Widget _previewRow(String label, int? value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: ManaText.raw(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: ManaColors.textSecondary,
                      fontWeight: bold ? FontWeight.w600 : null)),
            ),
            ManaText.raw(
              value == null ? '—' : manaRupees(value),
              style: TextStyle(
                  fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w600),
            ),
          ],
        ),
      );

  Future<void> _save({bool andAnother = false}) async {
    if (!await _confirmPreview()) return;
    if (!mounted) return;
    setState(() => _saving = true);

    String? customerId = _customer?.customerId;
    if (_newPerson) {
      final created = await NetworkErrorHandler.run(context, () async {
        return ref.read(customerListProvider.notifier).createNewReturningId(
              businessId: widget.businessId,
              fullName: _fullName.text.trim(),
              fatherHusbandName: _fatherHusband.text.trim(),
              genderDigit: _gender!,
              mobileNumber: _mobile.text.trim(),
              aadhaarNumber: _aadhaar.text.trim().isEmpty ? null : _aadhaar.text.trim(),
              doorNo: _doorNo.text.trim(),
              pinCode: _pinCode.text.trim(),
              villageId: _villageId!,
            );
      });
      if (!mounted) return;
      if (created == null) {
        setState(() => _saving = false);
        return; // registration failed — message already shown, nothing written
      }
      customerId = created;
    }

    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(businessManagementApiServiceProvider).migrateLoan(
            businessId: widget.businessId,
            customerId: customerId!,
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

    if (ok != true) {
      if (_newPerson) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: ManaText.raw(
              'The person was saved but the loan was not. Choose them from the '
              'customer list and enter the loan again — do not register them twice.',
            ),
          ),
        );
      }
      return;
    }

    if (!andAnother) {
      Navigator.of(context).pop(true);
      return;
    }

    // Same Owner, same sitting, next customer. The frequency and the
    // original start date usually repeat across a book, so they stay.
    setState(() {
      _customer = null;
      _newPerson = false;
      _gender = null;
      _villageId = null;
      _villageResults = [];
      _villageSearchAttempted = false;
      for (final c in [_fullName, _fatherHusband, _mobile, _aadhaar, _doorNo, _pinCode, _villageSearch, _given, _interest, _balance, _emi]) {
        c.clear();
      }
      _fee.text = '0';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: ManaText.raw('Saved. Enter the next one.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customerListProvider).customers;
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('add_a_customer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            ManaText.raw(
              ref.t('add_existing_loan_note'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.lg),
            // Branch behaviour (pick an existing customer OR enter a new
            // person inline), main's translation wiring.
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: ManaText.raw(ref.t('existing_customer'))),
                ButtonSegment(value: true, label: ManaText.raw(ref.t('new_person'))),
              ],
              selected: {_newPerson},
              onSelectionChanged: (s) => setState(() {
                _newPerson = s.first;
                _customer = null;
              }),
            ),
            const SizedBox(height: ManaSpacing.md),
            if (!_newPerson)
              DropdownButtonFormField<CustomerSummary>(
                initialValue: _customer,
                isExpanded: true,
                decoration: InputDecoration(labelText: ref.t('customer_required_field')),
                items: customers
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: ManaText.raw('${c.fullName} · ${c.mlid}',
                              style: ManaType.small),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _customer = v),
              )
            else
              ..._personFields(),
            const SizedBox(height: ManaSpacing.md),
            _amountField(_given, ref.t('amount_given_cash_field')),
            _amountField(_interest, ref.t('interest_required_field')),
            _amountField(_fee, ref.t('processing_fee_field')),
            _computedRow(ref.t('total_issued'), _issuedV, ref.t('total_issued_hint')),
            const SizedBox(height: ManaSpacing.md),
            DropdownButtonFormField<String>(
              // isExpanded: a DropdownButton sizes to its widest item and
              // overflows rather than shrinking -- measured at 1.0x on OW-002.
              isExpanded: true,
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
            _amountField(_emi, ref.t('instalment_amount_emi_field')),
            // Rupees, as the book states it. See _remainingV for why this is
            // typed and not counted out of instalments.
            _amountField(_balance, 'Balance Still Owed *'),
            _computedRow(ref.t('already_paid'), _collected, ref.t('already_paid_hint')),
            const SizedBox(height: ManaSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: ManaText.raw(ref.t('original_start_date')),
              subtitle: ManaText.raw(DateFormat('d MMM yyyy').format(_effectiveDate)),
              // An 18px Icon in the trailing slot is not a touch target: on a
              // handset, tapping the one part of the row that looks like a
              // button did nothing, while the text beside it opened the
              // picker. An IconButton gets the 48px minimum and its own
              // handler, so both halves of the row now do the same thing.
              trailing: IconButton(
                icon: const Icon(Icons.calendar_today, size: 18),
                tooltip: 'Change the date',
                onPressed: _pickEffectiveDate,
              ),
              onTap: _pickEffectiveDate,
            ),
            const Divider(height: ManaSpacing.xxl),
            _derivedCard(),
            if (_validationError != null && _customer != null) ...[
              const SizedBox(height: ManaSpacing.md),
              ManaText.raw(_validationError!,
                  style: ManaType.noteBad),
            ],
            const SizedBox(height: ManaSpacing.lg),
            // Migrating a book is fifty of these in a row. Save and Add
            // Another keeps the Owner in the form instead of making them
            // walk back in from the migration screen each time.
            OutlinedButton.icon(
              onPressed: _canSave ? () => _save(andAnother: true) : null,
              icon: const Icon(Icons.playlist_add),
              label: const ManaText('save and add another'),
            ),
            const SizedBox(height: ManaSpacing.sm),
            FilledButton(
              onPressed: _canSave ? () => _save() : null,
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
            suffixIcon: ManaInfoHint(hint),
            helperMaxLines: 2,
            filled: true,
            fillColor: ManaColors.surfaceSunken,
          ),
          child: ManaText.raw(
            value == null ? '—' : manaRupees(value),
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
                style: ManaType.strong),
            const SizedBox(height: ManaSpacing.sm),
            _derived(ref.t('already_collected'), _collected),
            _derived(ref.t('still_owed'), _remainingV),
            if (_instalmentsToCreate != null && _instalmentsToCreate! > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ManaText.raw(
                  ref
                      .t('instalments_created_note')
                      .replaceAll('{count}', '$_instalmentsToCreate'),
                  style: ManaType.note,
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
            Expanded(child: ManaText.raw(label, style: ManaType.small)),
            ManaText.raw(
              value == null
                  ? '—'
                  : '${signed && value > 0 ? '+' : ''}${manaRupees(value)}',
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
