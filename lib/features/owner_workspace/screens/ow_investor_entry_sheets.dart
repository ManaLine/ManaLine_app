/// Entering one investment, or one profit share, for a person already picked.
///
/// These replace two spreadsheet round-trips. A business has a handful of
/// investors and shareholders, all of them already recorded on page 1, so the
/// sheet was asking the Owner to retype names and MLIDs the app had just
/// written down — and every retyped MLID was a chance to attach money to the
/// wrong person.
///
/// Dates are picked from a calendar, never typed: 01/02 and 02/01 are the same
/// eight keystrokes and different months, and money hangs off which one was
/// meant. The interest type is a choice, not free text, because the column is
/// an enum and a typo used to come back as a rejected row after the upload.
library;

import 'package:flutter/material.dart';

import '../../../design/components/mana_text.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../state/bulk_onboarding_service.dart';

/// yyyy-MM-dd, which is what the RPCs take. Shown to the Owner as dd/MM/yyyy.
String _wire(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _shown(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

class _SheetFrame extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback? onSave;
  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.children,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      // viewInsets: the keyboard must not sit on top of the Save button.
      padding: EdgeInsets.only(
        left: ManaSpacing.lg,
        right: ManaSpacing.lg,
        top: ManaSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + ManaSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(title, style: ManaType.strong),
            ManaText.raw(subtitle, style: ManaType.small),
            const SizedBox(height: ManaSpacing.md),
            ...children,
            const SizedBox(height: ManaSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.check),
                label: const ManaText.raw('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InvestmentSheet extends StatefulWidget {
  final ManaMemberRef who;

  /// The migration cut-off, when one has been set — an investment cannot
  /// sensibly be dated after the book hands over.
  final DateTime? cutoff;
  const InvestmentSheet({super.key, required this.who, this.cutoff});

  @override
  State<InvestmentSheet> createState() => _InvestmentSheetState();
}

class _InvestmentSheetState extends State<InvestmentSheet> {
  final _amount = TextEditingController();
  final _roi = TextEditingController(text: '1.5');
  final _profitPercent = TextEditingController(text: '0');
  String _interestType = 'Simple';
  DateTime? _invested;

  @override
  void dispose() {
    _amount.dispose();
    _roi.dispose();
    _profitPercent.dispose();
    super.dispose();
  }

  bool get _ready =>
      (int.tryParse(_amount.text.trim()) ?? 0) > 0 &&
      double.tryParse(_roi.text.trim()) != null &&
      _invested != null;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: widget.who.fullName,
      subtitle: widget.who.mlid,
      onSave: _ready
          ? () => Navigator.of(context).pop(<String, dynamic>{
                'mlid': widget.who.mlid,
                'full_name': widget.who.fullName,
                'invested_amount': int.parse(_amount.text.trim()),
                'roi': _roi.text.trim(),
                'interest_type': _interestType,
                'invested_date': _wire(_invested!),
                'profit_percent': _profitPercent.text.trim().isEmpty
                    ? '0'
                    : _profitPercent.text.trim(),
              })
          : null,
      children: [
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Invested Amount *', prefixText: '₹ '),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _roi,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'ROI *',
            // Spelled out because per-month is the thing outsiders get wrong.
            helperText: 'Rupees per ₹100 per MONTH, not per year',
          ),
        ),
        const SizedBox(height: ManaSpacing.md),
        DropdownButtonFormField<String>(
          // isExpanded: without it a DropdownButton sizes to its widest item's
          // natural width and overflows rather than shrinking -- "Yearly
          // Compound" ran 180px past the edge at 2.0x. With it the item takes
          // the field's width and ellipsises.
          isExpanded: true,
          initialValue: _interestType,
          decoration: const InputDecoration(labelText: 'Interest Type *'),
          items: const [
            DropdownMenuItem(value: 'Simple', child: ManaText.raw('Simple')),
            DropdownMenuItem(
                value: 'Yearly Compound',
                child: ManaText.raw('Yearly Compound')),
          ],
          onChanged: (v) => setState(() => _interestType = v ?? 'Simple'),
        ),
        const SizedBox(height: ManaSpacing.md),
        _DateField(
          label: 'Invested Date *',
          value: _invested,
          lastDate: widget.cutoff,
          onPicked: (d) => setState(() => _invested = d),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _profitPercent,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Profit Share %',
            helperText: 'Leave at 0 if they take no share of profit',
          ),
        ),
      ],
    );
  }
}

class ShareholderSheet extends StatefulWidget {
  final ManaMemberRef who;
  const ShareholderSheet({super.key, required this.who});

  @override
  State<ShareholderSheet> createState() => _ShareholderSheetState();
}

class _ShareholderSheetState extends State<ShareholderSheet> {
  final _percent = TextEditingController();
  final _roi = TextEditingController();
  final _received = TextEditingController();
  DateTime? _paidOn;

  @override
  void dispose() {
    _percent.dispose();
    _roi.dispose();
    _received.dispose();
    super.dispose();
  }

  bool get _ready => (double.tryParse(_percent.text.trim()) ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: widget.who.fullName,
      subtitle: widget.who.mlid,
      onSave: _ready
          ? () => Navigator.of(context).pop(<String, dynamic>{
                'mlid': widget.who.mlid,
                'full_name': widget.who.fullName,
                'share_percent': double.parse(_percent.text.trim()),
                if (_roi.text.trim().isNotEmpty) 'roi_rate': _roi.text.trim(),
                if (_paidOn != null) 'paid_on': _wire(_paidOn!),
                if (_received.text.trim().isNotEmpty)
                  'amount_received': _received.text.trim(),
              })
          : null,
      children: [
        TextField(
          controller: _percent,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Share Of Profit % *', suffixText: '%'),
        ),
        const SizedBox(height: ManaSpacing.md),
        // Optional: a share declared and paid on the same day accrues nothing,
        // and most do. Only fill these in when the payout came later.
        _DateField(
          label: 'Paid On',
          value: _paidOn,
          onPicked: (d) => setState(() => _paidOn = d),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _roi,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'ROI Until Paid',
            helperText: 'Only if the share earned interest before it was paid',
          ),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _received,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Amount Actually Received',
            prefixText: '₹ ',
            helperText: 'What was really handed over, if it differs',
          ),
        ),
      ],
    );
  }
}

/// A date the Owner picks from a calendar rather than types.
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateTime? lastDate;
  final ValueChanged<DateTime> onPicked;
  const _DateField({
    required this.label,
    required this.value,
    required this.onPicked,
    this.lastDate,
  });

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: v ?? (lastDate ?? now),
          firstDate: DateTime(2000),
          lastDate: lastDate ?? DateTime(now.year + 1),
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        child: ManaText.raw(v == null ? 'Tap to choose' : _shown(v)),
      ),
    );
  }
}
