/// The filter sheet for both history screens.
///
/// Left rail of groups, right pane of choices, Apply at the bottom — the
/// shape people already know from payment apps. Returns null when dismissed
/// without applying, so the caller can tell "cancelled" from "cleared".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import 'ledger_history_service.dart';
import 'ledger_labels.dart';
import 'mana_time.dart';
import 'translation_service.dart';

Future<LedgerFilter?> showLedgerFilterSheet(
  BuildContext context,
  WidgetRef ref,
  LedgerFilter current, {
  /// AG-010 passes the subset an agent can actually receive. Offering a
  /// "Cheti" filter to someone whose RLS returns no cheti rows would look
  /// like missing money rather than an absent permission.
  Set<LedgerEventType>? availableTypes,
}) {
  return showModalBottomSheet<LedgerFilter>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LedgerFilterSheet(
      initial: current,
      availableTypes: availableTypes ?? LedgerEventType.values.toSet(),
    ),
  );
}

enum _Group { types, dates }

class _LedgerFilterSheet extends ConsumerStatefulWidget {
  final LedgerFilter initial;
  final Set<LedgerEventType> availableTypes;

  const _LedgerFilterSheet({required this.initial, required this.availableTypes});

  @override
  ConsumerState<_LedgerFilterSheet> createState() => _LedgerFilterSheetState();
}

class _LedgerFilterSheetState extends ConsumerState<_LedgerFilterSheet> {
  late Set<LedgerEventType> _types = {...widget.initial.types};
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;
  _Group _group = _Group.types;

  Future<void> _pickRange() async {
    final today = manaNowIst();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 10),
      // IST, like every other date bound in this app — a handset behind IST
      // would otherwise be unable to pick the day it is actually working in.
      lastDate: today,
      initialDateRange: _from != null && _to != null
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _from = picked.start;
        _to = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = widget.availableTypes.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: ManaText(ref.t('filters'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _types = {};
                      _from = null;
                      _to = null;
                    }),
                    child: ManaText(ref.t('clear_all')),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 132,
                    child: Container(
                      color: ManaColors.surfaceSunken,
                      child: ListView(
                        children: [
                          _railItem(_Group.types, ref.t('categories')),
                          _railItem(_Group.dates, ref.t('date_range')),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _group == _Group.types
                        ? ListView(
                            children: [
                              for (final t in types)
                                CheckboxListTile(
                                  value: _types.contains(t),
                                  title: ManaText.raw(
                                    ledgerTypeLabel(ref, t),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onChanged: (on) => setState(() {
                                    if (on == true) {
                                      _types.add(t);
                                    } else {
                                      _types.remove(t);
                                    }
                                  }),
                                ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.all(ManaSpacing.lg),
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: ManaText(ref.t('date_range')),
                                subtitle: ManaText.raw(
                                  _from == null || _to == null
                                      ? ref.t('all_dates')
                                      : '${manaDisplayDate(_from)} — ${manaDisplayDate(_to)}',
                                ),
                                trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                                onTap: _pickRange,
                              ),
                              if (_from != null)
                                TextButton(
                                  onPressed: () => setState(() {
                                    _from = null;
                                    _to = null;
                                  }),
                                  child: ManaText(ref.t('clear_all')),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(
                    widget.initial.copyWith(
                      types: _types,
                      from: _from,
                      to: _to,
                      clearDates: _from == null,
                    ),
                  ),
                  child: ManaText(ref.t('apply')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _railItem(_Group group, String label) {
    final selected = _group == group;
    return Material(
      color: selected ? ManaColors.surface : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _group = group),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: ManaSpacing.md, vertical: ManaSpacing.md),
          child: ManaText.raw(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
