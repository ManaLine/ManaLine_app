import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
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
          SnackBar(content: ManaText.raw(ref.t('could_not_build_template_note').replaceAll('{error}', '$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final group = XTypeGroup(
      label: ref.t('spreadsheet'),
      extensions: const ['xlsx', 'csv'],
    );
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) return; // cancelled — not an error

    if (!mounted) return;
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
      appBar: ManaAppBar(
        homeRoute: '/settings',
        title: ref.t('import_records'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            ManaText.raw(
              ref.t('import_records_note'),
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.lg),

            ManaText.raw(ref.t('step_1'),
                style: ManaType.heavy),
            const SizedBox(height: ManaSpacing.xs),
            OutlinedButton.icon(
              onPressed: _busy ? null : _template,
              icon: const Icon(Icons.download_outlined),
              label: ManaText.raw(ref.t('get_template')),
            ),
            const SizedBox(height: ManaSpacing.lg),

            ManaText.raw(ref.t('step_2'),
                style: ManaType.heavy),
            const SizedBox(height: ManaSpacing.xs),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.folder_open_outlined),
              label: ManaText.raw(ref.t('choose_file')),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(_fileName!,
                  style: ManaType.small),
            ],
            if (_formatError != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(
                _formatError!,
                style: TextStyle(
                    fontSize: 13, color: ManaColors.statusBad),
              ),
            ],

            if (_busy) ...[
              const SizedBox(height: ManaSpacing.lg),
              const Center(child: CircularProgressIndicator()),
            ],

            if (parse != null && !_busy) ...[
              const SizedBox(height: ManaSpacing.lg),
              ManaText.raw(ref.t('step_3'),
                  style: ManaType.heavy),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(ref.t('rows_ready_to_import').replaceAll('{count}', '${parse.rows.length}'),
                  style: ManaType.heavy),
              const SizedBox(height: ManaSpacing.sm),
              ElevatedButton.icon(
                onPressed: parse.rows.isEmpty ? null : _import,
                icon: const Icon(Icons.upload_outlined),
                label: ManaText.raw(ref.t('import_label')),
              ),
            ],

            if (outcome != null && !_busy) ...[
              const SizedBox(height: ManaSpacing.lg),
              if (!outcome.rejected)
                ManaText.raw(
                  ref.t('loans_imported_note').replaceAll('{count}', '${outcome.imported}'),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ManaColors.statusGood),
                )
              else ...[
                ManaText.raw(
                  ref.t('nothing_imported_note').replaceAll('{count}', '${outcome.errors.length}'),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ManaColors.statusBad),
                ),
                const SizedBox(height: ManaSpacing.sm),
                for (final e in outcome.errors)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: ManaText.raw(
                      ref
                          .t('row_error_note')
                          .replaceAll('{row}', '${e.row}')
                          .replaceAll('{message}', e.message),
                      style: ManaType.small,
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
