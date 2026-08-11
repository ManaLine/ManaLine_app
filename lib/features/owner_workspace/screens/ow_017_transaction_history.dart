import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';

final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dateFmt = DateFormat('dd MMM, hh:mm a');

/// OW-017 — Transaction History. NEW screen (extends beyond the original
/// locked OW inventory, per explicit request). Combines loans (money out),
/// collections (money in), and settlement adjustments (Short=out,
/// Excess=in) into one chronological, PhonePe-style timeline with a
/// running balance.
///
/// HONEST SCOPE NOTE: the "running balance" here starts at 0 and shows
/// the NET CUMULATIVE CHANGE across the transactions in view — it is
/// NOT cross-verified against a specific account_period's true opening
/// balance (that would require picking one specific period/agent
/// context, which this business-wide combined view deliberately doesn't
/// scope to). Labeled clearly in the UI as "Net Change," not claimed as
/// an authoritative cash-in-hand figure — treat this as a transaction
/// log with a running total, not a substitute for OW-006/AG-006's real
/// settlement reconciliation.
class TransactionHistoryScreen extends ConsumerStatefulWidget {
  final String businessId;
  const TransactionHistoryScreen({super.key, required this.businessId});

  @override
  ConsumerState<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

enum _TxnType { collection, loan, adjustmentExcess, adjustmentShort }

class _Txn {
  final String id;
  final _TxnType type;
  final double amount; // always positive; sign/color derived from type
  final DateTime timestamp;
  final String title;
  final Map<String, dynamic> raw;
  _Txn({required this.id, required this.type, required this.amount, required this.timestamp, required this.title, required this.raw});

  bool get isCredit => type == _TxnType.collection || type == _TxnType.adjustmentExcess;
}

class _TransactionHistoryScreenState extends ConsumerState<TransactionHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<_Txn> _transactions = [];
  final Map<String, double> _runningBalanceById = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = Supabase.instance.client;

      final collectionRows = await db
          .from('collections')
          .select('collection_id, collected_amount, entry_timestamp, loans!inner(business_id, loan_number)')
          .eq('loans.business_id', widget.businessId);

      final loanRows = await db
          .from('loans')
          .select('loan_id, loan_number, amount_given, entry_timestamp')
          .eq('business_id', widget.businessId);

      final adjustmentRows = await db
          .from('settlement_adjustments')
          .select('adjustment_id, adjustment_type, amount, business_date, '
              'account_settlements(account_periods(business_id))')
          .eq('account_settlements.account_periods.business_id', widget.businessId);

      final txns = <_Txn>[];

      for (final r in (collectionRows as List).cast<Map<String, dynamic>>()) {
        final loan = r['loans'] as Map<String, dynamic>?;
        txns.add(_Txn(
          id: 'c-${r['collection_id']}',
          type: _TxnType.collection,
          amount: (r['collected_amount'] as num).toDouble(),
          timestamp: DateTime.parse(r['entry_timestamp'] as String),
          title: 'Collection — ${loan?['loan_number'] ?? ''}',
          raw: r,
        ));
      }
      for (final r in (loanRows as List).cast<Map<String, dynamic>>()) {
        txns.add(_Txn(
          id: 'l-${r['loan_id']}',
          type: _TxnType.loan,
          amount: (r['amount_given'] as num).toDouble(),
          timestamp: DateTime.parse(r['entry_timestamp'] as String),
          title: 'Loan Distribution — ${r['loan_number']}',
          raw: r,
        ));
      }
      for (final r in (adjustmentRows as List).cast<Map<String, dynamic>>()) {
        final isExcess = r['adjustment_type'] == 'Excess';
        txns.add(_Txn(
          id: 'a-${r['adjustment_id']}',
          type: isExcess ? _TxnType.adjustmentExcess : _TxnType.adjustmentShort,
          amount: (r['amount'] as num).toDouble(),
          timestamp: DateTime.parse(r['business_date'] as String),
          title: 'Settlement Adjustment — ${r['adjustment_type']}',
          raw: r,
        ));
      }

      txns.sort((a, b) => a.timestamp.compareTo(b.timestamp)); // oldest first, to compute running balance forward
      double running = 0;
      for (final t in txns) {
        running += t.isCredit ? t.amount : -t.amount;
        _runningBalanceById[t.id] = running;
      }
      txns.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // display newest first

      if (!mounted) return;
      setState(() {
        _transactions = txns;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load transaction history.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final netChange = _transactions.isEmpty ? 0.0 : _runningBalanceById[_transactions.first.id] ?? 0.0;
    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('history')),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/ow-001', extra: widget.businessId)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: ManaText.raw(_error!, style: TextStyle(color: ManaColors.statusBad)))
                : RefreshIndicator(
                    onRefresh: _load,
                    // PERF: builder — this business's whole loan/collection/
                    // adjustment history, fetched with no limit, is genuinely
                    // unbounded over the life of the business. Index 0 is the
                    // fixed net-change header; the rest are transaction rows.
                    child: ListView.builder(
                      itemCount: 1 + (_transactions.isEmpty ? 1 : _transactions.length),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(ManaSpacing.lg),
                            color: ManaColors.surfaceSunken,
                            child: Column(
                              children: [
                                ManaText.raw(ref.t('net_change_this_view'),
                                    style: TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
                                const SizedBox(height: 4),
                                ManaText.raw(
                                  _currency.format(netChange),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: netChange >= 0 ? ManaColors.statusGood : ManaColors.statusBad,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        if (_transactions.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(ManaSpacing.xl),
                            child: Center(
                              child: ManaText.raw(ref.t('no_transactions_yet'),
                                  style: TextStyle(color: ManaColors.textSecondary)),
                            ),
                          );
                        }
                        final t = _transactions[i - 1];
                        return _TxnTile(
                          txn: t,
                          runningBalance: _runningBalanceById[t.id] ?? 0,
                          onTap: () => _showDetail(context, t),
                        );
                      },
                    ),
                  ),
      ),
    );
  }

  void _showDetail(BuildContext context, _Txn t) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(t.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw('${t.isCredit ? '+' : '-'}${_currency.format(t.amount)}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: t.isCredit ? ManaColors.statusGood : ManaColors.statusBad,
                )),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(_dateFmt.format(t.timestamp), style: TextStyle(color: ManaColors.textSecondary)),
            const SizedBox(height: ManaSpacing.md),
            const Divider(),
            ...t.raw.entries
                .where((e) => e.value is! Map)
                .map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ManaText.raw(e.key, style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
                          ManaText.raw('${e.value}', style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    )),
          ],
        ),
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final _Txn txn;
  final double runningBalance;
  final VoidCallback onTap;
  const _TxnTile({required this.txn, required this.runningBalance, required this.onTap});

  IconData get _icon {
    switch (txn.type) {
      case _TxnType.collection:
        return Icons.arrow_downward;
      case _TxnType.loan:
        return Icons.arrow_upward;
      case _TxnType.adjustmentExcess:
        return Icons.add_circle_outline;
      case _TxnType.adjustmentShort:
        return Icons.remove_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = txn.isCredit ? ManaColors.statusGood : ManaColors.statusBad;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(_icon, color: color, size: 20),
      ),
      title: ManaText.raw(txn.title, style: const TextStyle(fontSize: 14)),
      subtitle: ManaText.raw(_dateFmt.format(txn.timestamp), style: const TextStyle(fontSize: 13)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ManaText.raw(
            '${txn.isCredit ? '+' : '-'}${_currency.format(txn.amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          ManaText.raw(
            _currency.format(runningBalance),
            style: TextStyle(color: ManaColors.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
