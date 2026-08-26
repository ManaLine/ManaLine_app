import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_text.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../features/owner_workspace/screens/ow_006_collection_mode.dart'
    show ManaCollectionForm, ManaNoCollectionForm, ManaExtensionForm;
import '../features/owner_workspace/state/collection_mode_state.dart';
import 'translation_service.dart';
import 'widgets/address_check_banner.dart';

/// What happens at a door, in one sheet over the round.
///
/// Collect used to push a screen that restated the row -- name, loan number,
/// instalment, outstanding, LRI, grace, penalty -- and then offered three
/// buttons before any figure could be typed. Then it became an inline
/// expansion, which pushed the rest of the round off a 360px screen the moment
/// a row opened.
///
/// A sheet keeps the round underneath and visible, takes only the height it
/// needs, and closes on a tap outside without recording anything -- which is
/// the right default for a money screen a thumb can brush.
///
/// Everything a visit can be is here: the amount, the two ways somebody else's
/// money arrives, and the two outcomes that are not a payment at all. Nothing
/// navigates.
Future<bool> showCollectSheet(
  BuildContext context, {
  required CollectionDueRow row,
  required String businessId,
}) async {
  final recorded = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Tap outside closes it and nothing is written.
    isDismissible: true,
    builder: (sheetContext) => _CollectBody(row: row, businessId: businessId),
  );
  return recorded ?? false;
}

enum _Action { collect, noCollection, extension }

class _CollectBody extends ConsumerStatefulWidget {
  final CollectionDueRow row;
  final String businessId;
  const _CollectBody({required this.row, required this.businessId});

  @override
  ConsumerState<_CollectBody> createState() => _CollectBodyState();
}

class _CollectBodyState extends ConsumerState<_CollectBody> {
  _Action _action = _Action.collect;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ManaSpacing.lg,
        0,
        ManaSpacing.lg,
        // Above the keyboard. Without this the amount field sits under it on
        // a short screen and the Collect button cannot be reached at all.
        MediaQuery.of(context).viewInsets.bottom + ManaSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(row.customerName,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: ManaType.cardTitle),
            const SizedBox(height: ManaSpacing.xs),
            // Informational only, and deliberately so: collecting at a shop or
            // a relative's house is ordinary, and a customer who moved has
            // done nothing wrong. It never blocks a collection.
            AddressCheckBanner(customerId: row.customerId),
            const SizedBox(height: ManaSpacing.sm),
            if (_action == _Action.collect)
              ManaCollectionForm(
                row: row,
                businessId: widget.businessId,
                onCancel: () => Navigator.of(context).pop(false),
                onRecorded: () => Navigator.of(context).pop(true),
              )
            else if (_action == _Action.noCollection)
              ManaNoCollectionForm(
                row: row,
                onCancel: () => setState(() => _action = _Action.collect),
                onRecorded: () => Navigator.of(context).pop(true),
              )
            else
              ManaExtensionForm(
                row: row,
                onCancel: () => setState(() => _action = _Action.collect),
                onRecorded: () => Navigator.of(context).pop(true),
              ),
            if (_action == _Action.collect) ...[
              const Divider(height: ManaSpacing.lg),
              // The two outcomes that are not a payment. On a normal round
              // they are the exception, so they sit quietly -- but at the same
              // door, because that is where they are decided.
              Wrap(
                spacing: ManaSpacing.sm,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _action = _Action.noCollection),
                    icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
                    label: ManaText.raw(ref.t('no_collection')),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _action = _Action.extension),
                    icon: const Icon(Icons.event_repeat_outlined, size: 18),
                    label: ManaText.raw(ref.t('request_extension')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
