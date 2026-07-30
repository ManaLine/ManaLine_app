import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../state/auth_flow_state.dart';

/// LR-006 — confirms MLID, auto-navigates after 4s (locked default),
/// manual Continue button as safety net. No back navigation (terminal
/// state of the registration sub-flow).
class RegistrationResultScreen extends ConsumerStatefulWidget {
  const RegistrationResultScreen({super.key});

  @override
  ConsumerState<RegistrationResultScreen> createState() => _RegistrationResultScreenState();
}

class _RegistrationResultScreenState extends ConsumerState<RegistrationResultScreen> {
  Timer? _autoAdvance;

  @override
  void initState() {
    super.initState();
    _autoAdvance = Timer(const Duration(seconds: 4), _continue);
  }

  @override
  void dispose() {
    _autoAdvance?.cancel();
    super.dispose();
  }

  void _continue() {
    _autoAdvance?.cancel();
    if (mounted) context.go('/lr-007');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authFlowProvider);
    final isTemp = auth.mlidType == 'MLTI';

    return PopScope(
      canPop: false, // no back navigation, per spec
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: ManaColors.statusGood, size: 64),
                const SizedBox(height: ManaSpacing.lg),
                const ManaText('your mana line id',
                    style: TextStyle(color: ManaColors.textSecondary)),
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(
                  auth.mlid ?? '—',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: ManaSpacing.sm),
                const ManaText.raw(
                  'Save this ID. You\'ll use it to log in and it\'s yours for life.',
                  textAlign: TextAlign.center,
                ),
                if (isTemp) ...[
                  const SizedBox(height: ManaSpacing.md),
                  const ManaText.raw(
                    'Temporary ID issued. Add your Aadhaar later from your '
                    'profile to get your permanent ID.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ManaColors.statusWarn, fontSize: 13),
                  ),
                ],
                const SizedBox(height: ManaSpacing.xxl),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(onPressed: _continue, child: const ManaText('continue')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
