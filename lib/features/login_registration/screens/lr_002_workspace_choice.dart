import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_brand_mark.dart';
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
                  // 1024x1024 source rendered at 72px. cacheWidth decodes at
                  // display size rather than holding the full-res bitmap in
                  // memory — this is a cheap-Android target.
                  cacheWidth: 216,
                  height: 72,
                  width: 72,
                  // contain, not cover: the asset is cropped to the circle's
                  // own edge, so cover would shave the rim.
                  fit: BoxFit.contain,
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
              const SizedBox(height: 2),
              // Not translated: the tagline is the brand, and a brand that
              // changes wording per language stops being one. Same constant
              // the login screen uses, so the two cannot drift.
              ManaText.raw(
                kManaTagline,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.0,
                  color: ManaColors.textSecondary,
                ),
              ),
              const SizedBox(height: ManaSpacing.xxl),
              ManaText.raw(ref.t('choose_workspace'), style: ManaType.strong),
              const SizedBox(height: ManaSpacing.lg),
              _ProductCard(
                code: 'MLF',
                name: 'Mana Finance',
                enabled: true,
                // Straight to the login screen. LR-003 ("Already registered?
                // Login / Register") used to sit here and has been deleted:
                // it asked a question the app can answer itself. LR-009 shows
                // the PIN pad when this device has a PIN and the password
                // form when it does not, and Register is a button on that
                // form — so the choice screen was a tap that told us nothing.
                onTap: () => context.push('/lr-009'),
              ),
              const SizedBox(height: ManaSpacing.md),
              _ProductCard(
                code: 'MLC',
                name: 'Mana Cheeti',
                enabled: false,
                badge: ref.t('coming_soon'),
                onTap: () => _showComingSoon(context, ref),
              ),
              const SizedBox(height: ManaSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ManaText.raw(ref.t('mana_chits_coming_soon'), textAlign: TextAlign.center),
            const SizedBox(height: ManaSpacing.md),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: ManaText.raw(ref.t('close')),
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
                  child: ManaText.raw(code, style: ManaType.strong),
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
