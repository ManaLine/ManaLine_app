import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/person_identity.dart';
import '../state/backup_export_service.dart';

/// P3 Backup — export the business's records as a spreadsheet.
///
/// Two steps on purpose: generate, then share. Generating reads six tables and
/// can take a moment on a village connection, and a single button that both
/// fetched and opened the share sheet would leave the user staring at nothing
/// wondering whether it worked. The counts shown after generation are also the
/// only way to tell a real backup from an empty one before sending it on.
class BackupScreen extends ConsumerStatefulWidget {
  final String businessId;
  const BackupScreen({super.key, required this.businessId});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  BackupResult? _result;

  Future<void> _generate() async {
    setState(() => _busy = true);
    final name = businessNameFor(ref, widget.businessId) ?? 'Business';

    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(backupExportServiceProvider).generate(
            businessId: widget.businessId,
            businessName: name,
          );
    });

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  Future<void> _share() async {
    final r = _result;
    if (r == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(backupExportServiceProvider).shareWorkbook(r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: ManaText.raw('Could not share the file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // extra carries the businessId back, so the destination does not fall
          // through to router.dart's stub-business-id fallback.
          onPressed: () => context.pop(),
        ),
        title: const ManaText('backup'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            const ManaText('export to excel',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              'Creates a spreadsheet of your customers, loans, collections, '
              'expenses, investments and daily ledger. Deleted records are '
              'not included.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton.icon(
              onPressed: _busy ? null : _generate,
              icon: const Icon(Icons.table_chart_outlined),
              label: ManaText(r == null ? 'create backup' : 'create again'),
            ),
            if (_busy) ...[
              const SizedBox(height: ManaSpacing.lg),
              const Center(child: CircularProgressIndicator()),
            ],
            if (r != null && !_busy) ...[
              const SizedBox(height: ManaSpacing.lg),
              ManaText.raw(r.fileName,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: ManaSpacing.sm),
              for (final e in r.counts.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(child: ManaText.raw(e.key)),
                      ManaText.raw('${e.value}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              // A truncated backup that looks complete is worse than a refused
              // one, so the cap is stated rather than hidden.
              if (r.truncatedSheets.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.md),
                ManaText.raw(
                  'Some sheets were too large and were cut to '
                  '${BackupExportService.maxRowsPerSheet} rows: '
                  '${r.truncatedSheets.join(", ")}. This backup is incomplete.',
                  style: TextStyle(
                      fontSize: 13, color: ManaColors.statusBad),
                ),
              ],
              const SizedBox(height: ManaSpacing.lg),
              OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.ios_share),
                label: const ManaText('share file'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
