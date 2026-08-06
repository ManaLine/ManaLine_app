import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/components/mana_text.dart';
import '../network_error_handler.dart';
import '../soft_delete_service.dart';

final _currency =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('d MMM yyyy');

/// Recent Deletes — the 30-day bin, for the Owner and any agent the Owner
/// granted can_delete_records.
///
/// Not a locked spec screen: it has no LR/OW/AG id because it is not in the
/// spec. It is reached by push from wherever a delete happens, and is
/// registered at /recent-deletes rather than being given a fabricated id
/// that would break the one-route-per-screen-id cross reference.
class RecentDeletesScreen extends ConsumerWidget {
  final String businessId;
  const RecentDeletesScreen({super.key, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentDeletesProvider(businessId));

    return Scaffold(
      appBar: AppBar(title: const ManaText('recent deletes')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw('Could not load deleted records.\n$e',
                  textAlign: TextAlign.center),
            ),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(ManaSpacing.lg),
                  child: ManaText('nothing has been deleted'),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async =>
                  ref.invalidate(recentDeletesProvider(businessId)),
              child: ListView.separated(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                itemCount: rows.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: ManaSpacing.sm),
                itemBuilder: (_, i) => _DeletedRow(
                  record: rows[i],
                  businessId: businessId,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DeletedRow extends ConsumerStatefulWidget {
  final DeletedRecord record;
  final String businessId;
  const _DeletedRow({required this.record, required this.businessId});

  @override
  ConsumerState<_DeletedRow> createState() => _DeletedRowState();
}

class _DeletedRowState extends ConsumerState<_DeletedRow> {
  bool _restoring = false;

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(softDeleteServiceProvider).restore(
            entityWireName: widget.record.entityWireName,
            recordId: widget.record.recordId,
          );
      return true;
    });
    if (!mounted) return;
    if (ok != true) {
      setState(() => _restoring = false);
      return;
    }
    ref.invalidate(recentDeletesProvider(widget.businessId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw('${widget.record.label} restored.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    // 0 days left means the next nightly purge takes it. Saying "today" is
    // the honest reading of that, not "expired".
    final expiryLabel =
        r.daysLeft <= 0 ? 'removed permanently today' : '${r.daysLeft} days left';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ManaText.raw(r.label,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (r.amount != null)
                  ManaText.raw(_currency.format(r.amount),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              [
                if (r.businessDate != null) _dateFmt.format(r.businessDate!),
                'deleted by ${r.deletedBy}',
                _dateFmt.format(r.deletedAt),
              ].join(' · '),
              style: TextStyle(
                  color: ManaColors.textSecondary, fontSize: 12),
            ),
            if (r.reason != null && r.reason!.isNotEmpty) ...[
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw('“${r.reason}”',
                  style: TextStyle(
                      color: ManaColors.textSecondary,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: ManaSpacing.sm),
            // OverflowBar rather than a Row: the expiry text plus a button
            // is the shape that overflows once translated and scaled.
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.start,
              children: [
                ManaText.raw(expiryLabel,
                    style: TextStyle(
                        fontSize: 12,
                        color: r.daysLeft <= 3
                            ? ManaColors.statusBad
                            : ManaColors.textSecondary)),
                TextButton.icon(
                  onPressed: _restoring ? null : _restore,
                  icon: const Icon(Icons.restore, size: 18),
                  label: const ManaText('restore'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
