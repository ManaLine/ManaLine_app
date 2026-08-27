import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_card.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../state/investor_state.dart';


/// Owner-side review queue for IW-004's "Request Withdrawal" — not part
/// of the original locked screen inventory (no OW-0xx number), added to
/// close a real gap: investment_withdrawal_requests had a real INSERT
/// path from the Investor side (and from the Owner's own "request
/// withdrawal" shortcut) but nothing anywhere ever paid one out or
/// rejected it — every request sat Pending forever.
class WithdrawalRequestsScreen extends ConsumerStatefulWidget {
  final String businessId;
  const WithdrawalRequestsScreen({super.key, required this.businessId});

  @override
  ConsumerState<WithdrawalRequestsScreen> createState() => _WithdrawalRequestsScreenState();
}

class _WithdrawalRequestsScreenState extends ConsumerState<WithdrawalRequestsScreen> {
  late Future<List<WithdrawalRequestSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<WithdrawalRequestSummary>> _load() {
    return ref.read(investorApiServiceProvider).fetchWithdrawalRequests(businessId: widget.businessId);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _reject(WithdrawalRequestSummary r) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: ManaText.raw(ref.t('reject_withdrawal_request')),
        content: TextField(controller: reasonController, decoration: InputDecoration(labelText: ref.t('reason_field')), maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(reasonController.text.trim()),
            child: ManaText.raw(ref.t('reject')),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(investorApiServiceProvider).rejectWithdrawalRequest(requestId: r.requestId, reason: reason);
      return true;
    });
    if (ok == true) _reload();
  }

  Future<void> _approve(WithdrawalRequestSummary r) async {
    final principalController = TextEditingController(text: r.requestedAmount.toStringAsFixed(0));
    final interestController = TextEditingController(text: '0');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          // Scrolls if it does not fit -- see ow_011_day_closure.dart.
          scrollable: true,
          title: ManaText.raw(ref.t('pay_out_withdrawal')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ManaText.raw(ref
                  .t('requested_amount_type_note')
                  .replaceAll('{amount}', manaRupees(r.requestedAmount))
                  .replaceAll('{type}', r.withdrawalType),
                  style: TextStyle(fontSize: 16, color: ManaColors.textSecondary)),
              const SizedBox(height: ManaSpacing.md),
              TextField(
                controller: principalController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: ref.t('principal_portion_field')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.sm),
              TextField(
                controller: interestController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: ref.t('interest_portion_field')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(
                ref.t('total_note').replaceAll('{amount}', manaRupees((double.tryParse(principalController.text) ?? 0) + (double.tryParse(interestController.text) ?? 0))),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: ManaText.raw(ref.t('cancel'))),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: ManaText.raw(ref.t('pay_out'))),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final principal = int.tryParse(principalController.text.trim());
    final interest = int.tryParse(interestController.text.trim());
    if (principal == null || interest == null) return;
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(investorApiServiceProvider).approveWithdrawalRequest(
            requestId: r.requestId,
            investmentId: r.investmentId,
            withdrawalType: r.withdrawalType,
            amount: principal + interest, // whole rupees (M8)
            principalPortion: principal,
            interestPortion: interest,
          );
      return true;
    });
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('withdrawal_requests_title')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: FutureBuilder<List<WithdrawalRequestSummary>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                // Card-shaped placeholders matching the request rows below,
                // rather than a spinner on an empty screen.
                return const ManaSkeletonList(itemHeight: 152);
              }
              if (snapshot.hasError) {
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(ManaSpacing.lg),
                      child: ManaText.raw(ref.t('could_not_load_withdrawal_requests_note').replaceAll('{error}', '${snapshot.error}'),
                          textAlign: TextAlign.center, style: ManaType.noteBad),
                    ),
                  ],
                );
              }
              final requests = snapshot.data ?? const [];
              if (requests.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.all(ManaSpacing.xxl),
                  children: [
                    Center(
                      child: ManaText.raw(ref.t('no_pending_withdrawal_requests'), style: ManaType.secondary),
                    ),
                  ],
                );
              }
              return ListView(
                padding: const EdgeInsets.all(ManaSpacing.lg),
                children: requests
                    .map((r) => ManaCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: ManaText.raw(r.investorName,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                    ),
                                    ManaText.raw(manaRupees(r.requestedAmount),
                                        style: ManaType.cardTitle),
                                  ],
                                ),
                                ManaText.raw('${r.investorMlid} · ${r.withdrawalType}',
                                    style: ManaType.note),
                                if (r.remarks != null && r.remarks!.isNotEmpty) ...[
                                  const SizedBox(height: ManaSpacing.xs),
                                  ManaText.raw(r.remarks!, style: ManaType.small),
                                ],
                                const SizedBox(height: ManaSpacing.xs),
                                ManaText.raw('Requested ${DateFormat('d MMM yyyy').format(r.createdAt)}',
                                    style: ManaType.note),
                                const SizedBox(height: ManaSpacing.sm),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(onPressed: () => _reject(r), child: ManaText.raw(ref.t('reject'))),
                                    ),
                                    const SizedBox(width: ManaSpacing.sm),
                                    Expanded(
                                      child: FilledButton(onPressed: () => _approve(r), child: ManaText.raw(ref.t('pay_out'))),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                        ))
                    .toList(),
              );
            },
          ),
        ),
      ),
    );
  }
}
