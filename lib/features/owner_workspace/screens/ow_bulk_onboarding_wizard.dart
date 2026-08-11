import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/bulk_onboarding_service.dart';

/// P3 Bulk Migration Wizard — three spreadsheets to onboard a pre-existing
/// business's whole book at once, instead of one screen per person, loan or
/// instalment.
///
/// Not a locked spec screen ID — reached from OW-018 (Business Migration)
/// the same way `/import` (single-book loan import) is reached from
/// Settings, so it has no OW-0xx of its own.
///
/// Step 1 — Identities (Agent/Customer/Investor together, one file).
/// Step 2 — Details (3 tabs: Agent/Investor/Customer), prefilled from Step 1.
/// Step 3 — EMI History (optional) — up to 100 historical instalments per
///          customer, each its own amount+date pair.
///
/// Every write goes through the same server RPCs the rest of the app already
/// uses; see bulk_onboarding_service.dart for exactly which ones and why.
class BulkOnboardingWizardScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BulkOnboardingWizardScreen({super.key, required this.businessId});

  @override
  ConsumerState<BulkOnboardingWizardScreen> createState() => _BulkOnboardingWizardScreenState();
}

class _BulkOnboardingWizardScreenState extends ConsumerState<BulkOnboardingWizardScreen> {
  int _step = 0; // 0 Identities, 1 Details, 2 EMI History, 3 Finish

  // Step 1 — identities
  bool _busy1 = false;
  ParsedSheet? _identityParse;
  String? _identityFileName;
  String? _identityFormatError;
  List<DuplicateMatch> _duplicates = const [];
  final Map<int, String> _dedupeDecisions = {}; // row -> 'skip' | 'keep'
  ImportOutcome? _identityOutcome;

  // Step 2 — details
  bool _busy2 = false;
  Step2Parse? _step2Parse;
  String? _step2FileName;
  String? _step2FormatError;
  ImportOutcome? _investorOutcome;
  ImportOutcome? _customerLoanOutcome;

  // Step 3 — EMI history (optional)
  bool _busy3 = false;
  List<EmiScheduleRow>? _emiSchedule;
  String? _emiFileName;
  String? _emiFormatError;
  EmiSubmitResult? _emiResult;
  String _emiProgressLabel = '';

  String get _language => ref.read(authFlowProvider).language.enumValue;
  BulkOnboardingService get _svc => ref.read(bulkOnboardingServiceProvider);

  // -------------------------------------------------------------------
  // Step 1
  // -------------------------------------------------------------------

  Future<void> _identityTemplate() async {
    setState(() => _busy1 = true);
    try {
      final bytes = _svc.buildIdentityTemplate(language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-Identity-Import-Template.xlsx');
    } catch (e) {
      _toast('Could not build the template: $e');
    } finally {
      if (mounted) setState(() => _busy1 = false);
    }
  }

  Future<void> _identityPick() async {
    final group = XTypeGroup(label: ref.t('spreadsheet'), extensions: const ['xlsx', 'csv']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;

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

  Future<void> _identitySubmit() async {
    final parse = _identityParse;
    if (parse == null) return;
    // Every flagged row needs a decision before anything is sent — an
    // unreviewed duplicate must never silently import.
    final undecided = _duplicates.where((d) => !_dedupeDecisions.containsKey(d.row)).toList();
    if (undecided.isNotEmpty) {
      _toast('Review every flagged row (Merge or Ignore) before importing.');
      return;
    }
    setState(() => _busy1 = true);
    final outcome = await NetworkErrorHandler.run(context, () async {
      return _svc.submitIdentities(
        businessId: widget.businessId,
        rows: parse.rows,
        dedupeDecisions: _dedupeDecisions,
      );
    });
    if (!mounted) return;
    setState(() {
      _busy1 = false;
      _identityOutcome = outcome;
      if (outcome != null && !outcome.rejected) {
        _identityParse = null;
        _duplicates = const [];
      }
    });
  }

  Future<void> _identityDownloadCorrection() async {
    final parse = _identityParse;
    final outcome = _identityOutcome;
    if (parse == null || outcome == null) return;
    try {
      final bytes =
          BulkOnboardingService.buildIdentityCorrectionFile(rows: parse.rows, errors: outcome.errors, language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-Identity-Import-Corrections.xlsx');
    } catch (e) {
      _toast('Could not build the corrected file: $e');
    }
  }

  // -------------------------------------------------------------------
  // Step 2
  // -------------------------------------------------------------------

  Future<void> _step2Template() async {
    setState(() => _busy2 = true);
    try {
      final bytes = await _svc.buildOnboardingTemplate(businessId: widget.businessId, language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-Onboarding-Details-Template.xlsx');
    } catch (e) {
      _toast('Could not build the template: $e');
    } finally {
      if (mounted) setState(() => _busy2 = false);
    }
  }

  Future<void> _step2Pick() async {
    final group = XTypeGroup(label: ref.t('spreadsheet'), extensions: const ['xlsx']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;

    setState(() {
      _busy2 = true;
      _step2FormatError = null;
      _step2Parse = null;
      _investorOutcome = null;
      _customerLoanOutcome = null;
      _step2FileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      final parse = BulkOnboardingService.parseOnboardingBytes(bytes, file.name);
      if (!mounted) return;
      setState(() => _step2Parse = parse);
    } on ImportFormatException catch (e) {
      if (mounted) setState(() => _step2FormatError = e.message);
    } catch (e) {
      if (mounted) setState(() => _step2FormatError = 'Could not read this file: $e');
    } finally {
      if (mounted) setState(() => _busy2 = false);
    }
  }

  Future<void> _step2Submit() async {
    final parse = _step2Parse;
    if (parse == null) return;
    setState(() => _busy2 = true);
    final result = await NetworkErrorHandler.run(context, () async {
      final investors = parse.investor.rows.isEmpty
          ? const ImportOutcome(imported: 0, errors: [])
          : await _svc.submitInvestments(businessId: widget.businessId, rows: parse.investor.rows);
      final customers = parse.customer.rows.isEmpty
          ? const ImportOutcome(imported: 0, errors: [])
          : await _svc.submitCustomerLoans(businessId: widget.businessId, rows: parse.customer.rows);
      return (investors, customers);
    });
    if (!mounted) return;
    setState(() {
      _busy2 = false;
      if (result != null) {
        _investorOutcome = result.$1;
        _customerLoanOutcome = result.$2;
        if (!result.$1.rejected && !result.$2.rejected) _step2Parse = null;
      }
    });
  }

  Future<void> _step2DownloadCorrection() async {
    final parse = _step2Parse;
    if (parse == null) return;
    try {
      final bytes = BulkOnboardingService.buildStep2CorrectionFile(
        investorRows: parse.investor.rows,
        investorErrors: _investorOutcome?.errors ?? const [],
        customerRows: parse.customer.rows,
        customerErrors: _customerLoanOutcome?.errors ?? const [],
        language: _language,
      );
      await _svc.shareBytes(bytes, 'ManaLine-Onboarding-Details-Corrections.xlsx');
    } catch (e) {
      _toast('Could not build the corrected file: $e');
    }
  }

  // -------------------------------------------------------------------
  // Step 3
  // -------------------------------------------------------------------

  Future<void> _emiTemplate() async {
    setState(() => _busy3 = true);
    try {
      final customers = await _svc.fetchCustomerRefs(widget.businessId);
      final bytes = _svc.buildEmiTemplate(customers: customers, language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-EMI-History-Template.xlsx');
    } catch (e) {
      _toast('Could not build the template: $e');
    } finally {
      if (mounted) setState(() => _busy3 = false);
    }
  }

  Future<void> _emiPick() async {
    final group = XTypeGroup(label: ref.t('spreadsheet'), extensions: const ['xlsx']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return;

    setState(() {
      _busy3 = true;
      _emiFormatError = null;
      _emiSchedule = null;
      _emiResult = null;
      _emiFileName = file.name;
    });
    try {
      final bytes = await file.readAsBytes();
      final schedule = BulkOnboardingService.parseEmiBytes(bytes, file.name);
      if (!mounted) return;
      setState(() => _emiSchedule = schedule);
    } on ImportFormatException catch (e) {
      if (mounted) setState(() => _emiFormatError = e.message);
    } catch (e) {
      if (mounted) setState(() => _emiFormatError = 'Could not read this file: $e');
    } finally {
      if (mounted) setState(() => _busy3 = false);
    }
  }

  Future<void> _emiSubmit() async {
    final schedule = _emiSchedule;
    if (schedule == null || schedule.isEmpty) return;
    setState(() {
      _busy3 = true;
      _emiProgressLabel = '';
    });
    final result = await NetworkErrorHandler.run(context, () async {
      return _svc.submitEmiSchedule(
        businessId: widget.businessId,
        schedule: schedule,
        onProgress: (mlid, done, total) {
          if (mounted) setState(() => _emiProgressLabel = '$mlid — $done/$total');
        },
      );
    });
    if (!mounted) return;
    setState(() {
      _busy3 = false;
      _emiResult = result;
      if (result != null && result.errors.isEmpty) _emiSchedule = null;
    });
  }

  Future<void> _emiDownloadCorrection() async {
    final schedule = _emiSchedule;
    final result = _emiResult;
    if (schedule == null || result == null) return;
    try {
      final bytes = BulkOnboardingService.buildEmiCorrectionFile(schedule: schedule, errors: result.errors, language: _language);
      await _svc.shareBytes(bytes, 'ManaLine-EMI-History-Corrections.xlsx');
    } catch (e) {
      _toast('Could not build the corrected file: $e');
    }
  }

  // -------------------------------------------------------------------

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
                child: switch (_step) {
                  0 => _identitiesSection(),
                  1 => _detailsSection(),
                  2 => _emiSection(),
                  _ => _finishSection(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepHeader() {
    const labels = ['1. Identities', '2. Details', '3. EMI History', 'Finish'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg, vertical: ManaSpacing.sm),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: i == _step ? ManaColors.brand : ManaColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(ManaRadius.sm),
                ),
                child: ManaText.raw(
                  labels[i],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: i == _step ? ManaColors.textOnDark : ManaColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _navBar({required VoidCallback? onNext, String nextLabel = 'next'}) {
    // Both buttons are Flexible rather than bare — "Back" + "Finish" at a
    // 2.0x text scale is wide enough to overflow a 360dp-wide Row with no
    // flexible child, the same bug class CLAUDE.md calls out (a bare
    // unflexible child beside a flexible one, here the Spacer).
    return Padding(
      padding: const EdgeInsets.only(top: ManaSpacing.lg),
      child: Row(
        children: [
          if (_step > 0)
            Flexible(
              child: OutlinedButton(
                onPressed: () => setState(() => _step -= 1),
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

  // --- Step 1 -----------------------------------------------------------

  Widget _identitiesSection() {
    final parse = _identityParse;
    final outcome = _identityOutcome;
    final undecided = _duplicates.where((d) => !_dedupeDecisions.containsKey(d.row)).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(
          'One file, every new person — Agent, Customer and Investor together. '
          'Rows that look like an existing person will be flagged for you to '
          'review before anything is saved.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        OutlinedButton.icon(
          onPressed: _busy1 ? null : _identityTemplate,
          icon: const Icon(Icons.download_outlined),
          label: ManaText.raw(ref.t('get_template')),
        ),
        const SizedBox(height: ManaSpacing.md),
        OutlinedButton.icon(
          onPressed: _busy1 ? null : _identityPick,
          icon: const Icon(Icons.folder_open_outlined),
          label: ManaText.raw(ref.t('choose_file')),
        ),
        if (_identityFileName != null) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(_identityFileName!, style: const TextStyle(fontSize: 13)),
        ],
        if (_identityFormatError != null) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(_identityFormatError!, style: TextStyle(fontSize: 13, color: ManaColors.statusBad)),
        ],
        if (_busy1) ...[
          const SizedBox(height: ManaSpacing.lg),
          const Center(child: CircularProgressIndicator()),
        ],
        if (parse != null && !_busy1) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw('${parse.rows.length} rows ready', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (_duplicates.isNotEmpty) ...[
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw('${_duplicates.length} rows need review',
                style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusWarn)),
            const SizedBox(height: ManaSpacing.sm),
            for (final d in _duplicates) _duplicateCard(d),
            if (undecided > 0) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw('$undecided row(s) still need a decision.',
                  style: TextStyle(fontSize: 13, color: ManaColors.statusBad)),
            ],
          ],
          const SizedBox(height: ManaSpacing.lg),
          ElevatedButton.icon(
            onPressed: parse.rows.isEmpty ? null : _identitySubmit,
            icon: const Icon(Icons.upload_outlined),
            label: ManaText.raw(ref.t('import_identities')),
          ),
        ],
        if (outcome != null && !_busy1)
          _outcomeBlock(outcome,
              noun: 'identities',
              onDownloadCorrection: outcome.rejected ? _identityDownloadCorrection : null),
        _navBar(onNext: () => setState(() => _step = 1)),
      ],
    );
  }

  Widget _duplicateCard(DuplicateMatch d) {
    final decision = _dedupeDecisions[d.row];
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('row_duplicate_note').replaceAll('{row}', '${d.row}').replaceAll('{reason}', d.reason == "duplicate_in_file" ? ref.t('duplicate_in_file') : ref.t('looks_like_existing_customer')),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (d.candidates.isNotEmpty)
              ManaText.raw(d.candidates.join(' · '), style: TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.xs),
            Row(
              children: [
                ChoiceChip(
                  label: ManaText.raw(ref.t('merge_skip')),
                  selected: decision == 'skip',
                  onSelected: (_) => setState(() => _dedupeDecisions[d.row] = 'skip'),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ChoiceChip(
                  label: ManaText.raw(ref.t('ignore_import')),
                  selected: decision == 'keep',
                  onSelected: (_) => setState(() => _dedupeDecisions[d.row] = 'keep'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- Step 2 -----------------------------------------------------------

  Widget _detailsSection() {
    final parse = _step2Parse;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(
          'One file, three tabs — Agent, Investor, Customer — prefilled with '
          'MLID, Name, Type and Village from what you already imported. Fill '
          'in the Investor and Customer tabs with the extra details.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        OutlinedButton.icon(
          onPressed: _busy2 ? null : _step2Template,
          icon: const Icon(Icons.download_outlined),
          label: ManaText.raw(ref.t('get_template')),
        ),
        const SizedBox(height: ManaSpacing.md),
        OutlinedButton.icon(
          onPressed: _busy2 ? null : _step2Pick,
          icon: const Icon(Icons.folder_open_outlined),
          label: ManaText.raw(ref.t('choose_file')),
        ),
        if (_step2FileName != null) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(_step2FileName!, style: const TextStyle(fontSize: 13)),
        ],
        if (_step2FormatError != null) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(_step2FormatError!, style: TextStyle(fontSize: 13, color: ManaColors.statusBad)),
        ],
        if (_busy2) ...[
          const SizedBox(height: ManaSpacing.lg),
          const Center(child: CircularProgressIndicator()),
        ],
        if (parse != null && !_busy2) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw(
            '${parse.investor.rows.length} investor rows · ${parse.customer.rows.length} customer loan rows',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ManaSpacing.sm),
          ElevatedButton.icon(
            onPressed: (parse.investor.rows.isEmpty && parse.customer.rows.isEmpty) ? null : _step2Submit,
            icon: const Icon(Icons.upload_outlined),
            label: ManaText.raw(ref.t('import_details')),
          ),
        ],
        if (_investorOutcome != null && !_busy2)
          _outcomeBlock(_investorOutcome!,
              noun: 'investments',
              onDownloadCorrection: _investorOutcome!.rejected ? _step2DownloadCorrection : null),
        if (_customerLoanOutcome != null && !_busy2)
          _outcomeBlock(_customerLoanOutcome!,
              noun: 'customer loans',
              onDownloadCorrection:
                  (_customerLoanOutcome!.rejected && !(_investorOutcome?.rejected ?? false)) ? _step2DownloadCorrection : null),
        _navBar(onNext: () => setState(() => _step = 2)),
      ],
    );
  }

  // --- Step 3 -------------------------------------------------------------

  Widget _emiSection() {
    final schedule = _emiSchedule;
    final result = _emiResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(
          'Optional. Up to 100 past instalments per customer, each its own '
          'amount and date, so the collection history is not lost when the '
          'book moves onto MANA LINE. Skip this step if you have none to add.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
        ),
        const SizedBox(height: ManaSpacing.lg),
        OutlinedButton.icon(
          onPressed: _busy3 ? null : _emiTemplate,
          icon: const Icon(Icons.download_outlined),
          label: ManaText.raw(ref.t('get_template')),
        ),
        const SizedBox(height: ManaSpacing.md),
        OutlinedButton.icon(
          onPressed: _busy3 ? null : _emiPick,
          icon: const Icon(Icons.folder_open_outlined),
          label: ManaText.raw(ref.t('choose_file')),
        ),
        if (_emiFileName != null) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(_emiFileName!, style: const TextStyle(fontSize: 13)),
        ],
        if (_emiFormatError != null) ...[
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(_emiFormatError!, style: TextStyle(fontSize: 13, color: ManaColors.statusBad)),
        ],
        if (_busy3) ...[
          const SizedBox(height: ManaSpacing.lg),
          const Center(child: CircularProgressIndicator()),
          if (_emiProgressLabel.isNotEmpty) ...[
            const SizedBox(height: ManaSpacing.sm),
            Center(child: ManaText.raw(_emiProgressLabel, style: const TextStyle(fontSize: 13))),
          ],
        ],
        if (schedule != null && !_busy3) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw(
            '${schedule.length} customers · ${schedule.fold<int>(0, (a, r) => a + r.entries.length)} instalments ready',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: ManaSpacing.sm),
          ElevatedButton.icon(
            onPressed: schedule.isEmpty ? null : _emiSubmit,
            icon: const Icon(Icons.upload_outlined),
            label: ManaText.raw(ref.t('import_emi_history')),
          ),
        ],
        if (result != null && !_busy3) ...[
          const SizedBox(height: ManaSpacing.lg),
          ManaText.raw('${result.recorded} instalments recorded.',
              style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusGood)),
          if (result.errors.isNotEmpty) ...[
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw('${result.errors.length} could not be recorded:',
                style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusBad)),
            for (final e in result.errors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: ManaText.raw(
                  '${e.mlid}${e.instalment > 0 ? " · instalment ${e.instalment}" : ""}: ${e.message}',
                  style: const TextStyle(fontSize: 13),
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
        _navBar(onNext: () => setState(() => _step = 3), nextLabel: 'finish'),
      ],
    );
  }

  // --- Finish -------------------------------------------------------------

  Widget _finishSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('what_was_done'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: ManaSpacing.md),
        _checklistRow('Identities imported', _identityOutcome?.imported),
        _checklistRow('Investments recorded', _investorOutcome?.imported),
        _checklistRow('Customer loans recorded', _customerLoanOutcome?.imported),
        _checklistRow('EMI instalments recorded', _emiResult?.recorded),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(
          'Anything not shown above yet can still be added — every step in '
          'this wizard can be re-run any time the migration is open.',
          style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
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
          ManaText.raw(done ? '$value' : '—', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                    child: ManaText.raw(ref.t('row_error_note').replaceAll('{row}', '${e.row}').replaceAll('{message}', e.message), style: const TextStyle(fontSize: 13)),
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
          : ManaText.raw('${outcome.imported} $noun imported.',
              style: TextStyle(fontWeight: FontWeight.w700, color: ManaColors.statusGood)),
    );
  }
}
