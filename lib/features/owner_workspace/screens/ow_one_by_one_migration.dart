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

/// Above this many people in a stage, one-by-one is the wrong tool and the
/// screen says so rather than letting somebody start the walk.
///
/// Not a hard block: the Owner knows their book and may have a reason. But 200
/// customers is 200 screens, each replaying its instalments one
/// record_collection at a time, and finding that out on screen 40 is worse
/// than being told on screen 0.
const int kManaOneByOneComfortable = 25;

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
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_people.isEmpty)
              Expanded(child: _emptyStage())
            else ...[
              if (!single) _tooManyNotice(),
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

  /// Said on screen 0, not discovered on screen 40.
  Widget _tooManyNotice() {
    if (_people.length <= kManaOneByOneComfortable) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(ManaSpacing.md),
        decoration: BoxDecoration(
          color: ManaColors.statusWarnFaint,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ManaText.raw(
          ref
              .t('many_people_use_the_wizard_note')
              .replaceAll('{count}', '${_people.length}'),
          style: ManaType.note,
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

  /// One person, one page. The stage bodies arrive in Tasks 2, 3 and 4; until
  /// then this is the identity header they all share.
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
        ],
      );
}
