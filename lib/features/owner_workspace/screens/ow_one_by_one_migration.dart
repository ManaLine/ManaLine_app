import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/components/mana_amount.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/bulk_onboarding_service.dart';
import '../state/village_book_summary.dart';
import '../../../shared/widgets/mana_tab_heading.dart';
import 'ow_investor_entry_sheets.dart';
import 'ow_village_book.dart';
import 'ow_village_customers.dart';

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

  /// The label on this stage's "add somebody who is not on the list" button.
  ///
  /// Reuses the keys the header actions already use, so "Add Investor" reads
  /// the same word here as it does on Investor Management. A second wording
  /// for the same act is how two screens come to look like two features.
  String get addLabelKey => switch (this) {
        ManaEntryStage.investors => 'add_investor',
        ManaEntryStage.agents => 'add_an_agent',
        ManaEntryStage.customers => 'add_a_customer',
      };

  /// Where that button goes.
  ///
  /// Agents and Investors go through Universal Search with the role fixed --
  /// the same door ManaAddMemberAction uses, because somebody being entered
  /// from a paper book may already exist in another business and must be
  /// found rather than duplicated.
  ///
  /// Customers carry `migration=1`, which is what lets a customer copied out
  /// of a ledger have neither a phone nor an Aadhaar number. The flag only
  /// asks: app.register_new_customer checks the Owner and that the migration
  /// is still open before honouring it.
  String get addRoute => switch (this) {
        ManaEntryStage.investors => '/ow-search?role=investor',
        ManaEntryStage.agents => '/ow-search?role=agent',
        ManaEntryStage.customers => '/customer-new?migration=1',
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

  List<ManaMemberRef> _people = const [];
  bool _loading = true;

  /// The day the old book stops. An investment cannot sensibly be dated after
  /// the handover, and the sheet enforces that when it is known.
  DateTime? _cutoff;

  /// MLIDs entered in this sitting, so a row can say so rather than looking
  /// identical before and after. Not persistence -- reopening re-reads the
  /// server, and the server is the authority on what is already in the book.
  final Set<String> _done = <String>{};

  /// The one row currently open for entry, or null with the list closed.
  ///
  /// One at a time on purpose: two forms open at once on a 360dp screen means
  /// neither is readable, and the Owner is doing one person's entry.
  String? _openMlid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStage());
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
      // A single-person door has nothing to choose, so its one row opens
      // itself rather than asking for a tap that has only one answer.
      _openMlid = widget.onlyMlid;
    });
  }

  Future<void> _switchStage(int index) async {
    final next = ManaEntryStage.values[index];
    if (next == _stage) return;
    setState(() {
      _stage = next;
      _openMlid = null;
    });
    await _loadStage();
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.onlyMlid != null;

    // ONE customer, reached from a member row.
    //
    // Returned INSTEAD of this screen rather than nested inside it: the
    // customer form lives on its own Scaffold, and placing it in this one's
    // body would stack two app bars.
    if (single && _stage == ManaEntryStage.customers) {
      return _SingleCustomerEntry(
        businessId: widget.businessId,
        mlid: widget.onlyMlid!,
      );
    }

    final body = Scaffold(
      appBar: ManaAppBar(title: ref.t('enter_one_by_one')),
      body: SafeArea(
        child: Column(
          children: [
            // THE STAGE PICKER IS THE ARROW HEADING, NOT A SEGMENTED BUTTON.
            //
            // Three segments could not hold "Customers & Loans" -- it
            // ellipsised to "Customer..." on a real handset -- and the same
            // header already names one section at a time on OW-012. Shared
            // rather than copied, so an arrow means the same thing in both.
            //
            // Hidden for a single entry: there is one person and one stage,
            // and offering to move between three would invite somebody to
            // wander off the errand they came for.
            if (!single)
              ManaTabHeading(
                labels: [
                  for (final stage in ManaEntryStage.values)
                    ref.t(stage.labelKey),
                ],
                onChanged: _switchStage,
              ),
            // A TabBarView, so the stages can be SWIPED between and not only
            // arrowed. ManaTabHeading's own doc already claimed "swiping still
            // works" -- it does for the controller, but this body was a plain
            // conditional widget, so there was nothing to swipe. The header
            // and this share one DefaultTabController, so an arrow, a swipe
            // and a programmatic jump all move the same index.
            Expanded(
              child: single
                  ? _stageBody(_stage)
                  : TabBarView(
                      children: [
                        for (final stage in ManaEntryStage.values)
                          _stageBody(stage),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );

    // A single entry has no stages to move between, so it needs no controller.
    if (single) return body;
    return DefaultTabController(
      length: ManaEntryStage.values.length,
      initialIndex: ManaEntryStage.values.indexOf(widget.initialStage),
      child: body,
    );
  }

  /// One stage's contents.
  ///
  /// Only the stage that is actually open holds people: [_loadStage] fetches
  /// for one role at a time, so drawing the other two from `_people` would
  /// show investors under the Agents heading for as long as the load took.
  /// They show a spinner until the swipe settles and the load lands, which is
  /// the truth -- this screen has not asked the server about them yet.
  Widget _stageBody(ManaEntryStage stage) {
    if (stage == ManaEntryStage.customers) {
      return Column(
        children: [
          _addToStage(stage),
          Expanded(child: VillageBookList(businessId: widget.businessId)),
        ],
      );
    }
    if (stage != _stage || _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        _addToStage(stage),
        Expanded(child: _people.isEmpty ? _emptyStage() : _peopleList()),
      ],
    );
  }

  /// "Add Investor" / "Add an Agent" / "Add a Customer", per stage.
  ///
  /// THE GAP THIS CLOSES: this screen listed the people a bulk import had
  /// already created and offered no way to add one. An Owner who found
  /// somebody missing from their book had to leave, add them somewhere else,
  /// and come back -- and for a customer out of a paper ledger with no phone
  /// and no Aadhaar, the place they would have gone refused to create them at
  /// all. Hidden for a single-person door, which exists to finish one entry.
  Widget _addToStage(ManaEntryStage stage) {
    if (widget.onlyMlid != null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () async {
            await context.push(stage.addRoute, extra: widget.businessId);
            if (!mounted) return;
            // Somebody added on that screen is not on this list yet.
            await _loadStage();
          },
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: ManaText.raw(ref.t(stage.addLabelKey)),
        ),
      ),
    );
  }

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

  /// Everybody in this stage, in one list, with one row open at a time.
  ///
  /// This replaced a PageView of one person per page. Swiping meant an Owner
  /// could not see who was left, could not reach the fourth person without
  /// passing the second and third, and had no way to tell a stage of one from
  /// a stage of twenty except a "1 of 1" counter under it -- which is why the
  /// counter existed and why it goes with the swiping.
  Widget _peopleList() => ListView.builder(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        itemCount: _people.length,
        itemBuilder: (context, i) => _personRow(_people[i]),
      );

  Widget _personRow(ManaMemberRef who) {
    final open = _openMlid == who.mlid;
    final done = _done.contains(who.mlid);
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: ManaText.raw(who.fullName),
            subtitle: ManaText.raw(
              [
                who.mlid,
                if ((who.village ?? '').isNotEmpty) who.village!,
              ].join(' - '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ManaType.note,
            ),
            trailing: done
                ? Icon(Icons.check_circle,
                    size: 20, color: ManaColors.statusGood)
                : Icon(open ? Icons.expand_less : Icons.expand_more),
            onTap: widget.onlyMlid != null
                ? null
                : () => setState(() => _openMlid = open ? null : who.mlid),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.lg),
              child: done
                  ? ManaText.raw(ref.t('entered_in_this_sitting'),
                      style:
                          TextStyle(color: ManaColors.statusGood, fontSize: 13))
                  : switch (_stage) {
                      ManaEntryStage.investors => _investorAction(who),
                      ManaEntryStage.agents => _AgentShortEntry(
                          businessId: widget.businessId,
                          mlid: who.mlid,
                        ),
                      // The customer stage is a village book, not a list of
                      // people, so it never builds these rows.
                      ManaEntryStage.customers => const SizedBox.shrink(),
                    },
            ),
        ],
      ),
    );
  }

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

/// The agent stage: one number, or nothing at all.
///
/// Everything else about an agent's past is settled before the book comes
/// across -- that is why attendance was taken OUT of this door rather than
/// built into it. A short is the exception: money the agent owes the business
/// on the day it changes hands, and still live afterwards.
///
/// It loads its own figure rather than being handed one, because it is the
/// only thing on this page and the stage's member list carries names, not
/// money. Reloading after a write is what makes the "outstanding since" line
/// and the Mark Recovered button agree with the server instead of with what
/// was just typed.
class _AgentShortEntry extends ConsumerStatefulWidget {
  final String businessId;
  final String mlid;
  const _AgentShortEntry({required this.businessId, required this.mlid});

  @override
  ConsumerState<_AgentShortEntry> createState() => _AgentShortEntryState();
}

class _AgentShortEntryState extends ConsumerState<_AgentShortEntry> {
  final _amount = TextEditingController();
  ManaAgentShort? _short;
  bool _loading = true;
  bool _saving = false;

  /// Whether the read actually reached the server.
  ///
  /// NetworkErrorHandler.run returns null on failure, and so does a lookup
  /// that found nobody. Collapsing the two would tell an Owner with no signal
  /// that this person is not an agent -- a statement about their book, made
  /// from a statement about their phone.
  bool _reachedServer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await NetworkErrorHandler.run(context, () async {
      return ref.read(bulkOnboardingServiceProvider).agentOpeningShort(
            businessId: widget.businessId,
            mlid: widget.mlid,
          );
    });
    if (!mounted) return;
    setState(() {
      _short = s;
      _reachedServer = s != null;
      _loading = false;
      // Prefill only while it is still owed. Showing a recovered figure in an
      // editable box invites somebody to save it again and reopen a debt that
      // was settled -- declare() deliberately clears cleared_on.
      if (s != null && s.isOutstanding) _amount.text = '${s.amount}';
    });
  }

  Future<void> _save() async {
    final agentId = _short?.agentId;
    if (agentId == null) return;
    final typed = int.tryParse(_amount.text.trim());
    // An empty box is not zero. Zero is a deliberate "nothing owed"; an empty
    // box is somebody who has not answered yet.
    //
    // It must SAY so. Returning quietly made the button look broken -- the
    // Owner presses Save, nothing moves, and there is no way to tell that from
    // a failed write. This is the same silent no-op that had two Karri
    // Priyanka rows created two minutes apart.
    if (typed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: ManaText.raw(ref.t('enter_amount_owed'))),
      );
      return;
    }
    setState(() => _saving = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(bulkOnboardingServiceProvider)
          .declareAgentOpeningShort(agentId: agentId, amount: typed);
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == null) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ManaText.raw(typed == 0
          ? ref.t('no_short_to_record')
          : ref.t('short_recorded').replaceFirst('{amount}', manaRupees(typed))),
    ));
  }

  Future<void> _markRecovered() async {
    final agentId = _short?.agentId;
    if (agentId == null) return;
    setState(() => _saving = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref
          .read(bulkOnboardingServiceProvider)
          .clearAgentOpeningShort(agentId: agentId);
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == null) return;
    _amount.clear();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(ref.t('short_marked_recovered'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(ManaSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final s = _short;
    if (s == null) {
      if (!_reachedServer) {
        // The handler has already said what went wrong. Offering the read
        // again is the only useful thing left on screen.
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: ManaText.raw(ref.t('retry')),
          ),
        );
      }
      // A member listed under Agent with no agents row. Says so rather than
      // drawing a box that cannot save.
      return ManaText.raw(ref.t('person_not_in_this_stage'),
          style: ManaType.note);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ManaText.raw(ref.t('agent_opening_short'), style: ManaType.strong),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(ref.t('agent_opening_short_note'), style: ManaType.fine),
        const SizedBox(height: ManaSpacing.md),
        if (s.isOutstanding && s.declaredOn != null) ...[
          ManaText.raw(
            ref
                .t('short_outstanding_since')
                .replaceFirst('{date}', manaDisplayDate(s.declaredOn!)),
            style: TextStyle(color: ManaColors.statusWarn, fontSize: 13),
          ),
          const SizedBox(height: ManaSpacing.sm),
        ] else if (s.clearedOn != null) ...[
          ManaText.raw(
            ref
                .t('short_recovered_on')
                .replaceFirst('{date}', manaDisplayDate(s.clearedOn!)),
            style: TextStyle(color: ManaColors.statusGood, fontSize: 13),
          ),
          const SizedBox(height: ManaSpacing.sm),
        ],
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: ref.t('amount_owed'),
            prefixText: '₹ ',
          ),
        ),
        const SizedBox(height: ManaSpacing.md),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: ManaText.raw(ref.t('save_short')),
              ),
            ),
            if (s.isOutstanding) ...[
              const SizedBox(width: ManaSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _markRecovered,
                  child: ManaText.raw(ref.t('mark_short_recovered')),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// The loan form for exactly one customer, found by MLID.
///
/// Reads the same positions the village book reads and keeps the one row that
/// matches, rather than adding a second server call that takes an MLID: the
/// RPC already returns every customer with their village and their live loan,
/// and a book being migrated is hundreds of rows, not hundreds of thousands.
class _SingleCustomerEntry extends ConsumerStatefulWidget {
  final String businessId;
  final String mlid;
  const _SingleCustomerEntry({required this.businessId, required this.mlid});

  @override
  ConsumerState<_SingleCustomerEntry> createState() =>
      _SingleCustomerEntryState();
}

class _SingleCustomerEntryState extends ConsumerState<_SingleCustomerEntry> {
  List<ManaLoanPosition>? _mine;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final rows = await NetworkErrorHandler.run(context, () async {
      return ref
          .read(bulkOnboardingServiceProvider)
          .customerPositions(widget.businessId);
    });
    if (!mounted) return;
    setState(() {
      _mine = rows?.where((r) => r.mlid == widget.mlid).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: ManaAppBar(title: ref.t('enter_one_by_one')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final mine = _mine;
    if (mine == null || mine.isEmpty) {
      // Not a customer of this book, or the book has no row for them. Says so
      // rather than drawing a form that would have nowhere to save.
      return Scaffold(
        appBar: ManaAppBar(title: ref.t('enter_one_by_one')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.xl),
            child: ManaText.raw(ref.t('person_not_in_this_stage'),
                textAlign: TextAlign.center, style: ManaType.note),
          ),
        ),
      );
    }
    return VillageCustomersScreen(
      businessId: widget.businessId,
      title: mine.first.fullName,
      positions: mine,
    );
  }
}
