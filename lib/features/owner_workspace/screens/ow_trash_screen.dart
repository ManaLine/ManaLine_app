import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design/components/mana_amount.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/soft_delete_service.dart';
import '../../../shared/translation_service.dart';

/// Trash. Everything this business has deleted, and the only place it can be
/// destroyed on purpose.
///
/// Deleting here has always been recoverable: a row is hidden for 30 days and
/// then swept by a nightly job. What was missing was any way to see the whole
/// bin, and any way to say "this one, now" -- an Owner who deleted something
/// they did not want recoverable had to wait a month for it to go.
///
/// Long-press starts a selection. The primary tap has to stay harmless on a
/// screen whose other action cannot be undone.
class OwnerTrashScreen extends ConsumerStatefulWidget {
  final String businessId;
  const OwnerTrashScreen({super.key, required this.businessId});

  @override
  ConsumerState<OwnerTrashScreen> createState() => _OwnerTrashScreenState();
}

class _OwnerTrashScreenState extends ConsumerState<OwnerTrashScreen> {
  final _selected = <String>{};
  bool _working = false;

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(String id) => setState(() {
        if (_selected.contains(id)) {
          _selected.remove(id);
        } else {
          _selected.add(id);
        }
      });

  Future<void> _purgeSelected(List<DeletedRecord> all) async {
    final chosen = all.where((r) => _selected.contains(r.recordId)).toList();
    if (chosen.isEmpty) return;

    // Says the number, and says it cannot be undone. A loan takes its
    // collections with it, which the person agreeing is entitled to know
    // beforehand rather than afterwards.
    final anyLoan = chosen.any((r) => r.entityWireName == 'loan');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: ManaText.raw(ref.t('delete_forever')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref
                .t('delete_forever_count_note')
                .replaceAll('{count}', '${chosen.length}')),
            if (anyLoan) ...[
              const SizedBox(height: ManaSpacing.md),
              ManaText.raw(ref.t('delete_forever_loan_note'),
                  style: TextStyle(color: ManaColors.statusBad)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: ManaText.raw(ref.t('delete_forever')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      // One at a time, so a refusal on one record does not quietly take the
      // rest of the batch down with it.
      for (final r in chosen) {
        await ref.read(softDeleteServiceProvider).purge(
              entityWireName: r.entityWireName,
              recordId: r.recordId,
            );
      }
      return true;
    });
    if (!mounted) return;
    setState(() {
      _working = false;
      if (ok == true) _selected.clear();
    });
    ref.invalidate(recentDeletesProvider(widget.businessId));
  }

  Future<void> _restore(DeletedRecord r) async {
    setState(() => _working = true);
    await NetworkErrorHandler.run(context, () async {
      await ref.read(softDeleteServiceProvider).restore(
            entityWireName: r.entityWireName,
            recordId: r.recordId,
          );
      return true;
    });
    if (!mounted) return;
    setState(() => _working = false);
    ref.invalidate(recentDeletesProvider(widget.businessId));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recentDeletesProvider(widget.businessId));
    final date = DateFormat('d MMM yyyy');

    return Scaffold(
      appBar: ManaAppBar(
        title: _selecting
            ? ref.t('n_selected').replaceAll('{count}', '${_selected.length}')
            : ref.t('trash'),
        homeRoute: '/ow-settings',
        homeExtra: widget.businessId,
        actions: [
          if (_selecting)
            IconButton(
              tooltip: ref.t('delete_forever'),
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed: _working
                  ? null
                  : () => _purgeSelected(async.valueOrNull ?? const []),
            ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw(
                  ref
                      .t('could_not_load_deleted_records')
                      .replaceAll('{error}', '$e'),
                  textAlign: TextAlign.center),
            ),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  child: ManaText.raw(ref.t('nothing_has_been_deleted'),
                      style: ManaType.secondary),
                ),
              );
            }
            return Column(
              children: [
                // Select-all appears only once a selection has started.
                // Offering it to somebody who has selected nothing is an
                // invitation to empty the bin by accident.
                if (_selecting)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: ManaSpacing.md, vertical: ManaSpacing.xs),
                    child: Row(
                      children: [
                        Expanded(
                          child: ManaText.raw(
                            ref
                                .t('n_of_m_selected')
                                .replaceAll('{count}', '${_selected.length}')
                                .replaceAll('{total}', '${rows.length}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ManaType.note,
                          ),
                        ),
                        const SizedBox(width: ManaSpacing.xs),
                        Flexible(
                          child: TextButton(
                            onPressed: () => setState(() {
                              if (_selected.length == rows.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(rows.map((r) => r.recordId));
                              }
                            }),
                            child: ManaText.raw(
                                _selected.length == rows.length
                                    ? ref.t('clear_selection')
                                    : ref.t('select_all'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_working) const LinearProgressIndicator(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async => ref
                        .invalidate(recentDeletesProvider(widget.businessId)),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(ManaSpacing.md),
                      itemCount: rows.length,
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final picked = _selected.contains(r.recordId);
                        return Card(
                          margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
                          color: picked ? ManaColors.brandFaint : null,
                          child: InkWell(
                            // A plain tap only selects while a selection is
                            // running. Otherwise it does nothing, because the
                            // only other action on this screen destroys.
                            onTap:
                                _selecting ? () => _toggle(r.recordId) : null,
                            onLongPress: () => _toggle(r.recordId),
                            child: Padding(
                              padding: const EdgeInsets.all(ManaSpacing.md),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_selecting)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          right: ManaSpacing.sm),
                                      child: Icon(
                                        picked
                                            ? Icons.check_circle
                                            : Icons.circle_outlined,
                                        color: picked
                                            ? ManaColors.brand
                                            : ManaColors.textSecondary,
                                      ),
                                    ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: ManaText.raw(r.label,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: ManaType.emphasis),
                                            ),
                                            if (r.amount != null) ...[
                                              const SizedBox(
                                                  width: ManaSpacing.sm),
                                              Flexible(
                                                child: ManaText.raw(
                                                    manaRupees(r.amount!),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.right,
                                                    style: ManaType.cardTitle),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        ManaText.raw(
                                          '${date.format(r.deletedAt)} - ${r.deletedBy}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: ManaType.note,
                                        ),
                                        if (r.reason != null &&
                                            r.reason!.trim().isNotEmpty)
                                          ManaText.raw(r.reason!,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: ManaType.small),
                                        const SizedBox(height: ManaSpacing.xs),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: ManaText.raw(
                                                ref
                                                    .t('days_left_note')
                                                    .replaceAll(
                                                        '{days}', '${r.daysLeft}'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: r.daysLeft <= 3
                                                        ? ManaColors.statusWarn
                                                        : ManaColors
                                                            .textSecondary),
                                              ),
                                            ),
                                            if (!_selecting)
                                              Flexible(
                                                child: TextButton(
                                                  onPressed: _working
                                                      ? null
                                                      : () => _restore(r),
                                                  child: ManaText.raw(
                                                      ref.t('restore'),
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
