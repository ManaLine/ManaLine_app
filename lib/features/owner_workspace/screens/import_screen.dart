import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/import_service.dart';

/// P3 Import — enter a business's existing loan book from a spreadsheet.
///
/// Three steps, in order, because each one can fail differently and an Owner
/// needs to know which: get the template, pick the filled-in file, send it.
///
/// Nothing is imported unless every row is good. That is enforced on the
/// server, and it is stated on this screen too, because it changes what the
/// Owner should do when it fails: fix the sheet and upload the whole thing
/// again, rather than hunting for which rows got through.
class ImportScreen extends ConsumerStatefulWidget {
  final String businessId;
  const ImportScreen({super.key, required this.businessId});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _busy = false;
  ImportParse? _parse;
  String? _fileName;
  String? _formatError;
  ImportOutcome? _outcome;

  Future<void> _template() async {
    setState(() => _busy = true);
    try {
      final svc = ref.read(importServiceProvider);
      final bytes = await svc.buildTemplate(businessId: widget.businessId);
      await svc.shareTemplate(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: ManaText.raw('Could not build the template: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    const group = XTypeGroup(
      label: 'Spreadsheet',
      extensions: ['xlsx', 'csv'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return; // cancelled — not an error

    setState(() {
      _busy = true;
      _formatError = null;
      _outcome = null;
      _parse = null;
      _fileName = file.name;
    });

    try {
      final bytes = await file.readAsBytes();
      final parse = ImportService.parseBytes(bytes, file.name);
      if (!mounted) return;
      setState(() => _parse = parse);
    } on ImportFormatException catch (e) {
      if (mounted) setState(() => _formatError = e.message);
    } catch (e) {
      if (mounted) setState(() => _formatError = 'Could not read this file: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final parse = _parse;
    if (parse == null) return;
    setState(() => _busy = true);

    final outcome = await NetworkErrorHandler.run(context, () async {
      return ref.read(importServiceProvider).submit(
            businessId: widget.businessId,
            rows: parse.rows,
          );
    });

    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcome = outcome;
      // Only clear the parsed file on success. After a rejection the Owner
      // still needs to see which rows were wrong.
      if (outcome != null && !outcome.rejected) _parse = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final parse = _parse;
    final outcome = _outcome;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const ManaText('import records'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            const ManaText.raw(
              'Enter loans your business already had before it came onto MANA '
              'LINE. If any row is wrong, nothing is imported — fix the sheet '
              'and upload it again.',
              style: TextStyle(fontSize: 13, color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),

            const ManaText('step 1',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: ManaSpacing.xs),
            OutlinedButton.icon(
              onPressed: _busy ? null : _template,
              icon: const Icon(Icons.download_outlined),
              label: const ManaText('get template'),
            ),
            const SizedBox(height: ManaSpacing.lg),

            const ManaText('step 2',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: ManaSpacing.xs),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.folder_open_outlined),
              label: const ManaText('choose file'),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(_fileName!,
                  style: const TextStyle(fontSize: 13)),
            ],
            if (_formatError != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(
                _formatError!,
                style: const TextStyle(
                    fontSize: 13, color: ManaColors.statusBad),
              ),
            ],

            if (_busy) ...[
              const SizedBox(height: ManaSpacing.lg),
              const Center(child: CircularProgressIndicator()),
            ],

            if (parse != null && !_busy) ...[
              const SizedBox(height: ManaSpacing.lg),
              const ManaText('step 3',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw('${parse.rows.length} rows ready to import',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: ManaSpacing.sm),
              ElevatedButton.icon(
                onPressed: parse.rows.isEmpty ? null : _import,
                icon: const Icon(Icons.upload_outlined),
                label: const ManaText('import'),
              ),
            ],

            if (outcome != null && !_busy) ...[
              const SizedBox(height: ManaSpacing.lg),
              if (!outcome.rejected)
                ManaText.raw(
                  '${outcome.imported} loans imported.',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ManaColors.statusGood),
                )
              else ...[
                ManaText.raw(
                  'Nothing was imported. ${outcome.errors.length} '
                  '${outcome.errors.length == 1 ? "row" : "rows"} need fixing:',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ManaColors.statusBad),
                ),
                const SizedBox(height: ManaSpacing.sm),
                for (final e in outcome.errors)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: ManaText.raw(
                      'Row ${e.row}: ${e.message}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
