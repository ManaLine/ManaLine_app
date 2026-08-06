import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/components/mana_text.dart';
import '../gps_address_service.dart';
import '../mana_location.dart';

/// Shows whether the agent is standing where the customer's address says they
/// should be.
///
/// INFORMATION, NEVER A GATE. Nothing on this banner blocks a collection, and
/// there is deliberately no "you must be at the address" path — an agent may
/// legitimately collect at a shop, a field, or a relative's house, and a
/// customer who moved has not committed fraud. It exists so a mismatch is
/// VISIBLE, not so it can be enforced.
///
/// It checks quietly on its own and says nothing at all until it has an
/// answer, because an agent opening a customer wants the collection screen,
/// not a spinner about geography.
class AddressCheckBanner extends ConsumerStatefulWidget {
  final String customerId;
  const AddressCheckBanner({super.key, required this.customerId});

  @override
  ConsumerState<AddressCheckBanner> createState() => _AddressCheckBannerState();
}

class _AddressCheckBannerState extends ConsumerState<AddressCheckBanner> {
  ManaFix? _fix;
  AddressCheck? _check;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check_());
  }

  Future<void> _check_() async {
    // currentFix never throws; compare can, if the network is down mid-visit.
    // Either way this widget goes quiet rather than showing an error about a
    // check nobody asked for.
    try {
      final fix = await ManaLocation.currentFix();
      AddressCheck? result;
      if (fix.hasPosition && !fix.isTooRoughToJudge) {
        result = await ref
            .read(gpsAddressServiceProvider)
            .compare(customerId: widget.customerId, fix: fix);
      }
      if (!mounted) return;
      setState(() {
        _fix = fix;
        _check = result;
        _done = true;
      });
    } catch (_) {
      if (mounted) setState(() => _done = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_done) return const SizedBox.shrink();

    final check = _check;
    final fix = _fix;

    // Nothing useful to say. Staying silent beats "could not verify" on every
    // single customer, which people learn to stop reading within a day.
    if (check == null && (fix == null || fix.hasPosition)) {
      return const SizedBox.shrink();
    }

    final (String text, Color colour, IconData icon) = switch (check) {
      // A confirmed mismatch is the only thing worth colouring as a warning.
      AddressCheck(isMismatch: true) => (
          check.message,
          ManaColors.statusBad,
          Icons.wrong_location_outlined
        ),
      AddressCheck(isIndeterminate: false) => (
          check.message,
          ManaColors.statusGood,
          Icons.where_to_vote_outlined
        ),
      // Indeterminate, or no comparison possible: neutral, and worded as "not
      // checked" rather than anything that sounds like a finding about the
      // customer.
      _ => (
          check?.message ?? fix?.message ?? 'Address was not checked.',
          ManaColors.textSecondary,
          Icons.location_searching
        ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: ManaSpacing.md),
      padding: const EdgeInsets.all(ManaSpacing.sm),
      decoration: BoxDecoration(
        color: ManaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(ManaRadius.md),
      ),
      // Row with an Expanded text: the message is a full sentence and the
      // longest of them overflows beside a bare icon at 2.0x.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: ManaSpacing.sm),
          Expanded(
            child: ManaText.raw(
              text,
              style: TextStyle(fontSize: 13, color: colour),
            ),
          ),
        ],
      ),
    );
  }
}
