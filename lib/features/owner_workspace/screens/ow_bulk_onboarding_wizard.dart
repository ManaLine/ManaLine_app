import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/components/mana_card.dart';
import '../../../shared/idempotency.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/bulk_onboarding_service.dart';
import 'ow_investor_entry_sheets.dart';
import 'ow_member_picker.dart';

/// P3 Pre-Existing Business Wizard — seven pages that move a paper book onto
/// MANA LINE in the order the book itself is organised.
///
/// Not a locked spec screen ID — reached from OW-018 (Business Migration) the
/// same way `/import` is reached from Settings, so it has no OW-0xx of its own.
///
///   1 Identities        every person in the book, one file
///   2 Areas & Villages  the (PIN, Village) pairs that file names, confirmed
///                       against the LGD reference, then the areas that hold
///                       them — and only then are the identities written
///   3 Investors         including the Owner: owner capital is equity
///   4 Customers         one grid per repayment frequency, EMI history inline
///   5 Agents            attendance only; salary lives in the weekly sheet
///   6 Opening Snapshot  the cut-off declaration
///   7 Weekly Account    the weekly book, reconciled against what was imported
///
/// Page 2 is where identities are written, not page 1. A customer's address
/// has to point at a real village row, and the villages do not exist until the
/// Owner has confirmed them — the LGD reference suggests, it never validates,
/// because 8.1% of PIN codes list two districts after the post-2022 splits.
///
/// Every write goes through the same server RPCs the rest of the app uses; see
/// bulk_onboarding_service.dart for which ones and why.
class BulkOnboardingWizardScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BulkOnboardingWizardScreen({super.key, required this.businessId});

  @override
  ConsumerState<BulkOnboardingWizardScreen> createState() => _BulkOnboardingWizardScreenState();
}

/// Every flagged row gets [decision] — 'skip' merges each into the person
/// already on file, 'keep' imports each as a separate person.
///
/// Deliberately REPLACES decisions already made rather than only filling the
/// undecided ones. A "Merge All" that quietly left three earlier Ignores
/// standing would not be all, and the Owner would only discover the
/// disagreement as duplicate people after the import had run.
Map<int, String> manaDecideAllDuplicates(
  List<DuplicateMatch> duplicates,
  String decision,
) =>
    {for (final d in duplicates) d.row: decision};

/// The pages the wizard can show, in order.
///
/// Which of them an Owner actually sees depends on what they said their book
/// contains — see [_WizardPage] and the chooser. Two are always shown: the
/// plan itself, and the identities, because a book with nobody in it is not a
/// book.
///
/// Areas & Villages used to sit second. It derived the village list from the
/// identity sheet and then asked the Owner to place each one — AFTER the
/// identities that needed those villages had already been imported.
/// bulk_import_identities said as much, refusing a customer with "add it on
/// the Areas & Villages step first" about a step that came later. Villages and
/// areas are now set up before the wizard is opened, the identity sheet offers
/// them as a dropdown, and a village typed in fresh is created by the import.
enum _WizardPage {
  plan('What Your Book Has'),
  identities('Identities'),
  investors('Investors'),
  customers('Customers'),
  agents('Agents'),
  snapshot('Opening Snapshot'),
  weekly('Weekly Account'),
  finish('Finish');

  const _WizardPage(this.title);
  final String title;
}

/// The pages this book needs, given what the Owner said it has.
///
/// Shareholders share the Investors page, so that page shows if either was
/// ticked. Instalment history is part of the Customers sheet rather than a
/// page of its own; it changes what that page says, not whether it appears.
List<_WizardPage> _pagesFor(MigrationPlan? plan) {
  if (plan == null) return const [_WizardPage.plan];
  return [
    _WizardPage.plan,
    _WizardPage.identities,
    if (plan.investors || plan.shareholders) _WizardPage.investors,
    if (plan.customers) _WizardPage.customers,
    if (plan.attendance) _WizardPage.agents,
    _WizardPage.snapshot,
    if (plan.weekly) _WizardPage.weekly,
    _WizardPage.finish,
  ];
}

class _BulkOnboardingWizardScreenState extends ConsumerState<BulkOnboardingWizardScreen> {
  int _step = 0;

  /// What the Owner said their book contains. Null until they have said, which
  /// is why the chooser is the only page shown until then.
  MigrationPlan? _plan;
  bool _planSaving = false;
  List<String> _planGaps = const [];
  bool _gapsAsked = false;

  /// The page this sitting resumed at, or null if it started at the beginning.
  /// Only used to say so on screen — landing on page 5 with no explanation
  /// reads as lost work.
  int? _resumedAt;

  // Where the wizard had got to, per business.
  //
  // Eight pages, several of them a file upload, is more than one sitting: the
  // Owner puts the phone down, comes back, and the wizard used to drop them on
  // page 1 with every page they had already finished looking untouched. That
  // is also how a book gets imported twice.
  //
  // NOT derived from what is already in the database, which was the first
  // instinct: this business had four operating areas before the wizard was
  // ever run, so "areas exist" would have marked page 2 done when it was not.
  // A pointer the wizard writes itself cannot lie about its own progress.
  //
  // THE SERVER HOLDS IT (businesses.migration_wizard_step) so it follows the
  // Owner to another handset or through a reinstall. The secure-storage copy
  // is kept as an OFFLINE FALLBACK ONLY: this app is used where the signal
  // drops, and on a failed read the last place this device saw beats page 1.
  // The server wins whenever it answers — it is the one both devices share.
  static const _storage = FlutterSecureStorage();
  String get _stepKey => 'mana_bulk_onboarding_step_${widget.businessId}';

  @override
  void initState() {
    super.initState();
    // After the first frame, not awaited: page 1 is a correct thing to show
    // while the pointer is fetched, and blocking the first paint on a network
    // round trip is exactly the hang this app cannot afford.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The plan first: it decides which pages exist, so a step restored
      // before it would be an index into a list that has not been built.
      await _loadPlan();
      await _restoreStep();
      _refreshProgress();
    });
  }

  /// Resuming can land straight on page 3 without a page turn, so the
  /// investor list is fetched there too.
  void _loadForStep(int step) {
    if (_pages[step.clamp(0, _pages.length - 1)] == _WizardPage.investors) {
      unawaited(_loadInvestorCandidates());
    }
  }

  Future<void> _loadPlan() async {
    try {
      final plan = await _svc.migrationPlan(widget.businessId);
      if (!mounted || plan == null) return;
      setState(() {
        _plan = plan;
        // The cut-off is the anchor for every page that states a figure "as
        // at" a date, so the snapshot page opens on it already chosen.
        _cutoffDate ??= plan.cutoff;
      });
    } catch (_) {
      // Left null: the chooser is then the only page, which is where an Owner
      // who has not said what their book contains ought to be anyway.
    }
  }

  Future<void> _restoreStep() async {
    int? saved;
    try {
      saved = await _svc.wizardStep(widget.businessId);
    } catch (_) {
      // Offline, or the call failed. Fall through to what this device
      // remembers rather than silently restarting a half-finished migration.
      saved = null;
    }
    saved ??= await _localStep();

    if (!mounted || saved == null || saved <= 0) return;
    // Clamp: a pointer written by a build with more pages must not index past
    // the end of _pageTitles.
    final target = saved.clamp(0, _pages.length - 1);
    if (target == 0) return;
    setState(() {
      _step = target;
      _resumedAt = target;
    });
    _loadForStep(target);
  }

  /// Re-counts what is in the business. Called on open and after every write,
  /// never awaited by anything the Owner is waiting on. A failure leaves the
  /// last known counts up rather than blanking them: stale-but-labelled beats
  /// a page that suddenly claims nothing is there.
  Future<void> _refreshProgress() async {
    try {
      final p = await _svc.migrationProgress(widget.businessId);
      if (mounted) setState(() => _progress = p);
    } catch (_) {
      // Offline or denied. The line simply does not appear.
    }
  }

  Future<int?> _localStep() async {
    try {
      return int.tryParse(await _storage.read(key: _stepKey) ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Move to [step] and remember it, on the server and on this device. Every
  /// page change goes through here so there is no route back to page 1 that
  /// forgets to write the pointer.
  /// The next page in THIS book's list.
  ///
  /// Every page used to name the index it jumped to, which was already how
  /// Next came to skip a page when Areas & Villages was removed. With the list
  /// depending on what the Owner ticked, a hardcoded number cannot be right at
  /// all.
  void _goNext() => _goTo((_step + 1).clamp(0, _pages.length - 1));

  void _goTo(int step) {
    // Counted fresh on every page turn — including Back, which is the whole
    // reason this exists.
    unawaited(_refreshProgress());
    // Fetched on arrival, not from build(): a load kicked off during build
    // that fails ends up calling showSnackBar mid-frame, which Flutter
    // asserts on. An Owner who never reaches page 3 still never pays for it.
    if (step == 2) unawaited(_loadInvestorCandidates());
    setState(() {
      _step = step;
      _resumedAt = null; // they have navigated; the banner has done its job
    });
    // Neither write is awaited and neither blocks the page turn: a pointer
    // that failed to save costs the Owner one page of re-navigation later,
    // which is not worth making them wait on the network for.
    //
    // try/catch as well as catchError, because these can throw SYNCHRONOUSLY —
    // reading the service provider builds it, and that touches
    // Supabase.instance. A throw there took the page turn down with it, which
    // is the opposite of "saving the pointer never blocks navigation".
    try {
      _storage.write(key: _stepKey, value: '$step').catchError((_) {});
    } catch (_) {/* the server copy is the one that matters */}
    try {
      _svc.saveWizardStep(widget.businessId, step).catchError((_) {});
    } catch (_) {/* they keep the page they are on either way */}
  }

  /// Deliberate restart, from the resumed banner.
  void _startFromTheBeginning() {
    _goTo(0);
    setState(() => _resumedAt = null);
  }

  // 1 — identities
  bool _busy1 = false;
  ParsedSheet? _identityParse;
  String? _identityFileName;
  String? _identityFormatError;
  List<DuplicateMatch> _duplicates = const [];
  final Map<int, String> _dedupeDecisions = {};
  ImportOutcome? _identityOutcome;

  // 2 — areas & villages

  // 3 — investors
  bool _busy3 = false;
  ImportOutcome? _investorOutcome;

  /// Investors and shareholders are picked from the people page 1 already
  /// recorded, not retyped into a spreadsheet. There are a handful of them and
  /// every retyped MLID was a chance to attach money to the wrong person.
  List<ManaMemberRef>? _investorCandidates;
  final List<Map<String, dynamic>> _investorEntries = [];
  final List<Map<String, dynamic>> _shareholderEntries = [];
  List<Map<String, dynamic>>? _withdrawals;
  String? _withdrawalFileName;
  String? _withdrawalError;
  ImportOutcome? _withdrawalOutcome;
  final String _withdrawalKey = manaIdempotencyKey();

  // 4 — customers
  bool _busy4 = false;

  /// What is already in the business, per page. Null until the first read
  /// lands, and left null if it fails — a page with no line is honest; a page
  /// claiming zero when the read failed is not.
  MigrationProgress? _progress;

  /// Held across retries of step 4's loan import so the server can tell a
  /// retry from a second import. Null means "no import in flight".
  String? _loanImportKey;
  CustomerGridParse? _customerParse;
  String? _customerFileName;
  String? _customerFormatError;
  ImportOutcome? _customerOutcome;
  EmiSubmitResult? _emiResult;
  String _emiProgressLabel = '';

  // 5 — agents
  bool _busy5 = false;
  List<Map<String, dynamic>>? _attendance;
  String? _attendanceFileName;
  String? _attendanceError;
  AttendanceResult? _attendanceRecorded;

  // 6 — opening snapshot
  bool _busy6 = false;
  DateTime? _cutoffDate;
  final _openingBf = TextEditingController();
  final _declaredLineBalance = TextEditingController();
  final _declaredProfit = TextEditingController();
  Map<String, dynamic>? _snapshot;

  // 7 — weekly account
  bool _busy7 = false;
  List<Map<String, dynamic>>? _weeklyRows;
  String? _weeklyFileName;
  String? _weeklyError;
  Map<String, dynamic>? _weeklyResult;
  Map<String, dynamic>? _profitSummary;

  // 3b — shareholders, on the Investors page
  Map<String, dynamic>? _shareholderResult;
  // Distinct from the Opening Snapshot's declared profit: this is the profit
  // being shared out, which the Owner may declare lower than the computed one.
  final _declaredShareProfit = TextEditingController();

  List<_WizardPage> get _pages => _pagesFor(_plan);
  _WizardPage get _page => _pages[_step.clamp(0, _pages.length - 1)];

  String get _language => ref.read(authFlowProvider).language.enumValue;
  BulkOnboardingService get _svc => ref.read(bulkOnboardingServiceProvider);

  @override
  void dispose() {
    _openingBf.dispose();
    _declaredLineBalance.dispose();
    _declaredProfit.dispose();
    _declaredShareProfit.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // 1 — Identities
  // -------------------------------------------------------------------

  Future<void> _identityTemplate() async {
    setState(() => _busy1 = true);
    try {
      // The Owner's own villages, so the Village column offers them rather
      // than leaving every row to be typed from memory. Empty is fine: the
      // column is then plain text and the import creates whatever is written.
      final villages = await _svc
          .operatingVillages(widget.businessId)
          .catchError((_) => <String>[]);
      final bytes = BulkOnboardingService.buildIdentityTemplate(
          language: _language, villages: villages);
      await _svc.shareBytes(bytes, 'ManaLine-Identity-Import-Template.xlsx');
    } catch (e) {
      _toast('Could not build the template: $e');
    } finally {
      if (mounted) setState(() => _busy1 = false);
    }
  }

  Future<void> _identityPick() async {
    final file = await _pickSpreadsheet(allowCsv: true);
    if (file == null) return;

    if (!mounted) return;
    setState(() {
      _busy1 = true;
      _identityFormatError = null;
      _identityParse = null;
      _duplicates = const [];
      _dedupeDecisions.clear();
      _identityOutcome = null;
      _identityFileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      final parse = BulkOnboardingService.parseIdentityBytes(bytes, file.name);
      final duplicates = await _svc.findDuplicates(businessId: widget.businessId, rows: parse.rows);
      if (!mounted) return;
      setState(() {
        _identityParse = parse;
        _duplicates = duplicates;
      });
    } on ImportFormatException catch (e) {
      if (mounted) setState(() => _identityFormatError = e.message);
    } catch (e) {
      if (mounted) setState(() => _identityFormatError = 'Could not read this file: $e');
    } finally {
      if (mounted) setState(() => _busy1 = false);
    }
  }

  Future<void> _identityDownloadCorrection() async {
    final parse = _identityParse;
    final outcome = _identityOutcome;
    if (parse == null || outcome == null) return;
    try {
      final bytes = BulkOnboardingService.buildIdentityCorrectionFile(
          rows: parse.rows, errors: outcome.errors, language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-Identity-Import-Corrections.xlsx');
    } catch (e) {
      _toast('Could not build the corrected file: $e');
    }
  }

  /// Leaving the identities page with people parsed but not imported is almost always a
  /// mistake, so it has to be said out loud and chosen deliberately.
  Future<void> _confirmLeavingUnimported() async {
    final parse = _identityParse;
    final alreadyImported = _identityOutcome != null && !_identityOutcome!.rejected;

    if (parse == null || parse.rows.isEmpty || alreadyImported) {
      _goNext();
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ManaText.raw('Import These People First?'),
        content: ManaText.raw(
          '${parse.rows.length} people are ready but have not been saved yet. '
          'Nothing on the next pages can refer to them until they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('skip'),
            child: const ManaText.raw('Skip For Now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('import'),
            child: const ManaText.raw('Import Now'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'skip') {
      _goNext();
      return;
    }
    await _saveIdentities();
    // Only move on if it actually landed; a rejection keeps them on the page
    // with the row-by-row errors in view.
    if (mounted && _identityOutcome != null && !_identityOutcome!.rejected) {
      _goNext();
    }
  }

  /// Writes the people. Villages they name are created by the import itself
  /// now that Areas & Villages is gone — see the note on _WizardPage.
  Future<void> _saveIdentities() async {
    final parse = _identityParse;
    if (parse == null) {
      _toast('Choose the identity file first.');
      return;
    }
    final undecided = _duplicates.where((d) => !_dedupeDecisions.containsKey(d.row)).toList();
    if (undecided.isNotEmpty) {
      _toast('Review every flagged row (Merge or Ignore) before importing.');
      return;
    }

    setState(() => _busy1 = true);
    final outcome = await NetworkErrorHandler.run(
      context,
      timeout: kManaBulkTimeout,
      () => _svc.submitIdentities(
        businessId: widget.businessId,
        rows: parse.rows,
        dedupeDecisions: _dedupeDecisions,
      ),
    );

    if (!mounted) return;
    setState(() {
      _busy1 = false;
      _identityOutcome = outcome;
      // Drop the parsed rows once they are in. Pressing the button twice would
      // otherwise import every person a second time: the duplicate review ran
      // at parse time, against a database that did not yet contain them.
      if (outcome != null && !outcome.rejected) _identityParse = null;
    });
  }

  // -------------------------------------------------------------------
  // 3 — Investors
  // -------------------------------------------------------------------

  Future<void> _withdrawalTemplate() async {
    setState(() => _busy3 = true);
    try {
      final bytes = await _svc.buildWithdrawalTemplate(
          businessId: widget.businessId, language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-Withdrawals-Template.xlsx');
    } catch (e) {
      _toast('Could not build the template: $e');
    } finally {
      if (mounted) setState(() => _busy3 = false);
    }
  }

  Future<void> _withdrawalPick() async {
    final file = await _pickSpreadsheet();
    if (file == null) return;
    if (!mounted) return;
    setState(() {
      _busy3 = true;
      _withdrawalError = null;
      _withdrawals = null;
      _withdrawalOutcome = null;
      _withdrawalFileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      final rows = BulkOnboardingService.parseWithdrawalBytes(bytes, file.name);
      if (!mounted) return;
      setState(() => _withdrawals = rows);
    } on ImportFormatException catch (e) {
      if (mounted) setState(() => _withdrawalError = e.message);
    } catch (e) {
      if (mounted) setState(() => _withdrawalError = 'Could not read this file: $e');
    } finally {
      if (mounted) setState(() => _busy3 = false);
    }
  }

  Future<void> _withdrawalSubmit() async {
    final rows = _withdrawals;
    if (rows == null || rows.isEmpty) return;
    setState(() => _busy3 = true);
    final outcome = await NetworkErrorHandler.run(
      context,
      () => _svc.submitWithdrawals(
          businessId: widget.businessId,
          rows: rows,
          idempotencyKey: _withdrawalKey),
      timeout: kManaBulkTimeout,
    );
    if (!mounted) return;
    setState(() {
      _busy3 = false;
      _withdrawalOutcome = outcome;
      if (outcome != null && !outcome.rejected) _withdrawals = null;
    });
  }

  /// Everyone recorded as an Investor on page 1. Loaded once, when the
  /// Owner first reaches this page.
  Future<void> _loadInvestorCandidates() async {
    if (_investorCandidates != null) return;
    // Deliberately does NOT set _busy3. That flag disables this page's
    // buttons, and it is for a WRITE the Owner is waiting on — locking Next
    // behind a background list fetch stopped them leaving the page at all.
    try {
      final people = await _svc.membersInRole(
          businessId: widget.businessId, role: 'Investor');
      if (mounted) setState(() => _investorCandidates = people);
    } catch (_) {
      // Left empty on purpose: the picker then shows its own "nobody here
      // yet" note, which says more than a snackbar that has already gone.
      if (mounted) setState(() => _investorCandidates = const []);
    }
  }

  Future<void> _addInvestment(ManaMemberRef who) async {
    final entry = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => InvestmentSheet(who: who, cutoff: _cutoffDate),
    );
    if (entry != null && mounted) {
      setState(() => _investorEntries.add(entry));
    }
  }

  Future<void> _addShareholder(ManaMemberRef who) async {
    final entry = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ShareholderSheet(who: who),
    );
    if (entry != null && mounted) {
      setState(() => _shareholderEntries.add(entry));
    }
  }

  Future<void> _saveInvestments() async {
    if (_investorEntries.isEmpty) return;
    setState(() => _busy3 = true);
    final outcome = await NetworkErrorHandler.run(
      context,
      () => _svc.submitInvestments(
          businessId: widget.businessId, rows: _investorEntries),
      timeout: kManaBulkTimeout,
    );
    if (!mounted) return;
    setState(() {
      _busy3 = false;
      _investorOutcome = outcome;
      if (outcome != null && !outcome.rejected) _investorEntries.clear();
    });
  }

  Future<void> _shareholderSubmit() async {
    final rows = _shareholderEntries;
    final declared = int.tryParse(_declaredShareProfit.text.trim());
    if (rows.isEmpty) return;
    if (declared == null) {
      _toast('Enter the profit you are sharing out, in whole rupees.');
      return;
    }
    setState(() => _busy3 = true);
    final result = await NetworkErrorHandler.run(
      context,
      timeout: kManaBulkTimeout,
      () => _svc.importShareholders(
        businessId: widget.businessId,
        // The cut-off, which the chooser asks for before anything else. It
        // used to fall back to today because the date was not chosen until
        // the snapshot page, three pages later — so a shareholder's declaration
        // was dated the day the migration was run rather than the day the book
        // stopped.
        declaredOn: _cutoffDate ?? _plan?.cutoff ?? manaNowIst(),
        declaredProfit: declared,
        rows: rows,
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy3 = false;
      _shareholderResult = result;
      if (result != null) _shareholderEntries.clear();
    });
  }

  // -------------------------------------------------------------------
  // 4 — Customers
  // -------------------------------------------------------------------

  Future<void> _customerTemplate() async {
    setState(() => _busy4 = true);
    try {
      final bytes = await _svc.buildCustomerGridTemplate(businessId: widget.businessId, language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-Customers-Template.xlsx');
    } catch (e) {
      _toast('Could not build the template: $e');
    } finally {
      if (mounted) setState(() => _busy4 = false);
    }
  }

  Future<void> _customerPick() async {
    final file = await _pickSpreadsheet();
    if (file == null) return;
    if (!mounted) return;
    setState(() {
      _busy4 = true;
      _customerFormatError = null;
      _customerParse = null;
      _customerOutcome = null;
      _emiResult = null;
      _customerFileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      final parse = BulkOnboardingService.parseCustomerGridBytes(bytes, file.name);
      if (!mounted) return;
      setState(() => _customerParse = parse);
    } on ImportFormatException catch (e) {
      if (mounted) setState(() => _customerFormatError = e.message);
    } catch (e) {
      if (mounted) setState(() => _customerFormatError = 'Could not read this file: $e');
    } finally {
      if (mounted) setState(() => _busy4 = false);
    }
  }

  /// Loans first, then the instalment history against them. The loan import is
  /// all-or-nothing; the EMI pass deliberately is not (one record_collection
  /// call per instalment, no bulk RPC), so it only runs once the loans it
  /// needs are actually there.
  Future<void> _customerSubmit() async {
    final parse = _customerParse;
    if (parse == null || parse.loans.isEmpty) return;
    setState(() {
      _busy4 = true;
      _emiProgressLabel = '';
    });

    // Minted here — at the tap, outside the closure NetworkErrorHandler
    // re-invokes on Retry — so every retry of THIS import carries the same
    // key and the server replays instead of importing again. Cleared on
    // success below, so a later, deliberate second import is a new action.
    _loanImportKey ??= manaIdempotencyKey();

    // What the history on the same sheet adds up to, per customer. The server
    // uses it to decide whether the loan opens unpaid, and to check it against
    // a typed balance if the Owner filled both.
    final emiTotals = <String, int>{};
    for (final row in parse.schedule) {
      emiTotals[row.mlid] =
          (emiTotals[row.mlid] ?? 0) + row.entries.fold<int>(0, (a, e) => a + e.amount);
    }

    final loanOutcome = await NetworkErrorHandler.run(
      context,
      () => _svc.submitCustomerLoans(
        businessId: widget.businessId,
        rows: parse.loans,
        emiTotals: emiTotals,
        idempotencyKey: _loanImportKey,
      ),
      timeout: kManaBulkTimeout,
    );
    if (!mounted) return;
    setState(() => _customerOutcome = loanOutcome);

    if (loanOutcome == null || loanOutcome.rejected) {
      setState(() => _busy4 = false);
      return;
    }
    // The loans are in. Anything from here is a fresh action.
    _loanImportKey = null;
    if (parse.schedule.isEmpty) {
      setState(() => _busy4 = false);
      return;
    }

    final emi = await NetworkErrorHandler.run(context, timeout: kManaBulkTimeout, () async {
      return _svc.submitEmiSchedule(
        businessId: widget.businessId,
        schedule: parse.schedule,
        onProgress: (mlid, done, total) {
          if (mounted) setState(() => _emiProgressLabel = '$mlid — $done/$total');
        },
      );
    });
    if (!mounted) return;
    setState(() {
      _busy4 = false;
      _emiResult = emi;
      // Only once the instalments are through as well — the parse holds both,
      // and clearing it earlier would lose the schedule the EMI pass needs.
      if (emi != null && emi.errors.isEmpty) _customerParse = null;
    });
  }

  /// Only the instalments that FAILED come back in the correction file.
  /// Re-uploading the ones that already recorded would collect them twice —
  /// the EMI pass is the one import here that is not all-or-nothing.
  Future<void> _emiDownloadCorrection() async {
    final parse = _customerParse;
    final result = _emiResult;
    if (parse == null || result == null) return;
    try {
      final bytes = BulkOnboardingService.buildEmiCorrectionFile(
          schedule: parse.schedule, errors: result.errors, language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-EMI-History-Corrections.xlsx');
    } catch (e) {
      _toast('Could not build the corrected file: $e');
    }
  }

  // -------------------------------------------------------------------
  // 5 — Agents
  // -------------------------------------------------------------------

  Future<void> _attendanceTemplate() async {
    setState(() => _busy5 = true);
    try {
      final bytes = await _svc.buildAttendanceTemplate(businessId: widget.businessId, language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-Agent-Attendance-Template.xlsx');
    } catch (e) {
      _toast('Could not build the template: $e');
    } finally {
      if (mounted) setState(() => _busy5 = false);
    }
  }

  Future<void> _attendancePick() async {
    final file = await _pickSpreadsheet(allowCsv: true);
    if (file == null) return;
    if (!mounted) return;
    setState(() {
      _busy5 = true;
      _attendanceError = null;
      _attendance = null;
      _attendanceRecorded = null;
      _attendanceFileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      final rows = BulkOnboardingService.parseAttendanceBytes(bytes, file.name);
      if (!mounted) return;
      setState(() => _attendance = rows);
    } on ImportFormatException catch (e) {
      if (mounted) setState(() => _attendanceError = e.message);
    } catch (e) {
      if (mounted) setState(() => _attendanceError = 'Could not read this file: $e');
    } finally {
      if (mounted) setState(() => _busy5 = false);
    }
  }

  Future<void> _attendanceSubmit() async {
    final rows = _attendance;
    if (rows == null || rows.isEmpty) return;
    setState(() => _busy5 = true);
    final recorded = await NetworkErrorHandler.run(
      context,
      () => _svc.recordAttendance(businessId: widget.businessId, rows: rows),
      timeout: kManaBulkTimeout,
    );
    if (!mounted) return;
    setState(() {
      _busy5 = false;
      _attendanceRecorded = recorded;
      if (recorded != null) _attendance = null;
    });
  }

  // -------------------------------------------------------------------
  // 6 — Opening Snapshot
  // -------------------------------------------------------------------

  Future<void> _pickCutoff() async {
    // IST, never the handset clock — a cut-off date is a business date.
    final today = manaNowIst();
    final picked = await showDatePicker(
      context: context,
      initialDate: _cutoffDate ?? today,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked != null && mounted) setState(() => _cutoffDate = picked);
  }

  Future<void> _snapshotSubmit() async {
    final cutoff = _cutoffDate;
    final bf = int.tryParse(_openingBf.text.trim());
    final lb = int.tryParse(_declaredLineBalance.text.trim());
    final profit = int.tryParse(_declaredProfit.text.trim());
    if (cutoff == null || bf == null || lb == null || profit == null) {
      _toast('Fill in the cut-off date and all three amounts, in whole rupees.');
      return;
    }
    setState(() => _busy6 = true);
    final result = await NetworkErrorHandler.run(
      context,
      () => _svc.recordOpeningSnapshot(
        businessId: widget.businessId,
        cutoffDate: cutoff,
        openingBf: bf,
        declaredLineBalance: lb,
        declaredProfit: profit,
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy6 = false;
      _snapshot = result;
    });
  }

  // -------------------------------------------------------------------
  // 7 — Weekly Account
  // -------------------------------------------------------------------

  Future<void> _weeklyTemplate() async {
    setState(() => _busy7 = true);
    try {
      final bytes = _svc.buildWeeklyTemplate(language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-Weekly-Account-Template.xlsx');
    } catch (e) {
      _toast('Could not build the template: $e');
    } finally {
      if (mounted) setState(() => _busy7 = false);
    }
  }

  Future<void> _weeklyPick() async {
    final file = await _pickSpreadsheet(allowCsv: true);
    if (file == null) return;
    if (!mounted) return;
    setState(() {
      _busy7 = true;
      _weeklyError = null;
      _weeklyRows = null;
      _weeklyResult = null;
      _weeklyFileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      final rows = BulkOnboardingService.parseWeeklyBytes(bytes, file.name);
      if (!mounted) return;
      setState(() => _weeklyRows = rows);
    } on ImportFormatException catch (e) {
      if (mounted) setState(() => _weeklyError = e.message);
    } catch (e) {
      if (mounted) setState(() => _weeklyError = 'Could not read this file: $e');
    } finally {
      if (mounted) setState(() => _busy7 = false);
    }
  }

  Future<void> _weeklySubmit() async {
    final rows = _weeklyRows;
    if (rows == null || rows.isEmpty) return;
    setState(() => _busy7 = true);
    final result = await NetworkErrorHandler.run(
      context,
      () => _svc.importWeeklyAccount(businessId: widget.businessId, rows: rows),
      timeout: kManaBulkTimeout,
    );
    if (!mounted) return;
    setState(() {
      _busy7 = false;
      _weeklyResult = result;
      // Re-importing the same weeks is safe — each is keyed on its account date
      // and upserted — but the parsed rows are dropped so a stray second press
      // cannot re-send a file the Owner has since edited.
      if (result != null) _weeklyRows = null;
    });
    if (result != null) await _refreshProfit();
  }

  Future<void> _refreshProfit() async {
    final summary = await NetworkErrorHandler.run(
      context,
      () => _svc.profitSummary(businessId: widget.businessId),
    );
    if (!mounted) return;
    setState(() => _profitSummary = summary);
  }

  // -------------------------------------------------------------------

  Future<XFile?> _pickSpreadsheet({bool allowCsv = false}) {
    final group = XTypeGroup(
      label: ref.t('spreadsheet'),
      extensions: allowCsv ? const ['xlsx', 'csv'] : const ['xlsx'],
    );
    return openFile(acceptedTypeGroups: [group]);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: ManaText.raw(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: ManaText.raw(ref.t('bulk_onboarding')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _stepHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _alreadyIn(_progressParts(_step)),
                    // Switched on the PAGE, not its number: which pages exist
                    // depends on what the Owner said their book has, so an
                    // index means nothing on its own.
                    switch (_page) {
                      _WizardPage.plan => _planSection(),
                      _WizardPage.identities => _identitiesSection(),
                      _WizardPage.investors => _investorsSection(),
                      _WizardPage.customers => _customersSection(),
                      _WizardPage.agents => _agentsSection(),
                      _WizardPage.snapshot => _snapshotSection(),
                      _WizardPage.weekly => _weeklySection(),
                      _WizardPage.finish => _finishSection(),
                    },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Eight labels will not fit side by side on a 360dp screen, so the header is
  /// a position plus the current page's name rather than a row of chips.
  Widget _stepHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg, vertical: ManaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ManaText.raw(
                  '${_step + 1}. ${_page.title}',
                  maxLines: 2,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              ManaText.raw(
                '${_step + 1}/${_pages.length}',
                style: ManaType.fine,
              ),
            ],
          ),
          const SizedBox(height: ManaSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(ManaRadius.sm),
            child: LinearProgressIndicator(
              value: (_step + 1) / _pages.length,
              minHeight: 4,
              backgroundColor: ManaColors.surfaceSunken,
              color: ManaColors.brand,
            ),
          ),
          // Said out loud. Opening the wizard and finding yourself on page 5
          // with no explanation reads as lost work, and the way back has to be
          // one tap rather than five presses of Back.
          if (_resumedAt != null) ...[
            const SizedBox(height: ManaSpacing.xs),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: ManaSpacing.sm,
              children: [
                ManaText.raw(
                  'Carried on where you stopped.',
                  style: ManaType.fine,
                ),
                TextButton(
                  onPressed: _startFromTheBeginning,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const ManaText.raw('Start From Page 1',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// "Already in: 55 customers, 5 villages" — what this page has put into the
  /// business so far, counted from the live rows rather than remembered.
  ///
  /// Shown on every page including the one just submitted, because the case
  /// that matters is the Owner coming BACK to a page: nothing in memory, a
  /// file picker sitting there as if untouched, and no way to tell an empty
  /// page from a finished one except by importing again.
  Widget _alreadyIn(List<String> parts) {
    if (_progress == null || parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: ManaCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline, size: 18, color: ManaColors.statusGood),
            const SizedBox(width: ManaSpacing.sm),
            // Flexible, not bare: this is a long line at 2.0x text scale on a
            // 360dp screen — the overflow class CLAUDE.md calls out.
            Flexible(
              child: ManaText.raw(
                'Already In — ${parts.join(', ')}',
                style: ManaType.note,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The counts each page is responsible for. Empty means this page has put
  /// nothing in yet, and no line is drawn.
  List<String> _progressParts(int step) {
    final p = _progress;
    if (p == null) return const [];
    String n(int v, String one, String many) => '$v ${v == 1 ? one : many}';

    switch (step) {
      case 0:
        return [
          if (p.count('customers') > 0) n(p.count('customers'), 'customer', 'customers'),
          if (p.count('investors') > 0) n(p.count('investors'), 'investor', 'investors'),
          if (p.count('agents') > 0) n(p.count('agents'), 'agent', 'agents'),
        ];
      case 1:
        return [
          if (p.count('villages') > 0) n(p.count('villages'), 'village', 'villages'),
          if (p.count('areas') > 0) n(p.count('areas'), 'area', 'areas'),
        ];
      case 2:
        return [
          if (p.count('investments') > 0)
            '${n(p.count('investments'), 'investment', 'investments')}, '
                '${manaRupees(p.count('investment_amount'))}',
        ];
      case 3:
        return [
          if (p.count('loans') > 0)
            '${n(p.count('loans'), 'loan', 'loans')}, '
                '${manaRupees(p.count('line_balance'))} outstanding',
          if (p.count('collections') > 0)
            n(p.count('collections'), 'instalment', 'instalments'),
        ];
      case 4:
        return [
          if (p.count('attendance_days') > 0)
            n(p.count('attendance_days'), 'working day', 'working days'),
        ];
      case 5:
        return [
          if (p.date('snapshot_cutoff') != null) 'snapshot to ${p.date('snapshot_cutoff')}',
          if (p.count('shareholders') > 0)
            n(p.count('shareholders'), 'shareholder', 'shareholders'),
        ];
      case 6:
        return [
          if (p.count('weeks') > 0)
            '${n(p.count('weeks'), 'week', 'weeks')} to ${p.date('weeks_through')}',
        ];
      default:
        // The Finish page shows the whole book, not one page's share.
        return [
          if (p.count('customers') > 0) n(p.count('customers'), 'customer', 'customers'),
          if (p.count('loans') > 0)
            '${n(p.count('loans'), 'loan', 'loans')}, ${manaRupees(p.count('line_balance'))} outstanding',
          if (p.count('weeks') > 0) n(p.count('weeks'), 'week', 'weeks'),
        ];
    }
  }

  Widget _navBar({required VoidCallback? onNext, String nextLabel = 'next'}) {
    // Both buttons are Flexible rather than bare — "Back" + "Finish" at a
    // 2.0x text scale is wide enough to overflow a 360dp-wide Row with no
    // flexible child, the same bug class CLAUDE.md calls out.
    return Padding(
      padding: const EdgeInsets.only(top: ManaSpacing.lg),
      child: Row(
        children: [
          if (_step > 0)
            Flexible(
              child: OutlinedButton(
                onPressed: () => _goTo(_step - 1),
                child: ManaText.raw(ref.t('back')),
              ),
            ),
          const Spacer(),
          if (onNext != null)
            Flexible(child: FilledButton(onPressed: onNext, child: ManaText.raw(nextLabel))),
        ],
      ),
    );
  }

  Widget _intro(String text) => ManaText.raw(
        text,
        style: ManaType.note,
      );

  Widget _fileButtons({
    required bool busy,
    required VoidCallback onTemplate,
    required VoidCallback onPick,
    String? fileName,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: ManaSpacing.lg),
        OutlinedButton.icon(
          onPressed: busy ? null : onTemplate,
          icon: const Icon(Icons.download_outlined),
          label: ManaText.raw(ref.t('get_template')),
        ),
        const SizedBox(height: ManaSpacing.md),
        OutlinedButton.icon(
          onPressed: busy ? null : onPick,
          icon: const Icon(Icons.folder_open_outlined),
          label: ManaText.raw(ref.t('choose_file')),
        ),
        if (fileName != null) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(fileName, style: ManaType.small),
        ],
        if (error != null) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(error, style: ManaType.noteBad),
        ],
        if (busy) ...[
          const SizedBox(height: ManaSpacing.lg),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  // --- 0 What your book has ---------------------------------------------

  Future<void> _savePlan() async {
    final plan = _plan;
    if (plan == null || !plan.isComplete) {
      _toast('Choose the cut-off date first — everything else is counted as at that day.');
      return;
    }
    setState(() => _planSaving = true);
    final ok = await NetworkErrorHandler.run(
      context,
      () async {
        await _svc.saveMigrationPlan(businessId: widget.businessId, plan: plan);
        return true;
      },
    );
    if (!mounted) return;
    setState(() => _planSaving = false);
    if (ok == true) _goNext();
  }

  Future<void> _pickPlanCutoff() async {
    final today = manaNowIst();
    final picked = await showDatePicker(
      context: context,
      initialDate: _plan?.cutoff ?? today,
      firstDate: DateTime(2000),
      // Everything in the book is stated as at this day, so it cannot be one
      // that has not happened.
      lastDate: today,
    );
    if (picked != null && mounted) {
      setState(() {
        _plan = (_plan ?? const MigrationPlan()).copyWith(cutoff: picked);
        _cutoffDate = picked;
      });
    }
  }

  Widget _planTick({
    required String label,
    required String note,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      CheckboxListTile(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: ManaText.raw(label, style: ManaType.strong),
        subtitle: ManaText.raw(note, style: ManaType.small),
      );

  Widget _planSection() {
    final plan = _plan ?? const MigrationPlan();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(
          'Tell us what your book has before we start, and we will only ask '
          'for those. Everything you enter is counted as at the cut-off date — '
          'the day your book stops and this app takes over.',
        ),
        const SizedBox(height: ManaSpacing.md),
        InkWell(
          onTap: _pickPlanCutoff,
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Cut-Off Date *',
              suffixIcon: Icon(Icons.calendar_today_outlined),
            ),
            child: ManaText.raw(
              plan.cutoff == null
                  ? 'Tap to choose'
                  : '${plan.cutoff!.day.toString().padLeft(2, '0')}/'
                      '${plan.cutoff!.month.toString().padLeft(2, '0')}/'
                      '${plan.cutoff!.year}',
            ),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        const ManaText.raw('What your book has', style: ManaType.strong),
        _planTick(
          label: 'Investors',
          note: 'People whose money is in the business, including your own.',
          value: plan.investors,
          onChanged: (v) => setState(() => _plan = plan.copyWith(investors: v)),
        ),
        _planTick(
          label: 'Profit Shares',
          note: 'Who shares the profit. Not the same list as investors.',
          value: plan.shareholders,
          onChanged: (v) => setState(() => _plan = plan.copyWith(shareholders: v)),
        ),
        _planTick(
          label: 'Customers With Running Loans',
          note: 'Loans that were still being collected when your book stopped.',
          value: plan.customers,
          onChanged: (v) => setState(() => _plan = plan.copyWith(customers: v)),
        ),
        if (plan.customers)
          Padding(
            padding: const EdgeInsets.only(left: ManaSpacing.lg),
            child: _planTick(
              label: 'Instalment History For Those Loans',
              note: 'Every instalment ever paid. Leave off if your book only '
                  'keeps a running balance — the balance alone is enough.',
              value: plan.emiHistory,
              onChanged: (v) => setState(() => _plan = plan.copyWith(emiHistory: v)),
            ),
          ),
        _planTick(
          label: 'Agent Attendance',
          note: 'Which days each agent worked.',
          value: plan.attendance,
          onChanged: (v) => setState(() => _plan = plan.copyWith(attendance: v)),
        ),
        _planTick(
          label: 'Weekly Account Book',
          note: 'Your week-by-week accounts. Without it the app works the days '
              'out itself, and your BF will be its figure rather than yours.',
          value: plan.weekly,
          onChanged: (v) => setState(() => _plan = plan.copyWith(weekly: v)),
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (_planSaving)
          const Center(child: CircularProgressIndicator())
        else
          ElevatedButton.icon(
            onPressed: _savePlan,
            icon: const Icon(Icons.check),
            label: const ManaText.raw('Start'),
          ),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(
          'You can come back and change this at any time before you finish.',
          style: ManaType.fine,
        ),
      ],
    );
  }

  // --- 1 Identities -------------------------------------------------------

  Widget _identitiesSection() {
    final parse = _identityParse;
    final outcome = _identityOutcome;
    final undecided = _duplicates.where((d) => !_dedupeDecisions.containsKey(d.row)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(
          'One file, every person in the book — Agent, Customer and Investor '
          'together. Write each name the way your book does: surname first, '
          'then the name, in the one Name column. Phone and Aadhaar are both '
          'optional. Nothing is saved on this page: the villages named here '
          'have to be confirmed first.',
        ),
        _fileButtons(
          busy: _busy1,
          onTemplate: _identityTemplate,
          onPick: _identityPick,
          fileName: _identityFileName,
          error: _identityFormatError,
        ),
        if (parse != null && !_busy1) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw('${parse.rows.length} rows ready', style: ManaType.heavy),
          if (_duplicates.isNotEmpty) ...[
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw('${_duplicates.length} rows need review',
                style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusWarn)),
            // One decision per flagged row is fine for three; the live book
            // flagged 55, and chip-by-chip is where an Owner gives up or
            // mis-taps. These set every row at once and each card still shows
            // what it landed on, so a single row can be changed back after.
            const SizedBox(height: ManaSpacing.sm),
            Wrap(
              spacing: ManaSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _decideAllDuplicates('skip'),
                  icon: const Icon(Icons.merge_type, size: 18),
                  label: ManaText.raw(ref.t('merge_all')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _decideAllDuplicates('keep'),
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: ManaText.raw(ref.t('ignore_all')),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            for (final d in _duplicates) _duplicateCard(d),
            if (undecided > 0) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw('$undecided row(s) still need a decision.',
                  style: ManaType.noteBad),
            ],
          ],
        ],
        // This is the page that WRITES, now that Areas & Villages is gone.
        // Walking past it with a parsed file and nothing imported loses the
        // whole sheet silently, and the next page then looks like ordinary
        // progress — which is exactly what happened on the first live run.
        if (parse != null && parse.rows.isNotEmpty && !_busy1) ...[
          const SizedBox(height: ManaSpacing.lg),
          ElevatedButton.icon(
            onPressed: undecided > 0 ? null : _saveIdentities,
            icon: const Icon(Icons.upload_outlined),
            label: const ManaText.raw('Import These People'),
          ),
        ],
        if (_busy1) ...[
          const SizedBox(height: ManaSpacing.lg),
          const Center(child: CircularProgressIndicator()),
        ],
        if (outcome != null && !_busy1)
          _outcomeBlock(outcome,
              noun: 'identities',
              onDownloadCorrection: outcome.rejected ? _identityDownloadCorrection : null),
        _navBar(onNext: _confirmLeavingUnimported),
      ],
    );
  }

  void _decideAllDuplicates(String decision) {
    setState(() {
      _dedupeDecisions
        ..clear()
        ..addAll(manaDecideAllDuplicates(_duplicates, decision));
    });
  }

  Widget _duplicateCard(DuplicateMatch d) {
    final decision = _dedupeDecisions[d.row];
    return ManaCard(
      padding: ManaSpacing.sm,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(
                ref.t('row_duplicate_note').replaceAll('{row}', '${d.row}').replaceAll(
                    '{reason}',
                    d.reason == "duplicate_in_file"
                        ? ref.t('duplicate_in_file')
                        : ref.t('looks_like_existing_customer')),
                style: ManaType.smallStrong),
            if (d.candidates.isNotEmpty)
              ManaText.raw(d.candidates.join(' · '),
                  style: ManaType.fine),
            const SizedBox(height: ManaSpacing.xs),
            Wrap(
              spacing: ManaSpacing.sm,
              children: [
                ChoiceChip(
                  label: ManaText.raw(ref.t('merge_skip')),
                  selected: decision == 'skip',
                  onSelected: (_) => setState(() => _dedupeDecisions[d.row] = 'skip'),
                ),
                ChoiceChip(
                  label: ManaText.raw(ref.t('ignore_import')),
                  selected: decision == 'keep',
                  onSelected: (_) => setState(() => _dedupeDecisions[d.row] = 'keep'),
                ),
              ],
            ),
          ],
        ),

    );
  }

  // --- 2 Investors --------------------------------------------------------

  /// One pending entry, with a way to take it back out before saving.
  Widget _entryTile({
    required String title,
    required String detail,
    required VoidCallback onRemove,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ManaText.raw(title, style: ManaType.strong),
                  ManaText.raw(detail, style: ManaType.small),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              tooltip: 'Remove',
            ),
          ],
        ),
      );

  Widget _investorsSection() {
    final people = _investorCandidates ?? const <ManaMemberRef>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(
          'Every investor, with what they put in and when. Your own capital is '
          'equity, so add yourself here as an investor too. ROI is Rupees per '
          '100 per MONTH.',
        ),
        ManaMemberPicker(
          members: people,
          alreadyUsed: {for (final e in _investorEntries) e['mlid'] as String},
          onPick: _addInvestment,
          emptyNote: 'Nobody is recorded as an investor yet. Add them on '
              'page 1 first — this page is for what they put in, not who '
              'they are.',
        ),
        if (_investorEntries.isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw('${_investorEntries.length} to save', style: ManaType.heavy),
          for (var i = 0; i < _investorEntries.length; i++)
            _entryTile(
              title: _investorEntries[i]['full_name'] as String? ??
                  _investorEntries[i]['mlid'] as String,
              detail: '₹${_investorEntries[i]['invested_amount']} · '
                  'ROI ${_investorEntries[i]['roi']} · '
                  '${_investorEntries[i]['invested_date']}',
              onRemove: () => setState(() => _investorEntries.removeAt(i)),
            ),
          const SizedBox(height: ManaSpacing.sm),
          ElevatedButton.icon(
            onPressed: _busy3 ? null : _saveInvestments,
            icon: const Icon(Icons.save_outlined),
            label: const ManaText.raw('Save Investments'),
          ),
        ],
        if (_investorOutcome != null && !_busy3) _outcomeBlock(_investorOutcome!, noun: 'investments'),
        const Divider(height: ManaSpacing.xl),
        _intro(
          'Money any of them took back out before today. Leave it empty if none '
          'did. Amount is the cash that left the box — interest that was only '
          'settled against what they had accrued belongs in the weekly account '
          'sheet, not here.',
        ),
        _fileButtons(
          busy: _busy3,
          onTemplate: _withdrawalTemplate,
          onPick: _withdrawalPick,
          fileName: _withdrawalFileName,
          error: _withdrawalError,
        ),
        if (_withdrawals != null && !_busy3) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw('${_withdrawals!.length} withdrawals ready',
              style: ManaType.heavy),
          const SizedBox(height: ManaSpacing.sm),
          ElevatedButton.icon(
            onPressed: _withdrawals!.isEmpty ? null : _withdrawalSubmit,
            icon: const Icon(Icons.upload_outlined),
            label: const ManaText.raw('Import Withdrawals'),
          ),
        ],
        if (_withdrawalOutcome != null && !_busy3)
          _outcomeBlock(_withdrawalOutcome!, noun: 'withdrawals'),
        const Divider(height: ManaSpacing.xl),
        _intro(
          'Who shares in the profit. This is a different list from the one '
          'above: a shareholder may hold no investment at all, and an investor '
          'may take no share.',
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _declaredShareProfit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Profit being shared out *',
            prefixText: '₹ ',
          ),
        ),
        ManaMemberPicker(
          members: people,
          alreadyUsed: {for (final e in _shareholderEntries) e['mlid'] as String},
          onPick: _addShareholder,
          emptyNote: 'Nobody is on the books yet. Add people on page 1 first.',
        ),
        if (_shareholderEntries.isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(
            '${_shareholderEntries.length} to save · '
            '${_shareholderEntries.fold<num>(0, (a, e) => a + (e['share_percent'] as num))}% shared',
            style: ManaType.heavy,
          ),
          for (var i = 0; i < _shareholderEntries.length; i++)
            _entryTile(
              title: _shareholderEntries[i]['full_name'] as String,
              detail: '${_shareholderEntries[i]['share_percent']}%'
                  '${_shareholderEntries[i]['paid_on'] == null ? '' : ' · paid ${_shareholderEntries[i]['paid_on']}'}',
              onRemove: () => setState(() => _shareholderEntries.removeAt(i)),
            ),
          const SizedBox(height: ManaSpacing.sm),
          ElevatedButton.icon(
            onPressed: _busy3 ? null : _shareholderSubmit,
            icon: const Icon(Icons.save_outlined),
            label: const ManaText.raw('Record Profit Shares'),
          ),
        ],
        if (_shareholderResult != null && !_busy3) ...[
          const SizedBox(height: ManaSpacing.md),
          _amountRow('Declared profit', _shareholderResult!['declared_profit']),
          _amountRow('Computed profit', _shareholderResult!['computed_profit']),
          _amountRow('Carried forward', _shareholderResult!['carry_forward']),
          const SizedBox(height: ManaSpacing.sm),
          for (final s in (_shareholderResult!['shareholders'] as List? ?? const []))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ManaText.raw(
                '${s['full_name']} · ₹${s['share_amount']}'
                '${s['accrued_to_paid_on'] == null ? "" : " + ₹${s['accrued_to_paid_on']} accrued"}',
                style: ManaType.small,
              ),
            ),
        ],
        _navBar(onNext: _goNext),
      ],
    );
  }

  // --- 4 Customers --------------------------------------------------------

  Widget _customersSection() {
    final parse = _customerParse;
    final emi = _emiResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(
          'One sheet per repayment frequency — Daily, Weekly, Monthly. The '
          'sheet is the frequency, so it cannot be typed wrong. Each row is one '
          'loan; the EMI columns beside it are that loan\'s instalment history, '
          'every instalment ever, one amount and one date per pair.',
        ),
        _fileButtons(
          busy: _busy4,
          onTemplate: _customerTemplate,
          onPick: _customerPick,
          fileName: _customerFileName,
          error: _customerFormatError,
        ),
        if (_busy4 && _emiProgressLabel.isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.sm),
          Center(child: ManaText.raw(_emiProgressLabel, style: ManaType.small)),
        ],
        if (parse != null && !_busy4) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw(
            '${parse.loans.length} loans · '
            '${parse.schedule.fold<int>(0, (a, r) => a + r.entries.length)} instalments ready',
            style: ManaType.heavy,
          ),
          // A sheet whose history could not be read must say so BEFORE the
          // import, not leave a bare "0 instalments" to be noticed.
          if (parse.unreadableInstalments > 0)
            ManaText.raw(
              '${parse.unreadableInstalments} instalment cells could not be '
              'read — each needs a whole rupee amount and a yyyy-mm-dd date.',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: ManaColors.statusBad),
            ),
          const SizedBox(height: ManaSpacing.sm),
          ElevatedButton.icon(
            onPressed: parse.loans.isEmpty ? null : _customerSubmit,
            icon: const Icon(Icons.upload_outlined),
            label: const ManaText.raw('Import Loans And History'),
          ),
        ],
        if (_customerOutcome != null && !_busy4) _outcomeBlock(_customerOutcome!, noun: 'customer loans'),
        if (emi != null && !_busy4) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw('${emi.recorded} instalments recorded.',
              style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusGood)),
          // On a resumed replay this is most of the sheet, and without it
          // "12 recorded" against 216 rows reads as a failure rather than as
          // the other 204 already being in.
          if (emi.skipped > 0)
            ManaText.raw(
              '${emi.skipped} were already recorded and were left alone.',
              style: ManaType.note,
            ),
          if (emi.errors.isNotEmpty) ...[
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw('${emi.errors.length} could not be recorded:',
                style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusBad)),
            for (final e in emi.errors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: ManaText.raw(
                  '${e.mlid}${e.instalment > 0 ? " · instalment ${e.instalment}" : ""}: ${e.message}',
                  style: ManaType.small,
                ),
              ),
            const SizedBox(height: ManaSpacing.sm),
            OutlinedButton.icon(
              onPressed: _emiDownloadCorrection,
              icon: const Icon(Icons.download_outlined),
              label: ManaText.raw(ref.t('download_corrected_file')),
            ),
          ],
        ],
        _navBar(onNext: _goNext),
      ],
    );
  }

  // --- 5 Agents -----------------------------------------------------------

  Widget _agentsSection() {
    final rows = _attendance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(
          'Which days each agent worked, one row per agent per day. Salary and '
          'expenses are not entered here — they are declared in the weekly '
          'account sheet, which is where your book records them.',
        ),
        _fileButtons(
          busy: _busy5,
          onTemplate: _attendanceTemplate,
          onPick: _attendancePick,
          fileName: _attendanceFileName,
          error: _attendanceError,
        ),
        if (rows != null && !_busy5) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw('${rows.length} attendance rows ready',
              style: ManaType.heavy),
          const SizedBox(height: ManaSpacing.sm),
          ElevatedButton.icon(
            onPressed: rows.isEmpty ? null : _attendanceSubmit,
            icon: const Icon(Icons.upload_outlined),
            label: const ManaText.raw('Record Attendance'),
          ),
        ],
        if (_attendanceRecorded != null && !_busy5) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw('${_attendanceRecorded!.recorded} days recorded.',
              style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusGood)),
          // The RPC skips a day the agent already has, so re-uploading is
          // safe — but without this line a second upload reports a bare
          // "0 days recorded" and reads as a failure.
          if (_attendanceRecorded!.alreadyIn > 0)
            ManaText.raw(
              '${_attendanceRecorded!.alreadyIn} were already recorded and '
              'were left alone.',
              style: ManaType.note,
            ),
        ],
        _navBar(onNext: _goNext),
      ],
    );
  }

  // --- 6 Opening Snapshot -------------------------------------------------

  Widget _snapshotSection() {
    final snap = _snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(
          'What the book said on the cut-off date. BF is cash you could count; '
          'line balance is what customers still owe, and it deliberately sits '
          'outside BF. Your declared profit and the one computed from what you '
          'have imported will differ — a paper book rounds and back-dates — so '
          'the difference is carried forward rather than argued with.',
        ),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: ManaText.raw(
                _cutoffDate == null
                    ? 'No cut-off date chosen'
                    : 'Cut-off: ${_cutoffDate!.toIso8601String().split("T").first}',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Flexible(
              child: OutlinedButton(
                onPressed: _busy6 ? null : _pickCutoff,
                child: const ManaText.raw('Choose Date'),
              ),
            ),
          ],
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _openingBf,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Opening BF (cash in hand) *'),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _declaredLineBalance,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Line Balance in your book *'),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _declaredProfit,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Profit in your book *'),
        ),
        if (_busy6) ...[
          const SizedBox(height: ManaSpacing.lg),
          const Center(child: CircularProgressIndicator()),
        ],
        if (!_busy6) ...[
          const SizedBox(height: ManaSpacing.lg),
          ElevatedButton.icon(
            onPressed: _snapshotSubmit,
            icon: const Icon(Icons.save_outlined),
            label: const ManaText.raw('Save Opening Snapshot'),
          ),
        ],
        if (snap != null && !_busy6) ...[
          const SizedBox(height: ManaSpacing.lg),
          _amountRow('Line balance — your book', snap['declared_line_balance']),
          _amountRow('Line balance — computed', snap['computed_line_balance']),
          _amountRow('Difference', snap['line_balance_difference']),
          const Divider(),
          _amountRow('Profit — your book', snap['declared_profit']),
          _amountRow('Profit — computed', snap['computed_profit']),
          _amountRow('Carried forward', snap['profit_carry_forward']),
        ],
        _navBar(onNext: _goNext),
      ],
    );
  }

  // --- 7 Weekly Account ---------------------------------------------------

  Widget _weeklySection() {
    final rows = _weeklyRows;
    final profit = _profitSummary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(
          'Your weekly book, one row per account — the date is the day you '
          'closed it, the last working day of that schedule. Expense lines go '
          'on the second sheet against the same date. This is what BF comes '
          'from: it is imported as you wrote it, never recalculated.',
        ),
        _fileButtons(
          busy: _busy7,
          onTemplate: _weeklyTemplate,
          onPick: _weeklyPick,
          fileName: _weeklyFileName,
          error: _weeklyError,
        ),
        if (rows != null && !_busy7) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw(
            '${rows.length} weeks ready · '
            '${rows.fold<int>(0, (a, r) => a + ((r['expenses'] as List?)?.length ?? 0))} expense lines',
            style: ManaType.heavy,
          ),
          const SizedBox(height: ManaSpacing.sm),
          ElevatedButton.icon(
            onPressed: rows.isEmpty ? null : _weeklySubmit,
            icon: const Icon(Icons.upload_outlined),
            label: const ManaText.raw('Import Weekly Account'),
          ),
        ],
        if (_weeklyResult != null && !_busy7) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw('${_weeklyResult!['weeks']} weeks imported.',
              style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusGood)),
          _amountRow('Opening BF', _weeklyResult!['opening_bf']),
          _amountRow('Closing BF', _weeklyResult!['closing_bf']),
          ManaText.raw(
            'Book kept from ${_weeklyResult!['from']} through ${_weeklyResult!['through']}.',
            style: ManaType.note,
          ),
        ],
        const SizedBox(height: ManaSpacing.lg),
        OutlinedButton.icon(
          onPressed: _busy7 ? null : _refreshProfit,
          icon: const Icon(Icons.calculate_outlined),
          label: const ManaText.raw('Check Against My Book'),
        ),
        if (profit != null) ...[
          const SizedBox(height: ManaSpacing.md),
          _amountRow('Interest', profit['interest']),
          _amountRow('Fee (your book)', profit['fee']),
          _amountRow('Fee entered on loans', profit['fee_on_loans']),
          _amountRow('Expenses', profit['expenses']),
          _amountRow('Investor interest', profit['investor_interest']),
          _amountRow('Withdrawal interest', profit['withdrawal_interest']),
          const Divider(),
          _amountRow('Profit', profit['profit']),
          _amountRow('Line balance', profit['line_balance']),
          _amountRow('Collections', profit['collections']),
        ],
        _navBar(onNext: _goNext, nextLabel: 'finish'),
      ],
    );
  }

  // --- Finish -------------------------------------------------------------

  /// Named, not enforced. An Owner who ticked a section and then decided
  /// against it may still finish; they should just not find out afterwards.
  static const _gapLabels = <String, String>{
    'identities': 'the people',
    'investors': 'investors',
    'shareholders': 'profit shares',
    'customers': 'customer loans',
    'emi_history': 'instalment history',
    'attendance': 'agent attendance',
    'weekly': 'the weekly account book',
    'snapshot': 'the opening snapshot',
  };

  /// Asked once when the Finish page is first built. Not from initState: an
  /// Owner who never reaches the end should not pay for the query, and a
  /// failing call from build() is how the investor list came to try showing a
  /// snackbar mid-frame.
  void _refreshGapsOnce() {
    if (_gapsAsked) return;
    _gapsAsked = true;
    unawaited(_refreshGaps());
  }

  Future<void> _refreshGaps() async {
    try {
      final gaps = await _svc.migrationPlanGaps(widget.businessId);
      if (mounted) setState(() => _planGaps = gaps);
    } catch (_) {
      // A failure here must not stop an Owner finishing.
    }
  }

  Widget _finishSection() {
    _refreshGapsOnce();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('what_was_done'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: ManaSpacing.md),
        _checklistRow('Identities imported', _identityOutcome?.imported),
        _checklistRow('Investments recorded', _investorOutcome?.imported),
        _checklistRow('Customer loans recorded', _customerOutcome?.imported),
        _checklistRow('EMI instalments recorded', _emiResult?.recorded),
        _checklistRow('Attendance days recorded', _attendanceRecorded?.recorded),
        _checklistRow('Opening snapshot saved', _snapshot == null ? null : 1),
        _checklistRow('Weeks imported', (_weeklyResult?['weeks'] as num?)?.toInt()),
        if (_planGaps.isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw(
            'You said your book has these, and nothing has been entered for '
            'them yet: ${_planGaps.map((g) => _gapLabels[g] ?? g).join(', ')}.',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: ManaColors.statusWarn),
          ),
        ],
        const SizedBox(height: ManaSpacing.lg),
        _intro(
          'Anything not shown above yet can still be added — every page in this '
          'wizard can be re-run any time the migration is open.',
        ),
        const SizedBox(height: ManaSpacing.lg),
        FilledButton(onPressed: () => context.pop(), child: ManaText.raw(ref.t('done'))),
        _navBar(onNext: null),
      ],
    );
  }

  Widget _checklistRow(String label, int? value) {
    final done = value != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18, color: done ? ManaColors.statusGood : ManaColors.textSecondary),
          const SizedBox(width: ManaSpacing.sm),
          Expanded(child: ManaText.raw(label, style: const TextStyle(fontSize: 14))),
          ManaText.raw(done ? '$value' : '—', style: ManaType.emphasis),
        ],
      ),
    );
  }

  Widget _amountRow(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: ManaText.raw(label, style: const TextStyle(fontSize: 14))),
          ManaText.raw(
            value == null ? '—' : '₹${value.toString()}',
            style: ManaType.heavy,
          ),
        ],
      ),
    );
  }

  Widget _outcomeBlock(ImportOutcome outcome, {required String noun, VoidCallback? onDownloadCorrection}) {
    return Padding(
      padding: const EdgeInsets.only(top: ManaSpacing.md),
      child: outcome.rejected
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(
                  ref.t('nothing_imported_note').replaceAll('{count}', '${outcome.errors.length}'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusBad),
                ),
                const SizedBox(height: ManaSpacing.sm),
                for (final e in outcome.errors)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: ManaText.raw(
                        ref
                            .t('row_error_note')
                            .replaceAll('{row}', '${e.row}')
                            .replaceAll('{message}', e.message),
                        style: ManaType.small),
                  ),
                if (onDownloadCorrection != null) ...[
                  const SizedBox(height: ManaSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: onDownloadCorrection,
                    icon: const Icon(Icons.download_outlined),
                    label: ManaText.raw(ref.t('download_corrected_file')),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw('${outcome.imported} $noun imported.',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: ManaColors.statusGood)),
                // Re-uploading a sheet to finish a partly-failed import is the
                // normal way to recover; on that run this is most of the file,
                // and "0 imported" alone reads as a failure.
                if (outcome.skipped > 0)
                  ManaText.raw(
                    '${outcome.skipped} were already on the book and were left alone.',
                    style: ManaType.note,
                  ),
              ],
            ),
    );
  }
}
