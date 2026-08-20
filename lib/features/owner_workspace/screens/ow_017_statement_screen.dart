import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/ledger_statement_service.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';

/// My Statements — period picker, then an Excel statement of the ledger feed.
///
/// Excel rather than PDF: the app already depends on `excel` and
/// BackupExportService already writes and shares a workbook, so this adds no
/// dependency. A PDF would also need per-language font embedding for Telugu,
/// Hindi, Tamil and Kannada, which is the real cost of that route.
class StatementScreen extends ConsumerStatefulWidget {
  final String businessId;
  final String businessName;

  const StatementScreen({
    super.key,
    required this.businessId,
    this.businessName = '',
  });

  @override
  ConsumerState<StatementScreen> createState() => _StatementScreenState();
}

enum _Mode { range, financialYear }

class _ChoiceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: ManaText.raw(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.circle_outlined,
        color: selected ? ManaColors.statusGood : ManaColors.textDisabled,
      ),
    );
  }
}

class _StatementScreenState extends ConsumerState<StatementScreen> {
  _Mode _mode = _Mode.range;
  int _rangeDays = 30;
  late int _fyStart = StatementPeriod.currentFinancialYearStart();
  bool _busy = false;

  StatementPeriod get _period => _mode == _Mode.range
      ? StatementPeriod.lastDays(_rangeDays, 'last_n_days')
      : StatementPeriod.financialYear(_fyStart);

  Future<void> _download() async {
    setState(() => _busy = true);
    final result = await NetworkErrorHandler.run(context, () async {
      final svc = ref.read(ledgerStatementServiceProvider);
      final r = await svc.generate(
        businessId: widget.businessId,
        businessName: widget.businessName,
        period: _period,
      );
      await svc.share(r);
      return r;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (result == null) return; // network failure, already surfaced

    final messenger = ScaffoldMessenger.of(context);
    if (result.eventCount == 0) {
      messenger.showSnackBar(SnackBar(
        content: ManaText.raw(ref.t('statement_has_no_transactions')),
      ));
    } else if (result.truncated) {
      // Reported, never silent: a statement missing rows must say so.
      messenger.showSnackBar(SnackBar(
        content: ManaText.raw(ref
            .t('statement_truncated_note')
            .replaceAll('{count}', '${result.eventCount}')),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fyOptions = [
      for (var i = 0; i < 5; i++) StatementPeriod.currentFinancialYearStart() - i,
    ];

    return Scaffold(
      appBar: AppBar(title: ManaText(ref.t('my_statements'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            ManaText(ref.t('statement_period'),
                style: ManaType.heavy),
            const SizedBox(height: ManaSpacing.sm),
            SegmentedButton<_Mode>(
              segments: [
                ButtonSegment(value: _Mode.range, label: ManaText(ref.t('range'))),
                ButtonSegment(
                    value: _Mode.financialYear, label: ManaText(ref.t('financial_year'))),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: ManaSpacing.lg),
            // Plain ListTiles with a check glyph rather than RadioListTile:
            // Radio's groupValue/onChanged are deprecated in this Flutter in
            // favour of a RadioGroup ancestor, and a selectable row reads the
            // same to the user either way.
            if (_mode == _Mode.range)
              for (final days in const [30, 90, 180, 365])
                _ChoiceTile(
                  label: ref.t('last_n_days').replaceAll('{count}', '$days'),
                  selected: _rangeDays == days,
                  onTap: () => setState(() => _rangeDays = days),
                )
            else
              for (final year in fyOptions)
                _ChoiceTile(
                  label: 'FY $year - ${year + 1}',
                  selected: _fyStart == year,
                  onTap: () => setState(() => _fyStart = year),
                ),
            const Divider(height: ManaSpacing.xl),
            // Shows the resolved dates, so "Last 90 days" is never ambiguous
            // about which 90 days it means.
            ManaText.raw(
              '${manaDisplayDate(_period.from)} — ${manaDisplayDate(_period.to)}',
              style: ManaType.note,
            ),
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              ref.t('statement_excel_note'),
              style: ManaType.fine,
            ),
            const SizedBox(height: ManaSpacing.xl),
            ElevatedButton(
              onPressed: _busy ? null : _download,
              child: _busy
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText(ref.t('download_statement')),
            ),
          ],
        ),
      ),
    );
  }
}
