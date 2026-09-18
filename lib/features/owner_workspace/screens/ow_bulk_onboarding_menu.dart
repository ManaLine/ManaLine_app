import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_form_grid.dart';
import '../../../design/components/mana_logo_backdrop.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/translation_service.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/bulk_onboarding_pages.dart';
import '../state/bulk_onboarding_service.dart';

/// The website's front page for moving a paper book onto MANA LINE.
///
/// WHY THIS EXISTS AT ALL. The handset stopped offering the wizard on
/// 2026-09-18 — the Owner's judgement was that seven pages of spreadsheet
/// grids on a phone is "difficult and messy and may go wrong" — and the
/// signpost it shows instead promises a website with "a menu showing bulk
/// onboarding, allowing customers to download fill upload their sheets".
/// Dropping somebody straight into page 1 of the wizard would not be that
/// menu: page 1 is a chooser that asks what their book contains, which
/// answers a different question from "what do I do here".
///
/// THE SPLIT IS THE IDEA. Getting the sheets and bringing them back are two
/// different jobs on two different days:
///
///   * DOWNLOADING is bulk and orderless. An Owner at a laptop wants every
///     sheet their book needs in one sitting, then goes away and fills them
///     in over a week. Nothing is written, so nothing can go wrong in the
///     wrong order — which is why every template lives here, on one screen.
///   * UPLOADING is sequential and stateful. A customer's address has to
///     point at a village that exists; a loan has to point at a person.
///     That work stays in the wizard, which already has the parse, the
///     duplicate review and the commit for each step.
///
/// So this screen downloads, and hands over for the upload. It deliberately
/// does NOT reimplement a single import — see the note on [_open].
///
/// NUMBERED, and the numbers mean something. This app does not number lists
/// for decoration. Here the order is the content: importing customers before
/// identities fails, and the one time the sequence was unclear this business
/// ended up with its whole book twice (22 Aug 2026, the reason
/// `app.migration_progress` was written).
class BulkOnboardingMenuScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BulkOnboardingMenuScreen({super.key, required this.businessId});

  @override
  ConsumerState<BulkOnboardingMenuScreen> createState() => _BulkOnboardingMenuScreenState();
}

/// One downloadable sheet: what it is called, and how to build its bytes.
///
/// The builders are the SAME ones the wizard's own "Get Template" buttons
/// call. A template built two ways is a template that disagrees with itself
/// the first time a column is added.
class _Sheet {
  final String titleKey;
  final String fileName;
  final Future<Uint8List> Function() build;
  const _Sheet(this.titleKey, this.fileName, this.build);
}

class _BulkOnboardingMenuScreenState extends ConsumerState<BulkOnboardingMenuScreen> {
  MigrationPlan? _plan;
  MigrationProgress? _progress;
  bool _loading = true;

  /// Which sheet is being built, by file name. Only one button spins, rather
  /// than the whole screen going busy: building a customer grid reads the
  /// business and can take a moment, and an Owner should still be able to
  /// grab the identity sheet while it does.
  String? _busySheet;

  BulkOnboardingService get _svc => ref.read(bulkOnboardingServiceProvider);

  /// The same source the wizard's own template buttons read, so a sheet
  /// downloaded here and one downloaded there carry identical column
  /// headings — a template that disagrees with its own importer is
  /// unreadable in a way nobody can see.
  String get _language => ref.read(authFlowProvider).language.enumValue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    MigrationPlan? plan;
    MigrationProgress? progress;
    try {
      plan = await _svc.migrationPlan(widget.businessId);
    } catch (_) {
      // Left null: the screen then shows the "start with your book" card,
      // which is where an Owner who has not said what their book contains
      // ought to be anyway.
    }
    try {
      progress = await _svc.migrationProgress(widget.businessId);
    } catch (_) {
      // The counts simply do not appear. Never a zero — claiming a book is
      // empty because a call failed is the one thing this line must not do.
    }
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _progress = progress;
      _loading = false;
    });
  }

  /// Hand over to the wizard at [page].
  ///
  /// THROUGH THE SERVER POINTER, not a constructor argument. The wizard
  /// already restores its step from `app.migration_wizard_step` on open —
  /// that is how resuming on another device works — so writing the pointer
  /// and pushing the route reuses the mechanism instead of adding a second
  /// one beside it. It also means a person who lands on the wizard directly,
  /// from a bookmark, resumes exactly where the menu would have sent them.
  Future<void> _open(ManaBulkPage page) async {
    final step = manaBulkPagesFor(_plan).indexOf(page);
    if (step > 0) {
      try {
        await _svc.saveWizardStep(widget.businessId, step);
      } catch (_) {
        // The wizard falls back to what the device remembers, and its own
        // Next/Back still work. Refusing to open the page over a failed
        // bookmark write would be the worse outcome.
      }
    }
    if (!mounted) return;
    context.push('/ow-bulk-onboarding', extra: widget.businessId);
  }

  Future<void> _download(_Sheet sheet) async {
    setState(() => _busySheet = sheet.fileName);
    try {
      final bytes = await sheet.build();
      await _svc.shareBytes(bytes, sheet.fileName);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: ManaText.raw(ref.t('bulk_menu_sheet_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busySheet = null);
    }
  }

  /// The sheets this book actually needs.
  ///
  /// Driven by the saved plan, so an Owner with no investors is never offered
  /// an investor sheet — the same rule the wizard uses to decide which pages
  /// to show, from the same [manaBulkPagesFor] list.
  List<_Sheet> _sheets(String language) {
    final plan = _plan;
    if (plan == null) return const [];
    final id = widget.businessId;
    return [
      _Sheet('bulk_step_identities', 'ManaLine-Identity-Import-Template.xlsx',
          () async => BulkOnboardingService.buildIdentityTemplate(language: language)),
      if (plan.investors) ...[
        _Sheet('investors', 'ManaLine-Investors-Template.xlsx',
            () => _svc.buildInvestorTemplate(businessId: id, language: language)),
        _Sheet('withdrawals', 'ManaLine-Withdrawals-Template.xlsx',
            () => _svc.buildWithdrawalTemplate(businessId: id, language: language)),
      ],
      if (plan.shareholders)
        _Sheet('bulk_sheet_shares', 'ManaLine-Profit-Shares-Template.xlsx',
            () async => _svc.buildShareholderTemplate(language: language)),
      if (plan.customers)
        _Sheet('customers', 'ManaLine-Customers-Template.xlsx',
            () => _svc.buildCustomerGridTemplate(businessId: id, language: language)),
      if (plan.attendance)
        _Sheet('bulk_sheet_attendance', 'ManaLine-Agent-Attendance-Template.xlsx',
            () => _svc.buildAttendanceTemplate(businessId: id, language: language)),
      if (plan.weekly)
        _Sheet('bulk_step_weekly', 'ManaLine-Weekly-Account-Template.xlsx',
            () async => _svc.buildWeeklyTemplate(language: language)),
    ];
  }

  /// What is already in the book for [page], in the Owner's own words.
  ///
  /// Counted from live rows by `app.migration_progress`, never remembered —
  /// a stored "step 4 done" flag goes stale the moment anything is deleted
  /// outside the wizard.
  String? _alreadyIn(ManaBulkPage page) {
    final p = _progress;
    if (p == null) return null;
    String? n(int count, String one, String many) =>
        count == 0 ? null : '$count ${count == 1 ? one : many}';
    return switch (page) {
      ManaBulkPage.identities =>
        n(p.count('customers') + p.count('investors') + p.count('agents'), 'person', 'people'),
      ManaBulkPage.investors => n(p.count('investments'), 'investment', 'investments'),
      ManaBulkPage.customers => n(p.count('loans'), 'loan', 'loans'),
      ManaBulkPage.agents => n(p.count('attendance_days'), 'working day', 'working days'),
      ManaBulkPage.snapshot => p.date('snapshot_cutoff'),
      ManaBulkPage.weekly => n(p.count('weeks'), 'week', 'weeks'),
      ManaBulkPage.plan || ManaBulkPage.finish => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(translationLoaderProvider);
    final plan = _plan;

    return Scaffold(
      appBar: ManaAppBar(
        title: ref.t('bulk_onboarding'),
        homeRoute: '/web-home',
      ),
      // Same faint mark as the web home and the login screens -- one website,
      // one backdrop. See the note there on why it lives inside the body.
      body: ManaLogoBackdrop(
        // BOTTOM-RIGHT, not centred. This page is a grid of opaque cards
        // anchored top-left; a centred mark is sliced by their edges and
        // sits behind the words. Down here it is in the empty quarter of
        // the page, whole, and never behind anything that has to be read.
        alignment: Alignment.bottomRight,
        extent: 0.55,
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    // A form read across a 2560px monitor is a form nobody
                    // finishes. Everything else in this app is 360dp wide and
                    // needs no ceiling; this screen is the first that does.
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: ListView(
                      padding: const EdgeInsets.all(ManaSpacing.xl),
                      children: [
                        ManaText.raw(ref.t('bulk_menu_lead'), style: ManaType.secondary),
                        const SizedBox(height: ManaSpacing.lg),
                        if (plan == null)
                          _StartCard(onTap: () => _open(ManaBulkPage.plan))
                        else ...[
                          _CutoffBar(
                            plan: plan,
                            onChange: () => _open(ManaBulkPage.plan),
                          ),
                          const SizedBox(height: ManaSpacing.xl),
                          _Heading(
                            title: ref.t('bulk_menu_sheets'),
                            note: ref.t('bulk_menu_sheets_note'),
                          ),
                          const SizedBox(height: ManaSpacing.md),
                          ManaFormGrid(
                            columnsAtMedium: 2,
                            columnsAtExpanded: 3,
                            children: [
                              for (final sheet in _sheets(_language))
                                _SheetCard(
                                  title: ref.t(sheet.titleKey),
                                  action: ref.t('get_template'),
                                  busy: _busySheet == sheet.fileName,
                                  // Every other button stays live while one
                                  // sheet builds — see [_busySheet].
                                  onTap: _busySheet == null ? () => _download(sheet) : null,
                                ),
                            ],
                          ),
                          const SizedBox(height: ManaSpacing.xxl),
                          _Heading(
                            title: ref.t('bulk_menu_steps'),
                            note: ref.t('bulk_menu_steps_note'),
                          ),
                          const SizedBox(height: ManaSpacing.md),
                          for (final entry in manaBulkPagesFor(plan)
                              .asMap()
                              .entries
                              // The chooser is not a step to bring a sheet
                              // back to; it is the bar above.
                              .where((e) => e.value != ManaBulkPage.plan))
                            _StepRow(
                              number: entry.key,
                              title: ref.t(entry.value.titleKey),
                              alreadyIn: _alreadyIn(entry.value),
                              // NOT ref.t('open'): that key's Telugu is
                              // "తెరిచి ఉంది" -- "IS open", a loan's status --
                              // so it would have labelled this button "Is Open"
                              // for every Telugu reader while looking perfect
                              // in English. See migration 20260918120120.
                              action: ref.t('bulk_menu_open_step'),
                              onTap: () => _open(entry.value),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// The section rule — a heading with its one line of explanation.
class _Heading extends StatelessWidget {
  final String title;
  final String note;
  const _Heading({required this.title, required this.note});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(title, style: ManaType.sheetTitle),
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(note, style: ManaType.note),
          const SizedBox(height: ManaSpacing.sm),
          Divider(color: ManaColors.divider, height: 1),
        ],
      );
}

/// Shown when no plan is saved: there is exactly one thing to do, so there is
/// exactly one card.
class _StartCard extends ConsumerWidget {
  final VoidCallback onTap;
  const _StartCard({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
        color: ManaColors.brandFaint,
        borderRadius: BorderRadius.circular(ManaRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(ManaRadius.md),
          child: Container(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ManaRadius.md),
              border: Border.all(color: ManaColors.brand),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(ref.t('bulk_menu_start_title'), style: ManaType.cardTitle),
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(ref.t('bulk_menu_start_body'), style: ManaType.secondary),
              ],
            ),
          ),
        ),
      );
}

/// The cut-off date, and the way back to the chooser that set it.
///
/// It leads because everything below is stated as at that day — a menu that
/// showed the sheets without it would let somebody fill in a week of figures
/// against a date they had forgotten choosing.
class _CutoffBar extends ConsumerWidget {
  final MigrationPlan plan;
  final VoidCallback onChange;
  const _CutoffBar({required this.plan, required this.onChange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cutoff = plan.cutoff;
    return Container(
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.surfaceMuted,
        borderRadius: BorderRadius.circular(ManaRadius.sm),
      ),
      // Wrap, not Row: a Telugu label, a date and a button do not share a
      // narrow line, and a bare child beside a flexible one is the overflow
      // this project has shipped four times.
      child: Wrap(
        spacing: ManaSpacing.md,
        runSpacing: ManaSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ManaText.raw(ref.t('bulk_menu_cutoff'), style: ManaType.note),
          ManaText.raw(
            cutoff == null
                ? ref.t('bulk_menu_no_cutoff')
                : '${cutoff.day.toString().padLeft(2, '0')}/'
                    '${cutoff.month.toString().padLeft(2, '0')}/${cutoff.year}',
            style: ManaType.strong,
          ),
          TextButton(
            onPressed: onChange,
            child: ManaText.raw(ref.t('bulk_menu_change_plan')),
          ),
        ],
      ),
    );
  }
}

/// One sheet to download.
class _SheetCard extends StatelessWidget {
  final String title;
  final String action;
  final bool busy;
  final VoidCallback? onTap;
  const _SheetCard({
    required this.title,
    required this.action,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(ManaSpacing.md),
        decoration: BoxDecoration(
          color: ManaColors.surface,
          borderRadius: BorderRadius.circular(ManaRadius.md),
          border: Border.all(color: ManaColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ManaText.raw(title, style: ManaType.strong),
            const SizedBox(height: ManaSpacing.sm),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: ManaSpacing.sm),
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: ManaText.raw(action),
              ),
          ],
        ),
      );
}

/// One step of the journey, numbered.
class _StepRow extends StatelessWidget {
  final int number;
  final String title;
  final String? alreadyIn;
  final String action;
  final VoidCallback onTap;
  const _StepRow({
    required this.number,
    required this.title,
    required this.alreadyIn,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xs),
        child: Wrap(
          spacing: ManaSpacing.md,
          runSpacing: ManaSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // The number is the spine of this list and the reason it is a
            // list at all: these have to happen in this order.
            Container(
              height: 28,
              width: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ManaColors.brandFaint,
                shape: BoxShape.circle,
              ),
              child: ManaText.raw('$number', style: ManaType.smallStrong),
            ),
            ManaText.raw(title, style: ManaType.strong),
            if (alreadyIn != null) ManaText.raw(alreadyIn!, style: ManaType.note),
            TextButton(onPressed: onTap, child: ManaText.raw(action)),
          ],
        ),
      );
}
