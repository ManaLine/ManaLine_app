import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/widgets/language_selector.dart';
import '../../../shared/local_auth_store.dart';
import '../../../shared/translation_service.dart';
import '../state/auth_flow_state.dart';

/// LR-003 — pure fork point, no network call, no loading states.
class LoginRegistrationChoiceScreen extends ConsumerWidget {
  const LoginRegistrationChoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(authFlowProvider).language;
    ref.watch(translationLoaderProvider);

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/lr-002'))),
      body: SafeArea(
        // Centred when there is room, scrollable when there is not.
        //
        // This was a bare Column with Spacers, which cannot absorb a taller
        // language or a raised system font — the Spacers' flex goes negative
        // and the screen overflows. ConstrainedBox + IntrinsicHeight keeps
        // the Spacers working (so it still looks centred on a normal
        // handset) while the scroll view takes over the moment the content
        // is taller than the viewport.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - ManaSpacing.lg * 2,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const Spacer(),
                    ManaText.raw(ref.t('already_registered_q'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: ManaSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final pinLength = await LocalAuthStore.readPinLength();
                          if (!context.mounted) return;
                          context.push(pinLength != null ? '/lr-009' : '/lr-007');
                        },
                        child: ManaText.raw(ref.t('yes_im_registered')),
                      ),
                    ),
                    const SizedBox(height: ManaSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.push('/lr-004'),
                        child: ManaText.raw(ref.t('no_im_new')),
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
          ),
        ),
      ),
    );
  }
}
