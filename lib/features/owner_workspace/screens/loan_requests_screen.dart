import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_card.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../state/loan_wizard_state.dart';
import 'package:mana_line/design/components/mana_amount.dart';


/// Owner-side review queue for CW-003's "Request New Loan" — not part of
/// the original locked screen inventory (no OW-0xx number), added to
/// close a real gap: loan_requests had a real INSERT path from the
/// Customer side but nothing anywhere ever read it back, so every
/// request sat Pending forever with no way for an Owner to ever see or
/// act on it. Approve hands off to OW-005 (New Loan Workflow) pre-filled
/// with the requesting customer — this screen doesn't create the loan
/// itself, since the real eligibility/BF-cash/guarantor/live-photo flow
/// already lives there and shouldn't be duplicated.
class LoanRequestsScreen extends ConsumerStatefulWidget {
  final String businessId;
  const LoanRequestsScreen({super.key, required this.businessId});

  @override
  ConsumerState<LoanRequestsScreen> createState() => _LoanRequestsScreenState();
}

class _LoanRequestsScreenState extends ConsumerState<LoanRequestsScreen> {
  late Future<List<LoanRequestSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<LoanRequestSummary>> _load() {
    return ref.read(loanApiServiceProvider).fetchLoanRequests(businessId: widget.businessId);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _approve(LoanRequestSummary r) async {
    context.push('/ow-005?customerId=${r.customerId}&requestId=${r.requestId}', extra: widget.businessId);
  }

  Future<void> _reject(LoanRequestSummary r) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: ManaText.raw(ref.t('reject_loan_request')),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(labelText: ref.t('reason_field')),
          maxLines: 3,
        ),
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
      await ref.read(loanApiServiceProvider).rejectLoanRequest(requestId: r.requestId, reason: reason);
      return true;
    });
    if (ok == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('loan_requests')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: FutureBuilder<List<LoanRequestSummary>>(
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
                      child: ManaText.raw(ref.t('could_not_load_loan_requests_note').replaceAll('{error}', '${snapshot.error}'),
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
                      child: ManaText.raw(ref.t('no_pending_loan_requests'), style: ManaType.secondary),
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
                                      child: ManaText.raw(r.customerName,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                    ),
                                    ManaText.raw(manaRupees(r.requestedAmount),
                                        style: ManaType.cardTitle),
                                  ],
                                ),
                                ManaText.raw(r.customerMlid,
                                    style: ManaType.note),
                                if (r.purposeRemark != null && r.purposeRemark!.isNotEmpty) ...[
                                  const SizedBox(height: ManaSpacing.xs),
                                  ManaText.raw(r.purposeRemark!, style: ManaType.small),
                                ],
                                const SizedBox(height: ManaSpacing.xs),
                                ManaText.raw('Requested ${DateFormat('d MMM yyyy').format(r.createdAt)}',
                                    style: ManaType.note),
                                const SizedBox(height: ManaSpacing.sm),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _reject(r),
                                        child: ManaText.raw(ref.t('reject')),
                                      ),
                                    ),
                                    const SizedBox(width: ManaSpacing.sm),
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: () => _approve(r),
                                        child: ManaText.raw(ref.t('approve')),
                                      ),
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
