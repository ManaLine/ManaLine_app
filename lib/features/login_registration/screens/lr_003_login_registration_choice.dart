import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/widgets/language_selector.dart';
import '../../../shared/local_auth_store.dart';
import '../state/auth_flow_state.dart';

/// LR-003 — pure fork point, no network call, no loading states.
class LoginRegistrationChoiceScreen extends ConsumerWidget {
  const LoginRegistrationChoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(authFlowProvider).language;

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/lr-002'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            children: [
              const Spacer(),
              const ManaText('already registered?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: ManaSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final pinLength = await LocalAuthStore.readPinLength();
                    if (!context.mounted) return;
                    context.push(pinLength != null ? '/lr-009' : '/lr-007');
                  },
                  child: const ManaText('yes, i\'m registered'),
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.push('/lr-004'),
                  child: const ManaText('no, i\'m new'),
                ),
              ),
              const Spacer(),
              ManaLanguageSelector(
                current: lang,
                onChanged: (l) => ref.read(authFlowProvider.notifier).setLanguage(l),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
