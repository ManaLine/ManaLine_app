import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/local_auth_store.dart';
import '../../../shared/network_error_handler.dart';
import '../state/auth_flow_state.dart';
import '../state/auth_api_service.dart';

enum _PinStep { enter, confirm, biometric }

/// LR-008 — mandatory, non-skippable checkpoint. No back navigation.
class CreatePinScreen extends ConsumerStatefulWidget {
  const CreatePinScreen({super.key});

  @override
  ConsumerState<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends ConsumerState<CreatePinScreen> {
  int _length = 4;
  String _pin = '';
  String _confirmPin = '';
  _PinStep _step = _PinStep.enter;
  bool _submitting = false;

  void _onDigit(String digit) {
    setState(() {
      if (_step == _PinStep.enter) {
        if (_pin.length < _length) _pin += digit;
        if (_pin.length == _length) _step = _PinStep.confirm;
      } else if (_step == _PinStep.confirm) {
        if (_confirmPin.length < _length) _confirmPin += digit;
        if (_confirmPin.length == _length) _checkMatch();
      }
    });
  }

  void _checkMatch() {
    if (_pin == _confirmPin) {
      setState(() => _step = _PinStep.biometric);
    } else {
      setState(() {
        _pin = '';
        _confirmPin = '';
        _step = _PinStep.enter;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('PINs don\'t match')));
    }
  }

  Future<void> _finish({required bool biometricEnabled}) async {
    setState(() => _submitting = true);

    final personId = ref.read(authFlowProvider).personId;
    if (personId == null) {
      // Defensive — this screen should be unreachable without a personId
      // already set by LR-004/LR-007's login result.
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Please log in again.')),
      );
      context.go('/lr-001');
      return;
    }

    final result = await NetworkErrorHandler.run(context, () async {
      await ref.read(authApiServiceProvider).createPin(
            personId: personId,
            pin: _pin,
            biometricEnabled: biometricEnabled,
          );
      return true;
    });

    if (!mounted) return;
    if (result == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown, stay put
    }

    // LR-009 Daily Login depends on both of these already being on-device
    // before it can work — pin_length locally-remembered metadata, and
    // the PIN value itself for biometric-unlock reuse (LR-009 API BINDING).
    await LocalAuthStore.savePin(pin: _pin, biometricEnabled: biometricEnabled);

    // Fresh registration -> PIN creation is the first point a session
    // exists with no memberships fetched yet (LR-007's path already
    // fetches them before reaching here when pinExists was already true;
    // this is the "never had a PIN" branch). Fetch now so LR-012 has real
    // data instead of an empty list.
    final memberships = await NetworkErrorHandler.run(
      context,
      () => ref.read(authApiServiceProvider).fetchMemberships(),
    );
    if (!mounted) return;
    if (memberships == null) {
      setState(() => _submitting = false);
      return; // network failure — SnackBar already shown
    }
    ref.read(authFlowProvider.notifier).setMemberships(memberships);

    if (!mounted) return;
    context.go('/lr-012');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // no back navigation anywhere on this screen, per spec
      child: Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: _step == _PinStep.biometric ? _biometricPrompt() : _pinPad(),
          ),
        ),
      ),
    );
  }

  Widget _pinPad() {
    final label = _step == _PinStep.enter ? 'Create a PIN for quick daily login' : 'Confirm your PIN';
    final activeCount = _step == _PinStep.enter ? _pin.length : _confirmPin.length;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ManaText.raw(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_length, (i) {
            final filled = i < activeCount;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 16, height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? ManaColors.brass : ManaColors.surfaceSunken,
              ),
            );
          }),
        ),
        if (_step == _PinStep.enter) ...[
          const SizedBox(height: ManaSpacing.md),
          TextButton(
            onPressed: () => setState(() => _length = _length == 4 ? 6 : 4),
            child: ManaText('use ${_length == 4 ? 6 : 4}-digit pin instead'),
          ),
        ],
        const SizedBox(height: ManaSpacing.xl),
        _numberPad(),
      ],
    );
  }

  Widget _numberPad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: rows
          .map((row) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: row.map((d) {
                  if (d.isEmpty) return const SizedBox(width: 72, height: 56);
                  return SizedBox(
                    width: 72, height: 56,
                    child: TextButton(
                      onPressed: () {
                        if (d == '⌫') {
                          setState(() {
                            if (_step == _PinStep.enter && _pin.isNotEmpty) {
                              _pin = _pin.substring(0, _pin.length - 1);
                            } else if (_step == _PinStep.confirm && _confirmPin.isNotEmpty) {
                              _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
                            }
                          });
                        } else {
                          _onDigit(d);
                        }
                      },
                      child: Text(d, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                }).toList(),
              ))
          .toList(),
    );
  }

  Widget _biometricPrompt() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.fingerprint, size: 56, color: ManaColors.brass),
        const SizedBox(height: ManaSpacing.md),
        const ManaText('enable biometric login?', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.xl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : () => _finish(biometricEnabled: true),
            child: const ManaText('yes, enable'),
          ),
        ),
        const SizedBox(height: ManaSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _submitting ? null : () => _finish(biometricEnabled: false),
            child: const ManaText('not now'),
          ),
        ),
      ],
    );
  }
}
