import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens/colors.dart';
import '../../design/tokens/spacing.dart';
import '../../design/components/mana_text.dart';
import '../mana_location.dart';
import '../translation_service.dart';

/// "Use My Location" for any address form.
///
/// WHY THIS IS A COMPONENT: every place an address is typed needs the same
/// button with the same rules, and the rules are easy to get subtly wrong —
/// the interesting behaviour is what happens when the geocoder is vague,
/// which in rural India is most of the time.
///
/// Three rules, all of them the reason this is shared rather than copied:
///
///  1. **It never blocks.** No result is an error state. The person types
///     the address exactly as they would have anyway, and the button simply
///     saved them nothing that time.
///  2. **Coordinates outrank labels.** A fix with no readable address is
///     still worth keeping — lat/long is the part nobody can retype later
///     from memory, and `person_addresses.gps_*` is where a doorstep is
///     actually recorded. [onCaptured] therefore fires whenever there is a
///     position, whether or not any field was filled.
///  3. **It fills, it does not lock.** Everything it writes stays editable.
///     The geocoder is a suggestion; the person standing at the door is the
///     authority.
class UseMyLocationButton extends ConsumerStatefulWidget {
  /// Called with whatever was resolved. Fires only when there is a real
  /// position; `place.pinCode` / `place.village` may still be null.
  final void Function(ManaPlace place) onCaptured;

  const UseMyLocationButton({super.key, required this.onCaptured});

  @override
  ConsumerState<UseMyLocationButton> createState() => _UseMyLocationButtonState();
}

class _UseMyLocationButtonState extends ConsumerState<UseMyLocationButton> {
  bool _busy = false;

  Future<void> _capture() async {
    setState(() => _busy = true);
    final place = await ManaLocation.currentPlace();
    if (!mounted) return;
    setState(() => _busy = false);

    if (place.hasPosition) widget.onCaptured(place);

    // Always say what happened. A button that silently does nothing when the
    // GPS is off is indistinguishable from a broken button.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(place.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _busy ? null : _capture,
        icon: _busy
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.my_location, size: 20, color: ManaColors.brand),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xs),
          child: ManaText.raw(ref.t('use_my_location')),
        ),
      ),
    );
  }
}
