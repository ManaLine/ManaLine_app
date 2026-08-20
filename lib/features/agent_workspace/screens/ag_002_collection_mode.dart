import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_collection_search_field.dart';
import '../../../design/components/mana_frequency_picker.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/translation_service.dart';
import '../../owner_workspace/state/collection_mode_state.dart';
import '../../owner_workspace/screens/ow_006_collection_mode.dart' show CollectionEntryScreen;


/// AG-002 — Collection Mode (Agent Workspace). Per spec's own PURPOSE/API
/// BINDING: this is the Agent-side entry point into the same Collection
/// workflow already fully locked at OW-006 — same `collectionModeProvider`,
/// same `CollectionEntryScreen` (Full/Partial/Excess/No-Collection, mixed
/// payment, validations). This file adds only the Agent-specific dashboard/
/// list framing (Customers Due/Collected/Pending/Skipped, Penalty, Grace,
/// Today's Collection Total) around that shared workflow — it does not
/// redefine or duplicate the collection mechanics.
class AgentCollectionModeScreen extends ConsumerStatefulWidget {
  final String businessId;
  const AgentCollectionModeScreen({super.key, required this.businessId});

  @override
  ConsumerState<AgentCollectionModeScreen> createState() => _AgentCollectionModeScreenState();
}

class _AgentCollectionModeScreenState extends ConsumerState<AgentCollectionModeScreen> {
  /// Local, not in the notifier — see OW-006 for why.
  String _query = '';
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(collectionModeProvider.notifier).load(widget.businessId);
    });
  }


  /// Daily / Weekly / Monthly, or null for the whole round. Kept in the screen
  /// rather than the notifier because it is a view preference, not state the
  /// collection itself depends on — reloading the round must not silently
  /// re-narrow it.
  String? _frequency;

  Widget _frequencyPicker() => ManaFrequencyPicker(
        value: _frequency,
        onChanged: (f) => setState(() => _frequency = f),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectionModeProvider);
    final visible = manaFilterDueRows(state.sorted, _query, frequency: _frequency);

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('collection_mode')),
        actions: [
          IconButton(
            icon: Icon(_searchOpen ? Icons.search_off : Icons.search),
            tooltip: ref.t('search'),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) _query = '';
            }),
          ),
        ],
        bottom: _searchOpen
            ? ManaCollectionSearchField(
                onChanged: (v) => setState(() => _query = v),
              )
            : null,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(collectionModeProvider.notifier).load(widget.businessId),
          child: state.loading && state.dueList.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    _frequencyPicker(),
                    // manaNowIst(), not DateTime.now(): this labels which
                    // business day's round the Agent is standing in, and a
                    // handset an hour either side of midnight in the wrong
                    // zone would name the wrong one.
                    ManaText.raw(DateFormat('d MMM yyyy').format(manaNowIst()),
                        style: ManaType.note),
                    const SizedBox(height: ManaSpacing.sm),
                    ManaText.raw(
                      ref.t('sorted_by_note_short'),
                      style: ManaType.note,
                    ),
                    const SizedBox(height: ManaSpacing.md),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw(
                              _query.trim().isEmpty
                                  ? ref.t('no_customers_due_right_now')
                                  : ref.t('no_customers_match_view'),
                              textAlign: TextAlign.center,
                              style: ManaType.secondary),
                        ),
                      )
                    else
                      ...visible.map((row) => _CustomerDueRow(
                            row: row,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => CollectionEntryScreen(row: row, businessId: widget.businessId)),
                            ),
                          )),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CustomerDueRow extends ConsumerWidget {
  final CollectionDueRow row;
  final VoidCallback onTap;
  const _CustomerDueRow({required this.row, required this.onTap});

  ({IconData icon, Color color}) get _statusIcon => switch (row.collectionStatus) {
        'Collected' => (icon: Icons.check_circle, color: ManaColors.statusGood),
        'Partial' => (icon: Icons.adjust, color: ManaColors.statusWarn),
        'Skipped' => (icon: Icons.remove_circle_outline, color: ManaColors.textSecondary),
        'Closed' => (icon: Icons.lock_outline, color: ManaColors.textSecondary),
        _ => (icon: Icons.radio_button_unchecked, color: ManaColors.textSecondary),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = _statusIcon;
    // Same bug, same fix as OW-006's _DueRow (this widget is a near-verbatim
    // duplicate of it): ListTile's fixed-height/fixed-width trailing slot
    // overflows at larger text scales, and putting the amount beside the
    // name in a Row overflows too even with Flexible+ellipsis on both —
    // Flexible cannot shrink a child below its own minimum intrinsic width,
    // and an unbroken long name or loan number is exactly that case. The
    // amount goes on its own line below instead, never competing with the
    // name for horizontal space.
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(s.icon, color: s.color),
              const SizedBox(width: ManaSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: ManaText.raw(row.customerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ManaType.emphasis),
                        ),
                        if (row.penaltyEligible) ...[
                          const SizedBox(width: ManaSpacing.xs),
                          ManaStatusPill(label: ref.t('penalty'), status: ManaStatus.bad),
                        ] else if (row.gracePeriod) ...[
                          const SizedBox(width: ManaSpacing.xs),
                          ManaStatusPill(label: ref.t('grace'), status: ManaStatus.warn),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    ManaText.raw('${row.village} · ${row.loanNumber} · LRI ${row.lineRepaymentIndex}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ManaType.note),
                    const SizedBox(height: ManaSpacing.xs),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ManaText.raw(manaRupees(row.installmentDue),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ManaType.cardTitle),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
