/// One roster pattern for customers, agents and investors.
///
/// WHY THIS EXISTS: OW-002, OW-003 and OW-004 are the same screen three times
/// — a list of people in a role, ways to add one, and things you can do to
/// one — and they had drifted badly:
///
///   * three "add" paths crammed into each AppBar as separate icon buttons
///     (register new / add existing by ID / pre-existing migration);
///   * different status vocabulary per role, despite one shared
///     membership_status_enum;
///   * OW-004 mixed daily actions with destructive ones in a single menu, so
///     "Collect" sat one row above "Delete".
///
/// That last one is the reason this component separates [MemberAction] into
/// primary and destructive groups and renders them apart. In an app about
/// money, a routine action must never be adjacent to an irreversible one.
library;

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import 'mana_text.dart';

/// The membership lifecycle states a roster filters on. These come straight
/// from membership_status_enum rather than being re-invented per screen.
enum MemberFilter {
  all,
  active,
  pending,
  suspended;

  /// Statuses this filter accepts. 'Pending Invitation', 'Pending Acceptance'
  /// and 'Pending Approval' all read as "waiting on somebody" to an Owner
  /// scanning a list, so they group together.
  bool matches(String status) => switch (this) {
        MemberFilter.all => true,
        MemberFilter.active => status == 'Active',
        MemberFilter.pending => status.startsWith('Pending'),
        MemberFilter.suspended =>
          status == 'Suspended' || status == 'Temporarily Disabled' || status == 'Removed',
      };
}

/// One row in the roster.
class MemberEntry {
  final String id;
  final String name;

  /// MLID, village, or whatever identifies this person at a glance.
  final String subtitle;
  final String status;
  final String? photoUrl;

  const MemberEntry({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.status,
    this.photoUrl,
  });

  ManaStatus get statusKind => switch (status) {
        'Active' => ManaStatus.good,
        'Suspended' || 'Removed' => ManaStatus.bad,
        _ when status.startsWith('Pending') => ManaStatus.warn,
        _ => ManaStatus.neutral,
      };
}

/// Something you can do, either to the roster or to one member.
class MemberAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Irreversible or lifecycle-changing — suspend, remove, delete. Rendered
  /// apart from the primary actions and never given the visual weight of a
  /// button someone taps every day.
  final bool destructive;

  const MemberAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });
}

/// The roster screen body: heading with a filter dropdown, search, list.
///
/// Deliberately a body rather than a whole Scaffold, so each screen keeps its
/// own AppBar, drawer and footer nav.
class ManaMemberRoster extends StatefulWidget {
  /// "Customers", "Agents", "Investors".
  final String heading;
  final List<MemberEntry> members;

  /// Translated names for each filter, in MemberFilter.values order.
  final List<String> filterLabels;

  final String searchHint;
  final String emptyLabel;

  /// Opened by the single Add FAB. Replaces the two or three AppBar icons
  /// each screen used to carry.
  final List<MemberAction> addActions;
  final String addLabel;

  final void Function(MemberEntry) onOpen;
  final bool loading;

  /// A screen-specific filter shown under the search box — the village
  /// dropdown on Customers, for instance.
  ///
  /// A slot rather than a fixed set of filters: only one of the three rosters
  /// needs village, and baking it into the shared component would either
  /// carry dead UI on the other two or push this widget towards knowing about
  /// customers specifically, which is the coupling it exists to avoid.
  final Widget? extraFilter;

  /// Note under the filters, e.g. how the list is sorted.
  final String? footnote;

  /// Supplies a richer row than the default.
  ///
  /// WHY THIS EXISTS, and why it is not a failure of the shared component:
  /// the Customers row carries money — outstanding amount and a due date —
  /// and OW-004 deliberately does NOT use a ListTile for it. Its own comment
  /// records the reason: ListTile's trailing slot assumes a bounded width,
  /// which a two-line amount + "Due X" column stops fitting once text scale
  /// grows, and that overflow was caught by this screen's first layout test.
  ///
  /// Forcing every roster into the default ListTile row would reintroduce
  /// that bug and silently drop the money from the list. The heading,
  /// dropdown, search, FAB, add-sheet and action-sheet are still shared;
  /// only the row differs, because customers carry balances and agents do
  /// not.
  final Widget Function(MemberEntry entry, VoidCallback onTap)? rowBuilder;

  const ManaMemberRoster({
    super.key,
    required this.heading,
    required this.members,
    required this.filterLabels,
    required this.searchHint,
    required this.emptyLabel,
    required this.addActions,
    required this.addLabel,
    required this.onOpen,
    this.loading = false,
    this.extraFilter,
    this.footnote,
    this.rowBuilder,
  });

  @override
  State<ManaMemberRoster> createState() => _ManaMemberRosterState();
}

class _ManaMemberRosterState extends State<ManaMemberRoster> {
  MemberFilter _filter = MemberFilter.all;
  String _query = '';

  List<MemberEntry> get _visible {
    final q = _query.trim().toLowerCase();
    return widget.members.where((m) {
      if (!_filter.matches(m.status)) return false;
      if (q.isEmpty) return true;
      return m.name.toLowerCase().contains(q) || m.subtitle.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openAddSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in widget.addActions)
              ListTile(
                leading: Icon(a.icon),
                title: ManaText.raw(a.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  a.onTap();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, ManaSpacing.sm),
              child: Row(
                children: [
                  Flexible(
                    child: ManaText.raw(
                      widget.heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.sm),
                  // A dropdown, not a row of filter chips. Chips are a
                  // horizontal run of translated labels, which is precisely
                  // the shape that overflows at 2.0x text scale in this app;
                  // a dropdown is fixed width whatever the language.
                  Flexible(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<MemberFilter>(
                        value: _filter,
                        isDense: true,
                        borderRadius: BorderRadius.circular(ManaRadius.md),
                        onChanged: (v) => setState(() => _filter = v ?? MemberFilter.all),
                        items: [
                          for (var i = 0; i < MemberFilter.values.length; i++)
                            DropdownMenuItem(
                              value: MemberFilter.values[i],
                              child: ManaText.raw(
                                widget.filterLabels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  hintText: widget.searchHint,
                  filled: true,
                  fillColor: ManaColors.surfaceSunken,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (widget.extraFilter != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
                child: widget.extraFilter!,
              ),
            ],
            if (widget.footnote != null) ...[
              const SizedBox(height: ManaSpacing.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
                child: SizedBox(
                  width: double.infinity,
                  child: ManaText.raw(
                    widget.footnote!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ManaColors.textSecondary),
                  ),
                ),
              ),
            ],
            const SizedBox(height: ManaSpacing.sm),
            Expanded(
              child: widget.loading
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(ManaSpacing.xxl),
                              child: ManaText.raw(
                                widget.emptyLabel,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: ManaColors.textSecondary),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          // Room for the FAB not to cover the last row.
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: visible.length,
                          itemBuilder: (_, i) {
                            final entry = visible[i];
                            void open() => widget.onOpen(entry);
                            return widget.rowBuilder?.call(entry, open) ??
                                _MemberRow(entry: entry, onTap: open);
                          },
                        ),
            ),
          ],
        ),
        Positioned(
          right: ManaSpacing.lg,
          bottom: ManaSpacing.lg,
          child: FloatingActionButton.extended(
            onPressed: _openAddSheet,
            icon: const Icon(Icons.person_add_alt_1),
            label: ManaText.raw(widget.addLabel,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final MemberEntry entry;
  final VoidCallback onTap;
  const _MemberRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: ManaColors.surfaceSunken,
        backgroundImage:
            entry.photoUrl == null ? null : NetworkImage(entry.photoUrl!),
        child: entry.photoUrl == null
            ? Icon(Icons.person, color: ManaColors.textSecondary)
            : null,
      ),
      title: ManaText.raw(entry.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: ManaText.raw(entry.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
      trailing: ManaTrailingStatus(label: entry.status, status: entry.statusKind),
    );
  }
}

/// The per-member sheet: who they are, what you can do, and — kept apart —
/// what you should think twice about.
Future<void> showMemberActions(
  BuildContext context, {
  required MemberEntry entry,
  required List<MemberAction> actions,
  required String moreLabel,
}) {
  final primary = actions.where((a) => !a.destructive).toList();
  final destructive = actions.where((a) => a.destructive).toList();

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ManaText.raw(entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: ManaSpacing.sm),
          for (final a in primary)
            ListTile(
              leading: Icon(a.icon),
              title: ManaText.raw(a.label, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.of(sheetContext).pop();
                a.onTap();
              },
            ),
          if (destructive.isNotEmpty) ...[
            const Divider(height: ManaSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
              child: ManaText.raw(
                moreLabel,
                style: TextStyle(fontSize: 11, color: ManaColors.textSecondary),
              ),
            ),
            for (final a in destructive)
              ListTile(
                leading: Icon(a.icon, color: ManaColors.statusBad),
                title: ManaText.raw(a.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ManaColors.statusBad)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  a.onTap();
                },
              ),
          ],
        ],
      ),
    ),
  );
}
