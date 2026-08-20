import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../state/withdrawal_request_state.dart';

final _moneyFormat =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// IW-004 — Request Withdrawal. Entered with a specific investment
/// pre-selected from IW-003 (or from IW-001 → Select Business → Select
/// Investment) — investment selection is always mandatory before this
/// screen, per IW-004.md ENTRY POINT.
class RequestWithdrawalScreen extends ConsumerStatefulWidget {
  final String investmentId;

  /// Optional snapshot handed off from IW-003 so the balance can render
  /// immediately while the fresh fetch is in flight — see
  /// withdrawal_request_state.dart's integration note re: InvestmentSummary.
  final InvestmentSummary? investmentSnapshot;

  const RequestWithdrawalScreen({
    super.key,
    required this.investmentId,
    this.investmentSnapshot,
  });

  @override
  ConsumerState<RequestWithdrawalScreen> createState() =>
      _RequestWithdrawalScreenState();
}

class _RequestWithdrawalScreenState
    extends ConsumerState<RequestWithdrawalScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(withdrawalRequestProvider.notifier).loadInvestment(
            investmentId: widget.investmentId,
            fallbackSnapshot: widget.investmentSnapshot,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(withdrawalRequestProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/iw-001')),
        title: ManaText.raw(ref.t('request_withdrawal_title')),
      ),
      body: SafeArea(
        child: state.loadingInvestment && state.investment == null
            ? const Center(child: CircularProgressIndicator())
            : state.investment == null
                ? _ErrorState(message: state.error)
                : _WithdrawalForm(
                    investment: state.investment!,
                    disabled: state.withdrawDisabled),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String? message;
  const _ErrorState({this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: ManaText.raw(
          message ?? 'Could not load this investment.',
          textAlign: TextAlign.center,
          style: ManaType.bad,
        ),
      ),
    );
  }
}

class _WithdrawalForm extends ConsumerStatefulWidget {
  final InvestmentSummary investment;
  final bool disabled;
  const _WithdrawalForm({required this.investment, required this.disabled});

  @override
  ConsumerState<_WithdrawalForm> createState() => _WithdrawalFormState();
}

class _WithdrawalFormState extends ConsumerState<_WithdrawalForm> {
  WithdrawalType? _withdrawalType;
  final _amountController = TextEditingController();
  final _remarksController = TextEditingController();
  String? _amountError;

  @override
  void dispose() {
    _amountController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  int? get _requestedAmount =>
      int.tryParse(_amountController.text.trim());

  bool get _canSubmit {
    if (widget.disabled) return false;
    if (_withdrawalType == null) return false;
    final amount = _requestedAmount;
    if (amount == null || amount <= 0) return false;
    if (amount > widget.investment.availableBalance) return false;
    return true;
  }

  void _validateAmount() {
    final amount = _requestedAmount;
    setState(() {
      if (_amountController.text.trim().isEmpty) {
        _amountError = null;
      } else if (amount == null || amount <= 0) {
        _amountError = 'Enter a valid amount';
      } else if (amount > widget.investment.availableBalance) {
        _amountError = 'Cannot exceed Available Balance';
      } else {
        _amountError = null;
      }
    });
  }

  Future<void> _submit() async {
    final type = _withdrawalType;
    final amount = _requestedAmount;
    if (type == null || amount == null) return;

    final record = await NetworkErrorHandler.run(context, () async {
      final r = await ref.read(withdrawalRequestProvider.notifier).submit(
            withdrawalType: type,
            requestedAmount: amount,
            remarks: _remarksController.text.trim().isEmpty
                ? null
                : _remarksController.text.trim(),
          );
      if (r == null) throw Exception('Could not submit withdrawal request');
      return r;
    });
    if (record == null) return; // failed — error already shown, stay put
    if (!mounted) return;

    // S2 — Submitted. Per NAVIGATION: returns to IW-003 Investment Detail
    // View. This screen doesn't own IW-003, so it just pops/goes back;
    // the caller route wires the actual destination (see integration note).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              ManaText.raw(ref.t('withdrawal_submitted_note'))),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/iw-003');
    }
  }

  @override
  Widget build(BuildContext context) {
    final investment = widget.investment;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(ref.t('selected_investment'),
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: ManaSpacing.xs),
                ManaText.raw(
                  investment.investmentId,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: ManaSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ManaText.raw(ref.t('available_balance')),
                    ManaText.raw(
                      _moneyFormat.format(investment.availableBalance),
                      style: ManaTypography.amount(),
                    ),
                  ],
                ),
                const SizedBox(height: ManaSpacing.xs),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ManaText.raw(ref.t('principal_amount'),
                        style: Theme.of(context).textTheme.bodySmall),
                    ManaText.raw(
                      _moneyFormat.format(investment.principalAmount),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (widget.disabled) ...[
                  const SizedBox(height: ManaSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(ManaSpacing.sm),
                    decoration: BoxDecoration(
                      color: ManaColors.statusWarnFaint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ManaText.raw(
                      'Available Balance is below ₹1.00 — withdrawal requests are disabled.',
                      style:
                          ManaType.noteWarn,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(ref.t('withdrawal_type'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ManaSpacing.sm),
        // Checkmark-ListTile selection pattern (Radio/RadioListTile
        // deprecated in this SDK version — per shared convention).
        ...WithdrawalType.values.map((type) {
          final selected = _withdrawalType == type;
          return Card(
            margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
            child: ListTile(
              enabled: !widget.disabled,
              leading: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? ManaColors.brand : ManaColors.textSecondary,
              ),
              title: ManaText(type.label),
              onTap: widget.disabled
                  ? null
                  : () => setState(() => _withdrawalType = type),
            ),
          );
        }),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(ref.t('requested_amount'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _amountController,
          enabled: !widget.disabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            prefixText: '₹ ',
            labelText: ref.t('requested_amount_field'),
            errorText: _amountError,
          ),
          onChanged: (_) => _validateAmount(),
        ),
        const SizedBox(height: ManaSpacing.lg),
        ManaText.raw(ref.t('remarks'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ManaSpacing.sm),
        TextField(
          controller: _remarksController,
          enabled: !widget.disabled,
          maxLines: 3,
          decoration: InputDecoration(labelText: ref.t('remarks_optional_field')),
        ),
        const SizedBox(height: ManaSpacing.xl),
        Consumer(
          builder: (context, ref, _) {
            final submitting = ref.watch(withdrawalRequestProvider).submitting;
            return ElevatedButton(
              onPressed: (_canSubmit && !submitting) ? _submit : null,
              child: submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('submit_request')),
            );
          },
        ),
      ],
    );
  }
}
