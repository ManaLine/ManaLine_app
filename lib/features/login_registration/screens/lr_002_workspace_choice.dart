import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/translation_service.dart';


/// LR-002 — root product picker. V1 ships MLF (Mana Finance) only;
/// MLC (Mana Chits) is visible-but-disabled to establish brand presence.
class WorkspaceChoiceScreen extends ConsumerWidget {
  const WorkspaceChoiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(translationLoaderProvider); // triggers cache load, rebuilds when ready

    return Scaffold(
      body: SafeArea(
        // SCROLLS, and the Column sizes to its content instead of using
        // Spacer to centre it.
        //
        // WHY: this was a fixed-height Column with two Spacers. Spacers
        // divide up whatever vertical space is LEFT OVER, so the moment the
        // fixed children (72px logo, heading, two product cards) are taller
        // than the viewport that leftover goes negative and the layout
        // overflows — 41px in landscape on a real handset. The identical
        // fix was already applied to LR-009 for the identical reason; this
        // screen was simply missed.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: ManaSpacing.xl),
              // Long-press opens the Platform Admin login.
              //
              // The admin panel had NO entry point at all: nothing anywhere
              // in the app linked to /admin-login, so on the web you could
              // type the URL and on a phone there was simply no way in. It
              // is deliberately a long-press on the pre-login logo rather
              // than a visible row — ordinary Owners should never stumble
              // into it — and the admin username/password screen is still
              // the real gate, so discoverability is not the security
              // boundary here.
              GestureDetector(
                onLongPress: () => context.push('/admin-login'),
                child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  // 1254x1254 source rendered at ~96px. cacheWidth decodes at
                  // display size rather than holding a 2.4MB full-res bitmap
                  // in memory — this is a cheap-Android target and the splash
                  // is the first thing that runs.
                  cacheWidth: 288,
                  height: 72,
                  width: 72,
                  fit: BoxFit.cover,
                ),
                ),
              ),
              const SizedBox(height: ManaSpacing.md),
              Text(
                ref.t('app_name'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ManaColors.brand,
                    ),
              ),
              const SizedBox(height: ManaSpacing.xxl),
              ManaText.raw(ref.t('choose_workspace'), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: ManaSpacing.lg),
              _ProductCard(
                code: 'MLF',
                name: 'Mana Finance',
                enabled: true,
                onTap: () => context.push('/lr-003'),
              ),
              const SizedBox(height: ManaSpacing.md),
              _ProductCard(
                code: 'MLC',
                name: 'Mana Chits',
                enabled: false,
                badge: ref.t('coming_soon'),
                onTap: () => _showComingSoon(context),
              ),
              const SizedBox(height: ManaSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ManaText('mana chits — coming soon — version 2', textAlign: TextAlign.center),
            const SizedBox(height: ManaSpacing.md),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const ManaText('close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final String code;
  final String name;
  final bool enabled;
  final String? badge;
  final VoidCallback onTap;

  const _ProductCard({
    required this.code,
    required this.name,
    required this.enabled,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: enabled ? ManaColors.brandFaint : ManaColors.surfaceSunken,
                  child: ManaText.raw(code, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: ManaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(name, style: Theme.of(context).textTheme.titleMedium),
                      if (badge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: ManaText(badge!, style: Theme.of(context).textTheme.labelSmall),
                        ),
                    ],
                  ),
                ),
                if (enabled) Icon(Icons.chevron_right, color: ManaColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
