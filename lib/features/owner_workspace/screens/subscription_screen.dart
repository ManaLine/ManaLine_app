import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../state/subscription_state.dart';

/// P4 Subscription — plans, and where this business sits against them.
///
/// No purchase button. Billing is not built this round, and an inert
/// "Subscribe" would be a promise the app cannot keep. The screen says plainly
/// that nothing is being charged yet rather than leaving an Owner to guess
/// whether they are already paying.
class SubscriptionScreen extends ConsumerWidget {
  final String businessId;
  const SubscriptionScreen({super.key, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(businessUsageProvider(businessId));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: ManaText.raw(ref.t('subscription')),
      ),
      body: SafeArea(
        child: usage.when(
          loading: () => const ManaSkeletonList(itemCount: 4, itemHeight: 120),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.xl),
              child: ManaText.raw(
                'Could not load your current usage.\n\n$e',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: ManaColors.statusBad),
              ),
            ),
          ),
          data: (u) => ListView(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            children: [
              ManaText.raw(
                ref.t('planned_prices_note'),
                style:
                    TextStyle(fontSize: 13, color: ManaColors.textSecondary),
              ),
              const SizedBox(height: ManaSpacing.lg),
              _UsageCard(usage: u),
              const SizedBox(height: ManaSpacing.lg),
              ManaText.raw(ref.t('plans'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: ManaSpacing.sm),
              for (final t in kOwnerTiers)
                _TierCard(tier: t, isCurrent: t.name == u.currentTier.name),
              const SizedBox(height: ManaSpacing.lg),
              ManaText.raw(ref.t('customers_and_investors'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                ref.t('customers_investors_free_note'),
                style:
                    TextStyle(fontSize: 13, color: ManaColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageCard extends ConsumerWidget {
  final BusinessUsage usage;
  const _UsageCard({required this.usage});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = usage.currentTier;
    return Container(
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.brandFaint,
        borderRadius: BorderRadius.circular(ManaRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(ref.t('your_business_today'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: ManaSpacing.sm),
          _UsageRow(label: ref.t('agents'), value: usage.agents, cap: t.agents),
          _UsageRow(label: ref.t('customers'), value: usage.customers, cap: t.customers),
          _UsageRow(label: ref.t('investors'), value: usage.investors, cap: t.investors),
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(
            'That fits the ${t.name} plan.',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  final String label;
  final int value;
  final int? cap;
  const _UsageRow({required this.label, required this.value, this.cap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          // Expanded, not a bare Text: the label is translated and the figure
          // beside it is not, which is the shape that overflows once the
          // translated word is longer than the English one.
          Expanded(child: ManaText.raw(label)),
          ManaText.raw(
            cap == null ? '$value' : '$value of $cap',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  final SubscriptionTier tier;
  final bool isCurrent;
  const _TierCard({required this.tier, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      padding: const EdgeInsets.all(ManaSpacing.md),
      decoration: BoxDecoration(
        color: ManaColors.surface,
        borderRadius: BorderRadius.circular(ManaRadius.md),
        border: Border.all(
          color: isCurrent ? ManaColors.brandDeep : ManaColors.divider,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrap, not Row. "₹1,999/yr" beside a plan name is already most of
          // 360dp, and at 1.3x an unflexible price next to an Expanded name
          // overflows — the same bare-child-beside-a-flexible-one shape that
          // has shipped here five times. Wrap lets the price drop to its own
          // line instead of competing for width.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: ManaSpacing.sm,
            runSpacing: 2,
            children: [
              ManaText.raw(
                tier.name,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16),
              ),
              ManaText.raw(
                tier.isCustom
                    ? tier.monthly
                    : '${tier.monthly}/mo  ·  ${tier.yearly}/yr',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(
            tier.isCustom
                ? 'For businesses beyond the Business plan.'
                : 'Up to ${tier.agents} agents, ${tier.customers} customers, '
                    '${tier.investors} investors.',
            style: TextStyle(
                fontSize: 13, color: ManaColors.textSecondary),
          ),
          if (isCurrent) ...[
            const SizedBox(height: ManaSpacing.xs),
            ManaText.raw(
              'Your business fits here.',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ManaColors.brandDeep),
            ),
          ],
        ],
      ),
    );
  }
}
