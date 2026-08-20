import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design/tokens/colors.dart';
import '../../design/tokens/typography.dart';
import '../../design/tokens/spacing.dart';
import '../../design/components/mana_text.dart';
import '../network_error_handler.dart';
import '../soft_delete_service.dart';

/// The warning before a delete, and the delete itself.
///
/// Deliberately states the two consequences that are not obvious from the
/// button: that the figures move, and that there is a way back. Users
/// forgive a delete they were warned about; they do not forgive a closing
/// balance that changed without explanation.
///
/// Returns true when the record was deleted.
class ConfirmDeleteDialog extends ConsumerStatefulWidget {
  final DeletableEntity entity;
  final String recordId;

  /// What is being deleted, in the user's terms — "Collection RCT-2026…",
  /// "Expense — Fuel ₹450". Shown verbatim so they can check they picked
  /// the right row.
  final String description;

  /// True when removing this row changes a day's closing balance. Every
  /// ledger-source record does; remarks and documents do not.
  final bool affectsBalances;

  const ConfirmDeleteDialog({
    super.key,
    required this.entity,
    required this.recordId,
    required this.description,
    this.affectsBalances = true,
  });

  static Future<bool> show(
    BuildContext context, {
    required DeletableEntity entity,
    required String recordId,
    required String description,
    bool affectsBalances = true,
  }) async {
    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => ConfirmDeleteDialog(
        entity: entity,
        recordId: recordId,
        description: description,
        affectsBalances: affectsBalances,
      ),
    );
    return deleted ?? false;
  }

  @override
  ConsumerState<ConfirmDeleteDialog> createState() =>
      _ConfirmDeleteDialogState();
}

class _ConfirmDeleteDialogState extends ConsumerState<ConfirmDeleteDialog> {
  final _reason = TextEditingController();
  bool _deleting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);

    final until = await NetworkErrorHandler.run(context, () async {
      return ref.read(softDeleteServiceProvider).softDelete(
            entity: widget.entity,
            recordId: widget.recordId,
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          );
    });

    if (!mounted) return;
    if (until == null) {
      // The server refused — most likely no can_delete_records. Stay open.
      setState(() => _deleting = false);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber, color: ManaColors.statusWarn),
          const SizedBox(width: ManaSpacing.sm),
          Expanded(child: ManaText('delete ${widget.entity.label.toLowerCase()}')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(widget.description,
                style: ManaType.emphasis),
            const SizedBox(height: ManaSpacing.md),
            if (widget.affectsBalances)
              ManaText.raw(
                'This entry counts towards the day it belongs to. Deleting it '
                'changes that day\'s closing balance, and every day after it.',
                style: TextStyle(
                    color: ManaColors.textSecondary, fontSize: 13),
              ),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(
              'It moves to Recent Deletes and can be restored for 30 days. '
              'After that it is removed permanently.',
              style: TextStyle(
                  color: ManaColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _reason,
              enabled: !_deleting,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Why is this being removed?',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _deleting ? null : () => Navigator.pop(context, false),
          child: const ManaText('cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
          onPressed: _deleting ? null : _delete,
          child: _deleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const ManaText('delete'),
        ),
      ],
    );
  }
}
