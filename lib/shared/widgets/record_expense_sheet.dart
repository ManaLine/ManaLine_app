import 'package:flutter/material.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/components/mana_text.dart';
import '../network_error_handler.dart';

/// The expense categories are `expense_category_enum`, not a UI list — the
/// RPC casts the string straight to the enum, so anything not in this set
/// fails server-side. External Chit is here deliberately: BR-061 records an
/// external chit as an expense only, never as a cheti asset.
const List<String> kExpenseCategories = <String>[
  'General',
  'Travel',
  'Salary',
  'Fuel',
  'External Chit',
  'Other',
];

/// Shared expense-entry sheet for both the Owner (day closure) and the
/// Agent (settlement) surfaces.
///
/// Deliberately UI-only: it takes an [onSubmit] callback rather than
/// touching Supabase, because each workspace wraps the RPC in its own
/// `*_api_service` and screens in this codebase never call the database
/// directly. That also keeps one implementation of the form instead of two
/// that can drift apart on validation.
///
/// Returns `true` when an expense was actually recorded.
class RecordExpenseSheet extends StatefulWidget {
  /// Records the expense. Should throw on failure — the sheet lets
  /// [NetworkErrorHandler] render the server's own refusal (notably
  /// "Agent BF is only X, cannot pay a Y expense") rather than inventing
  /// its own wording for a money failure.
  final Future<void> Function({
    required String category,
    required int amount,
    String? remarks,
  }) onSubmit;

  /// Shown under the title, e.g. whose cash this comes out of. The RPC
  /// deducts from the payer's own balance, and the payer is whoever is
  /// logged in — worth saying out loud before they confirm.
  final String payerNote;

  const RecordExpenseSheet({
    super.key,
    required this.onSubmit,
    required this.payerNote,
  });

  static Future<bool> show(
    BuildContext context, {
    required Future<void> Function({
      required String category,
      required int amount,
      String? remarks,
    }) onSubmit,
    required String payerNote,
  }) async {
    final recorded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: RecordExpenseSheet(onSubmit: onSubmit, payerNote: payerNote),
      ),
    );
    return recorded ?? false;
  }

  @override
  State<RecordExpenseSheet> createState() => _RecordExpenseSheetState();
}

class _RecordExpenseSheetState extends State<RecordExpenseSheet> {
  String _category = kExpenseCategories.first;
  final _amount = TextEditingController();
  final _remarks = TextEditingController();
  String? _amountError;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Whole rupees only: every money column is numeric(_,0), so paise
    // cannot be stored and must not be silently truncated here.
    final amount = int.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter a whole rupee amount above zero');
      return;
    }
    setState(() {
      _amountError = null;
      _saving = true;
    });

    final result = await NetworkErrorHandler.run(context, () async {
      await widget.onSubmit(
        category: _category,
        amount: amount,
        remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
      );
      return true;
    });

    if (!mounted) return;
    if (result == true) {
      Navigator.pop(context, true);
    } else {
      // The handler already told the user what went wrong; stay open so
      // they can correct the amount rather than losing what they typed.
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      // Scrollable because at 2.0x the form is taller than a 360x640
      // handset viewport (measured: 182px over). A bottom sheet that
      // cannot scroll simply hides its own Record button.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ManaText('record expense',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(widget.payerNote,
                  style: TextStyle(
                      color: ManaColors.textSecondary, fontSize: 13)),
              const SizedBox(height: ManaSpacing.lg),
              DropdownButtonFormField<String>(
                initialValue: _category,
                // Without isExpanded the dropdown sizes to its widest item's
                // natural width; "External Chit" at 2.0x overflowed the field
                // by 120px. Expanded, the label ellipsizes inside the field.
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in kExpenseCategories)
                    DropdownMenuItem(value: c, child: ManaText.raw(c)),
                ],
                onChanged:
                    _saving ? null : (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _amount,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Amount',
                  errorText: _amountError,
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: _remarks,
                enabled: !_saving,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Remarks (optional)',
                ),
              ),
              const SizedBox(height: ManaSpacing.lg),
              // OverflowBar, not Row: at 1.6x and above the two translated
              // button labels do not fit side by side on a 360dp handset —
              // measured, not guessed. It lays them out horizontally when
              // they fit and stacks them when they do not.
              OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: ManaSpacing.sm,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    child: const ManaText('cancel'),
                  ),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const ManaText('record'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
