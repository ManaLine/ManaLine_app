import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/bulk_onboarding_service.dart';
import 'ow_investor_entry_sheets.dart';
import 'ow_village_book.dart';

/// Entering a pre-existing book ONE PERSON AT A TIME, beside the bulk wizard.
///
/// The wizard is seven pages of grids and a spreadsheet. That is right for two
/// hundred customers and wrong for three investors -- and wrong for the one
/// person the wizard missed, because finishing that entry means walking all
/// seven pages again.
///
/// THE TWO DOORS ARE CHOSEN PER STAGE, NOT PER BUSINESS. A real book brought to
/// this design had 200 customers, 2 agents and 3 investors. The wizard is the
/// only sane way to do the customers; building a spreadsheet for five other
/// people is not. So this screen opens on any stage and does not assume the
/// Owner wants all three.
///
/// EVERY WRITE GOES THROUGH BulkOnboardingService, one row at a time, using the
/// same calls the wizard's grids use. That is the whole design: the money
/// rules, the rejection parsing and the idempotency key are inherited rather
/// than rebuilt, so this door cannot disagree with the wizard about what an
/// investment or a loan is. Nothing here talks to Supabase directly.
enum ManaEntryStage {
  investors,
  agents,
  customers;

  /// The `business_members.role` this stage lists.
  ///
  /// Read out of business_member_role_enum -- ('Owner','Agent','Investor',
  /// 'Customer') -- rather than guessed, because membersInRole passes it
  /// straight to a query and a wrong literal returns an empty list in silence
  /// rather than an error.
  String get role => switch (this) {
        ManaEntryStage.investors => 'Investor',
        ManaEntryStage.agents => 'Agent',
        ManaEntryStage.customers => 'Customer',
      };

  String get labelKey => switch (this) {
        ManaEntryStage.investors => 'entry_stage_investors',
        ManaEntryStage.agents => 'entry_stage_agents',
        ManaEntryStage.customers => 'entry_stage_customers',
      };
}

// THE "USE THE WIZARD INSTEAD" NOTICE IS GONE, and deleting it rather than
// rewording it is the point.
//
// It told an Owner with 200 customers that the Bulk Onboarding Wizard would be
// faster. The Owner then said what I had not known: their users mostly have no
// laptop, so the wizard's spreadsheet is a door that does not open for them. A
// notice recommending the impossible is worse than no notice -- it reads as
// "you are doing this the wrong way" while offering nothing to do instead.
//
// The village grouping below is the real answer to the same problem. 200
// customers is not a 200-screen wall; it is a dozen villages of about
// seventeen, one sitting each.

/// Submits ONE investor through the bulk path.
///
/// A list of one, deliberately. app.bulk_import_investments is where the
/// investor money rules live -- ROI as rupees per hundred per month, the
/// interest type, the profit share -- and calling it with a single row means
/// this door cannot drift from what the wizard's grid means by an investment.
/// A second code path for "just one person" is how two answers to the same
/// question get shipped.
Future<ImportOutcome> saveInvestorRow({
  required BulkOnboardingService service,
  required String businessId,
  required Map<String, dynamic> row,
}) =>
    service.submitInvestments(businessId: businessId, rows: [row]);

// ATTENDANCE IS NOT PART OF MIGRATING A BOOK, and the range expansion that
// used to sit here is gone with it.
//
// I built it on the reasoning that attendance is one row per agent per day,
// the wizard collects it as a spreadsheet, and an Owner with no laptop could
// therefore never enter it. That reasoning was sound and the premise was
// wrong: the Owner does not WANT it entered. By the time a book is handed to
// the app the agents' salaries and sadar are already settled, and those
// settlements were the Owner's own entries in the old book. Replaying months
// of attendance would be importing history nobody will ever read to recompute
// a figure that is already paid.
//
// What DOES have to come across is an agent still holding a short at the
// handover -- money the agent owes the business on the day the book changes
// hands. That is an opening position, not a history, and it is the one agent
// figure that is still live.

/// Whether an entry actually went wrong.
///
/// SKIPPED IS NOT A FAILURE. Re-entering somebody is the normal way to finish
/// a partly-done import -- the server saw the row was already in the book and
/// left it alone. Reading that as an error would send an Owner looking for a
/// bug that is the book already being correct, and would make the obvious
/// recovery (go through them again) look broken.
bool manaEntryFailed(ImportOutcome outcome) => outcome.errors.isNotEmpty;

class OneByOneMigrationScreen extends ConsumerStatefulWidget {
  final String businessId;

  /// Which stage to open on. Investors first by default -- the Owner's order,
  /// and the order the book itself is organised in.
  final ManaEntryStage initialStage;

  /// Set to enter ONE person and no others: the missed-entry door, opened from
  /// a member row. No slider is drawn, because there is nothing to slide
  /// between.
  final String? onlyMlid;

  const OneByOneMigrationScreen({
    super.key,
    required this.businessId,
    this.initialStage = ManaEntryStage.investors,
    this.onlyMlid,
  });

  @override
  ConsumerState<OneByOneMigrationScreen> createState() =>
      _OneByOneMigrationScreenState();
}

class _OneByOneMigrationScreenState
    extends ConsumerState<OneByOneMigrationScreen> {
  late ManaEntryStage _stage = widget.initialStage;
  late final PageController _pages = PageController();

  List<ManaMemberRef> _people = const [];
  bool _loading = true;
  int _index = 0;

  /// The day the old book stops. An investment cannot sensibly be dated after
  /// the handover, and the sheet enforces that when it is known.
  DateTime? _cutoff;

  /// MLIDs entered in this sitting, so a page can say so rather than looking
  /// identical before and after. Not persistence -- reopening re-reads the
  /// server, and the server is the authority on what is already in the book.
  final Set<String> _done = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStage());
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _loadStage() async {
    setState(() => _loading = true);
    // Read before the members, and NOT through NetworkErrorHandler: a missing
    // cut-off is not worth a SnackBar. The sheet treats null as "no handover
    // date known" and simply does not bound the date, which is the behaviour
    // the wizard has when no plan has been saved either.
    try {
      final plan = await ref
          .read(bulkOnboardingServiceProvider)
          .migrationPlan(widget.businessId);
      _cutoff = plan?.cutoff;
    } catch (_) {
      _cutoff = null;
    }
    if (!mounted) return;
    final people = await NetworkErrorHandler.run(context, () async {
      return ref.read(bulkOnboardingServiceProvider).membersInRole(
            businessId: widget.businessId,
            role: _stage.role,
          );
    });
    if (!mounted) return;
    setState(() {
      // Null is a network failure, already surfaced by the handler. An empty
      // list is a real answer -- this stage has nobody in it yet -- and the
      // two must not render the same.
      _people = people == null
          ? const []
          : widget.onlyMlid == null
              ? people
              : people.where((p) => p.mlid == widget.onlyMlid).toList();
      _loading = false;
      _index = 0;
    });
    if (_pages.hasClients) _pages.jumpToPage(0);
  }

  Future<void> _switchStage(ManaEntryStage next) async {
    if (next == _stage) return;
    setState(() => _stage = next);
    await _loadStage();
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.onlyMlid != null;

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('enter_one_by_one')),
      body: SafeArea(
        child: Column(
          children: [
            // Hidden for a single entry: there is one person and one stage,
            // and offering to move between three would invite somebody to
            // wander off the errand they came for.
            if (!single) _stagePicker(),
            if (_stage == ManaEntryStage.customers && widget.onlyMlid == null)
              Expanded(
                child: VillageBookList(businessId: widget.businessId),
              )
            else if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_people.isEmpty)
              Expanded(child: _emptyStage())
            else ...[
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: _people.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _personPage(_people[i]),
                ),
              ),
              if (!single) _position(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stagePicker() => Padding(
        padding: const EdgeInsets.fromLTRB(
            ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, ManaSpacing.sm),
        child: SegmentedButton<ManaEntryStage>(
          segments: [
            for (final stage in ManaEntryStage.values)
              ButtonSegment(
                value: stage,
                label: ManaText.raw(ref.t(stage.labelKey),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          selected: {_stage},
          showSelectedIcon: false,
          onSelectionChanged: (v) => _switchStage(v.first),
        ),
      );

  Widget _emptyStage() => Padding(
        padding: const EdgeInsets.all(ManaSpacing.xxl),
        child: Center(
          child: ManaText.raw(
            widget.onlyMlid != null
                ? ref.t('person_not_in_this_stage')
                : ref.t('nobody_in_this_stage_yet'),
            textAlign: TextAlign.center,
            style: ManaType.secondary,
          ),
        ),
      );

  Widget _position() => Padding(
        padding: const EdgeInsets.only(bottom: ManaSpacing.md),
        child: ManaText.raw(
          ref
              .t('person_of_total')
              .replaceAll('{n}', '${_index + 1}')
              .replaceAll('{total}', '${_people.length}'),
          style: ManaType.note,
        ),
      );

  /// One person, one page: who they are, then what this stage asks of them.
  Widget _personPage(ManaMemberRef who) => ListView(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        children: [
          ManaText.raw(who.fullName, style: ManaType.sheetTitle),
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(
            [
              who.mlid,
              if ((who.village ?? '').isNotEmpty) who.village!,
            ].join(' · '),
            style: ManaType.note,
          ),
          const SizedBox(height: ManaSpacing.lg),
          if (_done.contains(who.mlid))
            ManaText.raw(ref.t('entered_in_this_sitting'),
                style: TextStyle(color: ManaColors.statusGood, fontSize: 13))
          else
            switch (_stage) {
              ManaEntryStage.investors => _investorAction(who),
              // Tasks 3 and 4.
              ManaEntryStage.agents => const SizedBox.shrink(),
              // The customer stage is not a list of people at all -- see
              // _customerStage, which groups the book by village. This branch
              // is unreachable, because that stage never builds person pages.
              ManaEntryStage.customers => const SizedBox.shrink(),
            },
        ],
      );

  /// The investor stage, which is mostly a host for a sheet that already
  /// exists. InvestmentSheet collects amount, ROI, interest type, date and
  /// profit share for one person and pops exactly the row map
  /// submitInvestments takes -- writing a second investor form would be
  /// building a disagreement.
  Widget _investorAction(ManaMemberRef who) => FilledButton.icon(
        onPressed: () => _enterInvestment(who),
        icon: const Icon(Icons.add, size: 18),
        label: ManaText.raw(ref.t('add_this_persons_entry')),
      );

  Future<void> _enterInvestment(ManaMemberRef who) async {
    final row = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => InvestmentSheet(who: who, cutoff: _cutoff),
    );
    if (row == null || !mounted) return;

    final outcome = await NetworkErrorHandler.run(context, () async {
      return saveInvestorRow(
        service: ref.read(bulkOnboardingServiceProvider),
        businessId: widget.businessId,
        row: row,
      );
    });
    if (outcome == null || !mounted) return;

    if (manaEntryFailed(outcome)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: ManaText.raw(outcome.errors.first.message),
      ));
      return;
    }
    // skipped counts as done: the server found it already in the book, which
    // is the normal result of going through somebody twice.
    setState(() => _done.add(who.mlid));
  }
}
