import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/customer_discovery_state.dart';

/// CW-002 — Find A Business / Request To Join. Self-service,
/// no-money-moves-in-app model: "Request To Join" only ever creates a
/// `membership_requests` row (requested_role='Customer'). Mirrors
/// IW-002's search → results → request → pending/approved/rejected
/// interaction pattern almost exactly — see that screen for the
/// mechanics this one reuses rather than reinvents.
class FindABusinessScreen extends ConsumerStatefulWidget {
  final String businessId; // originating businessId, passed through for nav back to CW-001
  const FindABusinessScreen({super.key, required this.businessId});

  @override
  ConsumerState<FindABusinessScreen> createState() => _FindABusinessScreenState();
}

class _FindABusinessScreenState extends ConsumerState<FindABusinessScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(customerDiscoveryProvider);

    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('find_a_business')),
        leading: BackButton(onPressed: () => context.go('/cw-001', extra: widget.businessId)),
      ),
      body: SafeArea(
        child: switch (state.phase) {
          DiscoveryPhase.search || DiscoveryPhase.results => _SearchAndResults(controller: _search, state: state),
          DiscoveryPhase.requestPending => _RequestPending(state: state, businessId: widget.businessId),
          DiscoveryPhase.approved => _Approved(state: state, businessId: widget.businessId),
          DiscoveryPhase.rejected => _Rejected(state: state, businessId: widget.businessId),
        },
      ),
    );
  }
}

// --- S1/S2 Search + Results ---------------------------------------------

class _SearchAndResults extends ConsumerWidget {
  final TextEditingController controller;
  final CustomerDiscoveryState state;
  const _SearchAndResults({required this.controller, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: ref.t('search_by_business_name_mlbi'),
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (v) => ref.read(customerDiscoveryProvider.notifier).setQuery(v),
            onSubmitted: (_) =>
                NetworkErrorHandler.run(context, () => ref.read(customerDiscoveryProvider.notifier).search()),
          ),
          const SizedBox(height: ManaSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: state.loading || controller.text.trim().isEmpty
                  ? null
                  : () => NetworkErrorHandler.run(
                      context, () => ref.read(customerDiscoveryProvider.notifier).search()),
              child: state.loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('search')),
            ),
          ),
          const SizedBox(height: ManaSpacing.lg),
          Expanded(
            child: state.phase == DiscoveryPhase.search
                ? Center(
                    child: ManaText.raw(
                      'Search for a Business to request Customer membership.',
                      textAlign: TextAlign.center,
                      style: ManaType.secondary,
                    ),
                  )
                : state.results.isEmpty
                    ? Center(
                        child: ManaText.raw(ref.t('no_businesses_matched'),
                            style: ManaType.secondary),
                      )
                    : ListView.separated(
                        itemCount: state.results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: ManaSpacing.sm),
                        itemBuilder: (context, i) => _BusinessResultCard(business: state.results[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

class _BusinessResultCard extends ConsumerWidget {
  final DiscoveredBusiness business;
  const _BusinessResultCard({required this.business});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: ManaColors.inkFaint,
          backgroundImage: business.logoUrl != null ? NetworkImage(business.logoUrl!) : null,
          child: business.logoUrl == null ? Icon(Icons.storefront, color: ManaColors.textSecondary) : null,
        ),
        title: ManaText.raw(business.businessName, style: ManaType.emphasis),
        subtitle: ManaText.raw(
          '${business.mlbi}${business.operatingAreas.isNotEmpty ? ' · ${business.operatingAreas.join(', ')}' : ''}',
          style: ManaType.note,
        ),
        // Business Status pill per SEARCH RESULT (Active / Not Accepting
        // New Customers) — display only. Unlike IW-002's onTap gate,
        // Request To Join here stays enabled regardless: if this
        // business surfaced in results at all (including via
        // MLBI-exact search on a non-accepting business the Owner still
        // allowed), the eligibility decision already happened
        // server-side — this screen doesn't re-filter it.
        // Same shape as IW-002: a very long status in a trailing slot.
        trailing: ManaTrailingStatus(
          label: business.acceptingNewCustomers ? 'Active' : 'Not Accepting New Customers',
          status: business.acceptingNewCustomers ? ManaStatus.good : ManaStatus.warn,
        ),
        onTap: () {
          ref.read(customerDiscoveryProvider.notifier).selectBusiness(business);
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const _RequestToJoinSheet(),
          );
        },
      ),
    );
  }
}

// --- Request To Join sheet -------------------------------------

class _RequestToJoinSheet extends ConsumerStatefulWidget {
  const _RequestToJoinSheet();

  @override
  ConsumerState<_RequestToJoinSheet> createState() => _RequestToJoinSheetState();
}

class _RequestToJoinSheetState extends ConsumerState<_RequestToJoinSheet> {
  final _remarks = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() => _submitting = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerDiscoveryProvider.notifier).submitRequest(
            remarks: _remarks.text.trim().isEmpty ? null : _remarks.text.trim(),
          );
    });
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(customerDiscoveryProvider).selectedBusiness;
    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('request_to_join_note').replaceAll('{name}', business?.businessName ?? ''),
                style: ManaType.cardTitle),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _remarks,
              decoration: InputDecoration(labelText: ref.t('remarks_optional_field')),
              maxLines: 2,
            ),
            const SizedBox(height: ManaSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _confirm,
                child: _submitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : ManaText.raw(ref.t('confirm_request')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- S3 Request Pending --------------------------------------------------

class _RequestPending extends ConsumerWidget {
  final CustomerDiscoveryState state;
  final String businessId;
  const _RequestPending({required this.state, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ResultState(
      icon: Icons.hourglass_top,
      iconColor: ManaColors.statusWarn,
      title: 'request sent',
      body: 'Status: Pending Owner/Agent Review. You will be notified as soon as they respond.',
      primaryLabel: 'back to dashboard',
      onPrimary: () {
        ref.read(customerDiscoveryProvider.notifier).reset();
        context.go('/cw-001', extra: businessId);
      },
    );
  }
}

// --- S4 Approved -----------------------------------------------------------

class _Approved extends ConsumerWidget {
  final CustomerDiscoveryState state;
  final String businessId;
  const _Approved({required this.state, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ResultState(
      icon: Icons.check_circle,
      iconColor: ManaColors.statusGood,
      title: 'request approved',
      body: 'Business Membership created — Status: Active. This Business now '
          'appears in your Switch Business list.',
      primaryLabel: 'back to dashboard',
      onPrimary: () {
        ref.read(customerDiscoveryProvider.notifier).reset();
        context.go('/cw-001', extra: businessId);
      },
    );
  }
}

// --- S5 Rejected -----------------------------------------------------------

class _Rejected extends ConsumerWidget {
  final CustomerDiscoveryState state;
  final String businessId;
  const _Rejected({required this.state, required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cooldown = state.lastRequest?.cooldownUntil;
    return _ResultState(
      icon: Icons.cancel_outlined,
      iconColor: ManaColors.statusBad,
      title: 'request rejected',
      body: cooldown != null
          ? 'You may reapply to this Business after ${cooldown.toLocal()}.'
          : 'You may reapply to this Business after a 24-hour cooldown.',
      primaryLabel: 'search again',
      onPrimary: () => ref.read(customerDiscoveryProvider.notifier).reset(),
    );
  }
}

// --- shared result-state layout ------------------------------------------

class _ResultState extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;

  const _ResultState({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: iconColor),
            const SizedBox(height: ManaSpacing.md),
            ManaText(title, style: ManaType.sheetTitle),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(body, textAlign: TextAlign.center, style: ManaType.secondary),
            const SizedBox(height: ManaSpacing.lg),
            ElevatedButton(onPressed: onPrimary, child: ManaText(primaryLabel)),
          ],
        ),
      ),
    );
  }
}
