import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/translation_service.dart';

/// Where the handset sends an Owner who wants to bring a whole book across.
///
/// THE WIZARD IS NOT GONE — it is on the web build, where it always ran, and
/// this screen is the signpost. The Owner's judgement, 2026-09-18: "for an
/// user onboarding wizard via app is difficult and messy and may go wrong".
///
/// The screen it replaces is seven pages of spreadsheet grids and the largest
/// file in `lib/`. It asks somebody to download a workbook, fill it in and
/// upload it again — on a phone, where there is nowhere comfortable to edit a
/// spreadsheet at all, and where every step that goes wrong goes wrong against
/// a real book being migrated once.
///
/// SAME ROUTE, DIFFERENT BUILD. `/ow-bulk-onboarding` still exists in both
/// routers; the handset builds this and the web build still builds
/// `BulkOnboardingWizardScreen`. Keeping the route means the old entry point
/// in OW-018 leads somewhere that explains itself, rather than to a dead end
/// or a removed button an Owner remembers pressing last week.
class BulkOnboardingOnWebScreen extends ConsumerWidget {
  final String businessId;
  const BulkOnboardingOnWebScreen({super.key, required this.businessId});

  /// Deliberately the app's front door, not a deep link to the wizard.
  ///
  /// The Owner has to sign in on the web anyway — the session does not travel
  /// from the handset — so a link straight to `/ow-bulk-onboarding` would land
  /// on a login screen and lose the destination on the way through. Sending
  /// them to the front door and naming the menu item is the honest route, and
  /// it is the one the instruction described: "website - login - menu showing
  /// bulk onboarding".
  static const websiteUrl = 'https://manaline.in/app/';

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    // canLaunchUrl answers false on devices that would in fact open a
    // browser, so the launch is attempted and only its failure is reported —
    // the same pattern ManaCallButton uses for the dialer.
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(websiteUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ManaText.raw(
        ref.t('no_browser_on_this_device').replaceAll('{url}', websiteUrl),
      ),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: ManaAppBar(
        title: ref.t('bulk_onboarding'),
        homeRoute: '/ow-001',
        homeExtra: businessId,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            Icon(Icons.desktop_windows_outlined,
                size: 44, color: ManaColors.brand),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('bulk_onboarding_is_on_the_web'),
                style: ManaType.sheetTitle),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(ref.t('bulk_onboarding_is_on_the_web_body'),
                style: ManaType.secondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('bulk_onboarding_web_steps'),
                style: ManaType.note),
            const SizedBox(height: ManaSpacing.lg),

            // Wrap, not Row. Two buttons and a Telugu label do not share a
            // 360dp line, and a bare button beside a flexible one is the
            // overflow this project has shipped four times.
            Wrap(
              spacing: ManaSpacing.sm,
              runSpacing: ManaSpacing.xs,
              children: [
                FilledButton.icon(
                  onPressed: () => _open(context, ref),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: ManaText.raw(ref.t('open_the_website')),
                ),
                // A second way out, because the first one depends on there
                // being a browser that answers. An Owner can paste this into
                // the laptop they are about to do the work on anyway.
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        const ClipboardData(text: websiteUrl));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: ManaText.raw(ref.t('copied'))),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: ManaText.raw(ref.t('copy_link')),
                ),
              ],
            ),

            const SizedBox(height: ManaSpacing.lg),
            const Divider(),
            const SizedBox(height: ManaSpacing.sm),
            // The door that did NOT move. Somebody arriving here for three
            // investors should not be sent to a laptop for them.
            ManaText.raw(ref.t('one_by_one_still_works_here'),
                style: ManaType.note),
          ],
        ),
      ),
    );
  }
}
