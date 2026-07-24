import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../login_registration/state/auth_flow_state.dart';
import '../state/owner_api_service.dart';
import '../state/owner_workspace_state.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// OW-001 — Owner Home Dashboard. Read-only aggregation screen; every write
/// happens on the destination screens its Quick Actions/cards link to (per
/// spec's own DATA MODEL TOUCHED note). Polling refresh every 15-30s per
/// the cross-cutting live-update decision — this scaffold polls on a timer
/// rather than websockets, matching the locked API BINDING.
class OwnerHomeDashboardScreen extends ConsumerStatefulWidget {
  final String businessId;
  const OwnerHomeDashboardScreen({super.key, required this.businessId});

  @override
  ConsumerState<OwnerHomeDashboardScreen> createState() => _OwnerHomeDashboardScreenState();
}

class _OwnerHomeDashboardScreenState extends ConsumerState<OwnerHomeDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(ownerDashboardProvider.notifier).load(widget.businessId);
    });
  }

  Future<void> _refresh() => ref.read(ownerDashboardProvider.notifier).load(widget.businessId);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ownerDashboardProvider);

    return Scaffold(
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _errorState(e),
          data: (data) => RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: ManaSpacing.xxl),
              children: [
                _Header(businessName: data.businessName, businessOpen: data.businessOpen),
                _BusinessStatusBar(data: data),
                const SizedBox(height: ManaSpacing.md),
                _SectionCard(
                  title: "today's business summary",
                  child: _TodaysSummary(data: data),
                ),
                _SectionCard(
                  title: 'quick actions',
                  child: _QuickActions(businessId: widget.businessId),
                ),
                _SectionCard(
                  title: 'live business activity',
                  onSeeAll: data.liveActivity.isEmpty ? null : () {},
                  child: _LiveActivity(items: data.liveActivity),
                ),
                _SectionCard(
                  title: 'attention required',
                  child: _AttentionRequired(cards: data.attentionRequired),
                ),
                _SectionCard(
                  title: 'business overview',
                  child: _BusinessOverview(data: data),
                ),
                _SectionCard(
                  title: 'workforce snapshot',
                  onSeeAll: () => context.go('/ow-002'),
                  child: _WorkforceSnapshot(data: data),
                ),
                _SectionCard(
                  title: 'investor snapshot',
                  onSeeAll: () => context.go('/ow-003'),
                  child: _InvestorSnapshot(data: data),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const _FooterNav(),
    );
  }

  Widget _errorState(Object e) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('could not load dashboard'),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(onPressed: _refresh, child: const ManaText('retry')),
          ],
        ),
      ),
    );
  }
}

// --- C1 Header ---------------------------------------------------------

class _Header extends ConsumerWidget {
  final String businessName;
  final bool businessOpen;
  const _Header({required this.businessName, required this.businessOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    return Container(
      color: ManaColors.surface,
      padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, ManaSpacing.md),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: ManaColors.inkFaint,
            child: Icon(Icons.storefront, color: ManaColors.ink),
          ),
          const SizedBox(width: ManaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(businessName.isEmpty ? 'Business' : businessName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ManaText.raw(DateFormat('EEE, d MMM').format(now),
                    style: const TextStyle(fontSize: 12, color: ManaColors.textSecondary)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          IconButton(
            tooltip: 'Universal Search',
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'switch_business':
                  context.go('/lr-012');
                case 'switch_role':
                  context.go('/lr-013');
                case 'profile':
                  break;
                case 'logout':
                  ref.read(authFlowProvider.notifier).reset();
                  context.go('/lr-003');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: ManaText('profile')),
              PopupMenuItem(value: 'switch_business', child: ManaText('switch workspace')),
              PopupMenuItem(value: 'switch_role', child: ManaText('switch role')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'logout', child: ManaText('logout')),
            ],
          ),
        ],
      ),
    );
  }
}

// --- C2 Business Status Bar ---------------------------------------------

class _BusinessStatusBar extends StatelessWidget {
  final OwnerDashboardData data;
  const _BusinessStatusBar({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ManaColors.surface,
      padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.md),
      child: Wrap(
        spacing: ManaSpacing.sm,
        runSpacing: ManaSpacing.sm,
        children: [
          ManaStatusPill(
            label: data.businessOpen ? 'Open' : 'Closed',
            status: data.businessOpen ? ManaStatus.good : ManaStatus.bad,
          ),
          if (data.pendingApprovals > 0)
            ManaStatusPill(label: '${data.pendingApprovals} Approvals', status: ManaStatus.warn),
          if (data.pendingInvitations > 0)
            ManaStatusPill(label: '${data.pendingInvitations} Invitations', status: ManaStatus.warn),
          if (data.pendingAcceptances > 0)
            ManaStatusPill(label: '${data.pendingAcceptances} Acceptances', status: ManaStatus.warn),
          if (data.pendingDayClosure)
            const ManaStatusPill(label: 'Day Closure Pending', status: ManaStatus.bad),
        ],
      ),
    );
  }
}

// --- Shared section wrapper ------------------------------------------------

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onSeeAll;
  const _SectionCard({required this.title, required this.child, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, ManaSpacing.md, ManaSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: ManaText(title, style: Theme.of(context).textTheme.titleMedium)),
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: const ManaText('see all')),
            ],
          ),
          const SizedBox(height: ManaSpacing.sm),
          child,
        ],
      ),
    );
  }
}

// --- C3 Today's Business Summary --------------------------------------------

class _TodaysSummary extends StatelessWidget {
  final OwnerDashboardData data;
  const _TodaysSummary({required this.data});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, double, bool)>[
      ('Opening Balance', data.openingBalance, false),
      ("Today's Collections", data.todaysCollections, false),
      ("Today's Loan Distribution", data.todaysLoanDistribution, false),
      ("Today's Investments", data.todaysInvestments, false),
      ("Today's Withdrawals", data.todaysWithdrawals, false),
      ("Today's Expenses", data.todaysExpenses, false),
      ("Today's Outstanding", data.todaysOutstanding, false),
      ("Today's Difference", data.todaysDifference, true),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          children: [
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: ManaText.raw(r.$1, style: const TextStyle(fontSize: 13))),
                      ManaText.raw(
                        _currency.format(r.$2),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: r.$3 && r.$2 < 0 ? ManaColors.statusBad : ManaColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                )),
            const Divider(height: ManaSpacing.lg),
            Row(
              children: [
                const Expanded(
                  child: ManaText('live closing balance', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ManaText.raw(
                  _currency.format(data.liveClosingBalance),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: ManaColors.brass),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// --- C4 Quick Actions --------------------------------------------------

class _QuickActions extends StatelessWidget {
  final String businessId;
  const _QuickActions({required this.businessId});

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, String)>[
      (Icons.person_add_outlined, 'New Customer', '/ow-004'),
      (Icons.request_quote_outlined, 'New Loan', '/ow-005'),
      (Icons.point_of_sale_outlined, 'Collection Mode', '/ow-006'),
      (Icons.people_outline, 'Customer Management', '/ow-004'),
      (Icons.badge_outlined, 'Workforce Management', '/ow-002'),
      (Icons.savings_outlined, 'Investor Management', '/ow-003'),
      (Icons.bar_chart_outlined, 'Reports', '/ow-010'),
      (Icons.menu_book_outlined, 'Daily Record Book', '/ow-009'),
      (Icons.lock_clock_outlined, 'Day Closure', '/ow-011'),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: ManaSpacing.sm,
        crossAxisSpacing: ManaSpacing.sm,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (context, i) {
        final (icon, label, route) = actions[i];
        return Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go(route),
            child: Padding(
              padding: const EdgeInsets.all(ManaSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: ManaColors.brass),
                  const SizedBox(height: ManaSpacing.xs),
                  ManaText(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- C5 Live Business Activity --------------------------------------------

class _LiveActivity extends StatelessWidget {
  final List<ActivityItem> items;
  const _LiveActivity({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(ManaSpacing.lg),
          child: ManaText.raw('No activity yet today.', style: TextStyle(color: ManaColors.textSecondary)),
        ),
      );
    }
    return Card(
      child: Column(
        children: items
            .take(5)
            .map((a) => ListTile(
                  leading: const Icon(Icons.circle, size: 8, color: ManaColors.brass),
                  title: ManaText.raw(a.label, style: const TextStyle(fontSize: 13)),
                  trailing: ManaText.raw(DateFormat('hh:mm a').format(a.timestamp),
                      style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
                ))
            .toList(),
      ),
    );
  }
}

// --- C6 Attention Required --------------------------------------------

class _AttentionRequired extends StatelessWidget {
  final List<AttentionCard> cards;
  const _AttentionRequired({required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(ManaSpacing.lg),
          child: ManaText.raw('Nothing needs attention right now.', style: TextStyle(color: ManaColors.textSecondary)),
        ),
      );
    }
    return Column(
      children: cards
          .map((c) => Card(
                child: ListTile(
                  leading: Icon(Icons.priority_high,
                      color: c.priority == 'High' ? ManaColors.statusBad : ManaColors.statusWarn),
                  title: ManaText.raw(c.type, style: const TextStyle(fontSize: 13)),
                  subtitle: ManaText.raw('Updated ${DateFormat('d MMM, hh:mm a').format(c.lastUpdated)}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: ManaStatusPill(
                    label: '${c.count}',
                    status: c.priority == 'High' ? ManaStatus.bad : ManaStatus.warn,
                  ),
                  onTap: () {},
                ),
              ))
          .toList(),
    );
  }
}

// --- C7 Business Overview --------------------------------------------

class _BusinessOverview extends StatelessWidget {
  final OwnerDashboardData data;
  const _BusinessOverview({required this.data});

  @override
  Widget build(BuildContext context) {
    final metrics = <(String, String)>[
      ('Total Customers', '${data.totalCustomers}'),
      ('Active Customers', '${data.activeCustomers}'),
      ('Active Loans', '${data.activeLoans}'),
      ("Today's Due", '${data.todaysDueCustomers}'),
      ('Collected Today', _currency.format(data.collectedToday)),
      ('Pending Collections', _currency.format(data.pendingCollections)),
      ('Penalty Customers', '${data.penaltyCustomers}'),
      ('Grace Period', '${data.gracePeriodCustomers}'),
      ('Active Agents', '${data.activeAgents}'),
      ('Active Investors', '${data.activeInvestors}'),
      ('Total Investment', _currency.format(data.totalInvestment)),
      ('Interest Payable', _currency.format(data.interestPayable)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: ManaSpacing.sm,
        crossAxisSpacing: ManaSpacing.sm,
        childAspectRatio: 2.4,
      ),
      itemBuilder: (context, i) {
        final (label, value) = metrics[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ManaText(label, style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- C8 Workforce Snapshot --------------------------------------------

class _WorkforceSnapshot extends StatelessWidget {
  final OwnerDashboardData data;
  const _WorkforceSnapshot({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Wrap(
          spacing: ManaSpacing.lg,
          runSpacing: ManaSpacing.sm,
          children: [
            _stat('Total Agents', '${data.workforceTotalAgents}'),
            _stat('Active Today', '${data.workforceActiveToday}'),
            _stat('Pending Invitations', '${data.workforcePendingInvitations}'),
            _stat('Pending Acceptance', '${data.workforcePendingAcceptance}'),
            _stat('Disabled', '${data.workforceDisabled}'),
            _stat('Suspended', '${data.workforceSuspended}'),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ManaText(label, style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
        ],
      );
}

// --- C9 Investor Snapshot --------------------------------------------

class _InvestorSnapshot extends StatelessWidget {
  final OwnerDashboardData data;
  const _InvestorSnapshot({required this.data});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Wrap(
          spacing: ManaSpacing.lg,
          runSpacing: ManaSpacing.sm,
          children: [
            _stat('Total Investors', '${data.investorTotal}'),
            _stat('Active Investors', '${data.investorActive}'),
            _stat('Pending Invitations', '${data.investorPendingInvitations}'),
            _stat('Pending Acceptance', '${data.investorPendingAcceptance}'),
            _stat('Investment Balance', _currency.format(data.investorBalance)),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ManaText(label, style: const TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
        ],
      );
}

// --- C11 Footer Navigation --------------------------------------------

class _FooterNav extends StatelessWidget {
  const _FooterNav();

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.people_outline), label: 'Customers'),
        NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'Collections'),
        NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Reports'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ],
      onDestinationSelected: (i) {
        switch (i) {
          case 1:
            context.go('/ow-004');
          case 2:
            context.go('/ow-006');
          case 3:
            context.go('/ow-010');
          case 4:
            context.go('/ow-012');
        }
      },
    );
  }
}
