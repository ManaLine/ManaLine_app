import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tokens/colors.dart';
import 'mana_text.dart';

/// Opens the handset's own dialer with the number already keyed in.
///
/// Deliberately `tel:` and not a call placed by the app: the person still
/// presses the green button themselves, which is the difference between a
/// shortcut and an app that rings someone by surprise. It also means no
/// CALL_PHONE permission — `tel:` needs none, because dialling is the user's
/// action in their own dialer.
///
/// Renders nothing at all when there is no number. An agent looking at a
/// customer with no phone on file should not see a dead call button and
/// wonder whether the tap failed.
class ManaCallButton extends StatelessWidget {
  final String? phoneNumber;

  /// Shown in the failure message so the person can dial it by hand if the
  /// handset has no dialer to hand it to (a tablet with no SIM, mostly).
  final String? label;

  /// `icon` for a list row, `filled` for a profile screen's main action.
  final bool filled;

  const ManaCallButton(this.phoneNumber, {super.key, this.label, this.filled = false});

  bool get _hasNumber => (phoneNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '').length >= 10;

  Future<void> _dial(BuildContext context) async {
    final digits = phoneNumber!.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    // canLaunchUrl can answer false on a device that would in fact dial, so
    // the launch is attempted first and only its failure is reported.
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw('No dialer on this device. The number is $digits.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasNumber) return const SizedBox.shrink();

    if (filled) {
      return FilledButton.icon(
        onPressed: () => _dial(context),
        icon: const Icon(Icons.call, size: 18),
        label: ManaText.raw(label ?? phoneNumber!),
      );
    }
    return IconButton(
      icon: Icon(Icons.call, size: 20, color: ManaColors.brand),
      tooltip: phoneNumber,
      onPressed: () => _dial(context),
    );
  }
}
