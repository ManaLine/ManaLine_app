import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/components/mana_amount.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../shared/translation_service.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../design/components/mana_card.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/soft_delete_service.dart';
import '../../../shared/widgets/confirm_delete_dialog.dart';
import '../state/cheti_state.dart';
import '../../../design/components/mana_info_hint.dart';

final _dateFmt = DateFormat('d MMM yyyy');

/// OW-019 — Cheti Management.
///
/// A cheti is the Owner's own chit fund, held as an ASSET rather than an
/// expense: instalments paid in come back as an availed lumpsum. See
/// migration 20260801192125_add_chetis.sql for why that reverses BR-061.
class ChetiManagementScreen extends ConsumerStatefulWidget {
  final String businessId;
  const ChetiManagementScreen({super.key, required this.businessId});

  @override
  ConsumerState<ChetiManagementScreen> createState() => _ChetiManagementScreenState();
}

class _ChetiManagementScreenState extends ConsumerState<ChetiManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() =>
      ref.read(chetiListProvider.notifier).load(widget.businessId);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chetiListProvider);
    return Scaffold(
      appBar: AppBar(title: ManaText.raw(ref.t('cheti'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: ManaText.raw(ref.t('add_cheti')),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: state.loading && state.chetis.isEmpty
              ? const ManaSkeletonList()
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    _summary(state),
                    const SizedBox(height: ManaSpacing.lg),
                    if (state.chetis.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: ManaText.raw(
                          ref.t('no_chetis_yet_note'),
                          textAlign: TextAlign.center,
                          style: ManaType.secondary,
                        ),
                      ),
                    ...state.chetis.map(_card),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _summary(ChetiListState state) {
    final net = state.totalNetPosition;
    return Card(
      color: ManaColors.inkFaint,
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: ManaText.raw(ref.t('cheti_net_position'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ManaType.note),
            ),
            const SizedBox(width: ManaSpacing.xs),
            ManaText.raw(
              manaRupees(net),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                // Negative means more has been availed than paid in, so the
                // remaining instalments are a liability rather than an asset.
                color: net < 0 ? ManaColors.statusBad : ManaColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Cheti c) {
    final net = c.netPosition;
    return ManaCard(
      gap: ManaSpacing.md,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Both sides flexible: a long cheti name and the type/frequency
            // label are each free-form width, and a bare Text beside an
            // Expanded is the exact shape that overflowed LR-013.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ManaText.raw(c.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                const SizedBox(width: ManaSpacing.sm),
                Flexible(
                  child: ManaText.raw(
                    '${c.type.dbValue} · ${c.frequency.dbValue}',
                    textAlign: TextAlign.end,
                    style: ManaType.fine,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.sm),
            Wrap(
              spacing: ManaSpacing.lg,
              runSpacing: ManaSpacing.xs,
              children: [
                _figure(ref.t('face_value'), manaRupees(c.faceValue)),
                _figure(
                    ref.t('instalments'),
                    ref
                        .t('instalments_x_of_y')
                        .replaceAll('{paid}', '${c.instalmentsPaid}')
                        .replaceAll('{total}', '${c.totalInstalments}')),
                _figure(ref.t('paid_in'), manaRupees(c.totalPaid)),
                if (c.isAvailed)
                  _figure(ref.t('availed'), manaRupees(c.totalReceived)),
                _figure(ref.t('net_position'), manaRupees(net),
                    warn: net < 0),
                if (c.finalProfit != null)
                  _figure(ref.t('final_profit'), manaRupees(c.finalProfit!),
                      warn: c.finalProfit! < 0),
              ],
            ),
            if (c.isAvailed)
              Padding(
                padding: const EdgeInsets.only(top: ManaSpacing.xs),
                child: ManaText.raw(
                  ref.t('availed_on_note').replaceAll('{date}', _dateFmt.format(c.availedDate!)) +
                      (c.availedPreMigration ? ref.t('before_migration_suffix') : '') +
                      (c.instalmentsRemaining > 0
                          ? ref
                              .t('instalments_still_to_pay_suffix')
                              .replaceAll('{count}', '${c.instalmentsRemaining}')
                          : ''),
                  style: ManaType.fine,
                ),
              ),
            const SizedBox(height: ManaSpacing.sm),
            // Wrap, not Row: the two labels come from ui_translations and
            // together overflowed a 360dp phone by 213px even at 1.0x, before
            // any translation or font scaling. Caught by the layout test.
            Wrap(
              spacing: ManaSpacing.sm,
              children: [
                if (c.instalmentsRemaining > 0)
                  TextButton.icon(
                    onPressed: () => _openPayment(c),
                    icon: const Icon(Icons.south_west, size: 18),
                    label: ManaText.raw(ref.t('record_payment')),
                  ),
                if (!c.isAvailed)
                  TextButton.icon(
                    onPressed: () => _openAvailing(c),
                    icon: const Icon(Icons.north_east, size: 18),
                    label: ManaText.raw(ref.t('record_availing')),
                  ),
                TextButton.icon(
                  onPressed: () => _deleteCheti(c),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  style: TextButton.styleFrom(
                      foregroundColor: ManaColors.statusBad),
                  label: ManaText.raw(ref.t('delete')),
                ),
              ],
            ),
            // Collapsed by default: most of the time the aggregate above is
            // what the Owner wants, and this list exists so a single wrong
            // instalment can be corrected without deleting the whole chit.
            if (c.payments.isNotEmpty)
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: ManaText.raw(
                    ref
                        .t(c.payments.length == 1
                            ? 'recorded_instalment_note'
                            : 'recorded_instalments_note')
                        .replaceAll('{count}', '${c.payments.length}'),
                    style: TextStyle(
                        fontSize: 13, color: ManaColors.textSecondary),
                  ),
                  children: [
                    for (final p in c.payments)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: ManaText.raw(manaRupees(p.netPaid)),
                        subtitle: ManaText.raw(
                          _dateFmt.format(p.businessDate),
                          style: TextStyle(
                              fontSize: 12, color: ManaColors.textSecondary),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: ManaColors.statusBad,
                          tooltip: ref.t('delete'),
                          onPressed: () => _deleteChetiPayment(c, p),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),

    );
  }

  Widget _figure(String label, String value, {bool warn = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(label,
              style: TextStyle(fontSize: 11, color: ManaColors.textSecondary)),
          ManaText.raw(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: warn ? ManaColors.statusBad : ManaColors.textPrimary)),
        ],
      );

  Future<void> _openEditor() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChetiEditorSheet(businessId: widget.businessId),
    );
    if (saved == true) await _reload();
  }

  Future<void> _openPayment(Cheti c) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PaymentSheet(cheti: c, businessId: widget.businessId),
    );
    if (saved == true) await _reload();
  }

  Future<void> _openAvailing(Cheti c) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AvailingSheet(cheti: c),
    );
    if (saved == true) await _reload();
  }

  /// Deleting the cheti hides the whole chit: its availed lumpsum stops
  /// counting as cash received. Its instalment payments are separate rows
  /// and are NOT deleted with it — they are removed individually from the
  /// payments list, so a mistyped chit does not silently take a month of
  /// correct instalments with it.
  Future<void> _deleteCheti(Cheti c) async {
    final deleted = await ConfirmDeleteDialog.show(
      context,
      entity: DeletableEntity.cheti,
      recordId: c.chetiId,
      description: 'Cheti ${c.name} — ${manaRupees(c.faceValue)}',
    );
    if (deleted && mounted) await _reload();
  }

  /// One instalment. Deleting it returns that cash to whoever paid it and
  /// reopens the slot, so the term can be re-recorded correctly.
  Future<void> _deleteChetiPayment(Cheti c, ChetiPaymentRow p) async {
    final deleted = await ConfirmDeleteDialog.show(
      context,
      entity: DeletableEntity.chetiPayment,
      recordId: p.paymentId,
      description: '${c.name} instalment — ${manaRupees(p.netPaid)} '
          'on ${_dateFmt.format(p.businessDate)}',
    );
    if (deleted && mounted) await _reload();
  }
}

// ============================================================================
// Add a cheti — new, or already part-way through
// ============================================================================

class _ChetiEditorSheet extends ConsumerStatefulWidget {
  final String businessId;
  const _ChetiEditorSheet({required this.businessId});
  @override
  ConsumerState<_ChetiEditorSheet> createState() => _ChetiEditorSheetState();
}

class _ChetiEditorSheetState extends ConsumerState<_ChetiEditorSheet> {
  final _name = TextEditingController();
  final _faceValue = TextEditingController();
  final _total = TextEditingController();
  final _instalment = TextEditingController();
  final _openingCount = TextEditingController(text: '0');
  final _openingPaid = TextEditingController(text: '0');
  final _availedAmount = TextEditingController();

  ChetiType _type = ChetiType.auction;
  ChetiFrequency _frequency = ChetiFrequency.monthly;
  DateTime _startDate = DateTime.now();
  bool _alreadyAvailed = false;
  DateTime _availedDate = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _faceValue.dispose();
    _total.dispose();
    _instalment.dispose();
    _openingCount.dispose();
    _openingPaid.dispose();
    _availedAmount.dispose();
    for (final c in [
      _name, _faceValue, _total, _instalment,
      _openingCount, _openingPaid, _availedAmount,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _faceV => int.tryParse(_faceValue.text.trim());
  int? get _totalV => int.tryParse(_total.text.trim());
  int? get _instV => int.tryParse(_instalment.text.trim());
  int get _openCountV => int.tryParse(_openingCount.text.trim()) ?? 0;
  int get _openPaidV => int.tryParse(_openingPaid.text.trim()) ?? 0;
  int? get _availedV => int.tryParse(_availedAmount.text.trim());

  /// What count x instalment WOULD be, shown only to make the gap visible.
  /// On an Auction cheti the real figure is lower because of dividends
  /// already earned, and that difference is exactly why opening paid is its
  /// own input rather than something derived.
  int? get _openingImplied =>
      _instV == null ? null : _openCountV * _instV!;

  String? get _error {
    if (_name.text.trim().isEmpty) return 'Give the cheti a name.';
    if (_faceV == null || _totalV == null || _instV == null) return null;
    if (_faceV! <= 0 || _instV! <= 0 || _totalV! <= 0) {
      return 'Face value, instalments and instalment amount must be above zero.';
    }
    if (_openCountV > _totalV!) {
      return 'Instalments paid cannot exceed the total of $_totalV.';
    }
    if (_alreadyAvailed && (_availedV == null || _availedV! <= 0)) {
      return 'Enter the lumpsum you availed.';
    }
    return null;
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _faceV != null &&
      _totalV != null &&
      _instV != null &&
      _error == null &&
      !_saving;

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(chetiApiServiceProvider).createCheti(
            businessId: widget.businessId,
            name: _name.text.trim(),
            type: _type,
            frequency: _frequency,
            faceValue: _faceV!,
            totalInstalments: _totalV!,
            instalmentAmount: _instV!,
            startDate: _startDate,
            openingInstalmentsPaid: _openCountV,
            openingAmountPaid: _openPaidV,
            availedDate: _alreadyAvailed ? _availedDate : null,
            availedAmount: _alreadyAvailed ? _availedV : null,
            // Availing entered here happened before this app tracked the
            // cheti, so that cash is already inside the declared opening
            // balance and must not move BF again.
            availedPreMigration: _alreadyAvailed,
          );
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: ManaSpacing.lg,
        right: ManaSpacing.lg,
        top: ManaSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + ManaSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw(ref.t('add_cheti'),
                style: ManaType.cardTitle),
            const SizedBox(height: ManaSpacing.md),
            _field(_name, ref.t('cheti_name_field'), number: false),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ChetiType>(
                    initialValue: _type,
                    decoration: InputDecoration(labelText: ref.t('type_field')),
                    items: ChetiType.values
                        .map((t) => DropdownMenuItem(
                            value: t, child: ManaText.raw(t.dbValue)))
                        .toList(),
                    onChanged: (v) => setState(() => _type = v ?? ChetiType.auction),
                  ),
                ),
                const SizedBox(width: ManaSpacing.md),
                Expanded(
                  child: DropdownButtonFormField<ChetiFrequency>(
                    initialValue: _frequency,
                    decoration: InputDecoration(labelText: ref.t('frequency_field')),
                    items: ChetiFrequency.values
                        .map((f) => DropdownMenuItem(
                            value: f, child: ManaText.raw(f.dbValue)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _frequency = v ?? ChetiFrequency.monthly),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ManaSpacing.md),
            _field(_faceValue, ref.t('face_value_field')),
            _field(_total, ref.t('total_instalments_field')),
            _field(_instalment, ref.t('instalment_amount_field')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: ManaText.raw(ref.t('start_date')),
              subtitle: ManaText.raw(_dateFmt.format(_startDate)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (!mounted) return;
                if (picked != null) setState(() => _startDate = picked);
              },
            ),
            const Divider(height: ManaSpacing.xl),
            ManaText.raw(
              ref.t('cheti_partway_note'),
              style: ManaType.fine,
            ),
            const SizedBox(height: ManaSpacing.md),
            _field(_openingCount, ref.t('instalments_already_paid_field')),
            _field(_openingPaid, ref.t('total_already_paid_field')),
            if (_openingImplied != null && _openCountV > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: ManaSpacing.md),
                child: ManaText.raw(
                  _openPaidV == _openingImplied
                      ? ref
                          .t('opening_matches_note')
                          .replaceAll('{count}', '$_openCountV')
                          .replaceAll('{amount}', manaRupees(_instV!))
                      : ref
                          .t('opening_gap_note')
                          .replaceAll('{count}', '$_openCountV')
                          .replaceAll('{amount}', manaRupees(_instV!))
                          .replaceAll('{implied}', manaRupees(_openingImplied!)),
                  style: ManaType.fine,
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _alreadyAvailed,
              onChanged: (v) => setState(() => _alreadyAvailed = v),
              title: ManaText.raw(ref.t('already_availed_lumpsum')),
            ),
            if (_alreadyAvailed) ...[
              _field(_availedAmount, ref.t('amount_availed_field')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: ManaText.raw(ref.t('availed_on')),
                subtitle: ManaText.raw(_dateFmt.format(_availedDate)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _availedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (!mounted) return;
                  if (picked != null) setState(() => _availedDate = picked);
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(_error!,
                  style: ManaType.noteBad),
            ],
            const SizedBox(height: ManaSpacing.lg),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('save_cheti')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {bool number = true}) => Padding(
        padding: const EdgeInsets.only(bottom: ManaSpacing.md),
        child: TextField(
          controller: c,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(labelText: label),
          onChanged: (_) => setState(() {}),
        ),
      );
}

// ============================================================================
// Record one instalment
// ============================================================================

class _PaymentSheet extends ConsumerStatefulWidget {
  final Cheti cheti;
  final String businessId;
  const _PaymentSheet({required this.cheti, required this.businessId});
  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  late final TextEditingController _gross =
      TextEditingController(text: '${widget.cheti.instalmentAmount}');
  final _dividend = TextEditingController(text: '0');
  bool _saving = false;

  @override
  void dispose() {
    _gross.dispose();
    _dividend.dispose();
    super.dispose();
  }

  int? get _grossV => int.tryParse(_gross.text.trim());
  int get _dividendV => int.tryParse(_dividend.text.trim()) ?? 0;
  int? get _netV => _grossV == null ? null : _grossV! - _dividendV;

  String? get _error {
    if (_grossV == null) return null;
    if (_grossV! <= 0) return 'Instalment must be above zero.';
    if (_dividendV < 0) return 'Dividend cannot be negative.';
    if (_dividendV > _grossV!) {
      return 'Dividend cannot exceed the instalment.';
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(chetiApiServiceProvider).recordPayment(
            chetiId: widget.cheti.chetiId,
            grossInstalment: _grossV!,
            dividend: _dividendV,
          );
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isFixed = widget.cheti.type == ChetiType.fixed;
    return Padding(
      padding: EdgeInsets.only(
        left: ManaSpacing.lg,
        right: ManaSpacing.lg,
        top: ManaSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + ManaSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(ref.t('record_payment_for_note').replaceAll('{name}', widget.cheti.name),
              style: ManaType.cardTitle),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _gross,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: ref.t('instalment_required_field')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: ManaSpacing.md),
          // A Fixed cheti is a lucky draw: there is no auction and so no
          // dividend. Offering the field would invite a number that cannot
          // exist for this type.
          if (!isFixed)
            TextField(
              controller: _dividend,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: ref.t('dividend_this_period_field'),
                suffixIcon: ManaInfoHint(ref.t('dividend_helper')),
              ),
              onChanged: (_) => setState(() {}),
            ),
          const SizedBox(height: ManaSpacing.md),
          Row(
            children: [
              Expanded(
                  child: ManaText.raw(ref.t('cash_out_of_bf'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ManaType.note)),
              const SizedBox(width: ManaSpacing.xs),
              ManaText.raw(_netV == null ? '—' : manaRupees(_netV!),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(_error!,
                style: ManaType.noteBad),
          ],
          const SizedBox(height: ManaSpacing.lg),
          FilledButton(
            onPressed: (_grossV != null && _error == null && !_saving) ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : ManaText.raw(ref.t('save_payment')),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Record the availed lumpsum
// ============================================================================

class _AvailingSheet extends ConsumerStatefulWidget {
  final Cheti cheti;
  const _AvailingSheet({required this.cheti});
  @override
  ConsumerState<_AvailingSheet> createState() => _AvailingSheetState();
}

class _AvailingSheetState extends ConsumerState<_AvailingSheet> {
  final _amount = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _amountV => int.tryParse(_amount.text.trim());

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await NetworkErrorHandler.run(context, () async {
      await ref.read(chetiApiServiceProvider).recordAvailing(
            chetiId: widget.cheti.chetiId,
            amount: _amountV!,
          );
      return true;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: ManaSpacing.lg,
        right: ManaSpacing.lg,
        top: ManaSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + ManaSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ManaText.raw(ref.t('record_availing_for_note').replaceAll('{name}', widget.cheti.name),
              style: ManaType.cardTitle),
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(
            ref
                .t('availing_adds_to_bf_note')
                .replaceAll('{count}', '${widget.cheti.instalmentsRemaining}'),
            style: ManaType.fine,
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: ref.t('amount_availed_field')),
            onChanged: (_) => setState(() {}),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: ManaText.raw(ref.t('availed_on')),
            subtitle: ManaText.raw(_dateFmt.format(_date)),
            trailing: const Icon(Icons.calendar_today, size: 18),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (!mounted) return;
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: ManaSpacing.lg),
          FilledButton(
            onPressed: (_amountV != null && _amountV! > 0 && !_saving) ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : ManaText.raw(ref.t('save_availing')),
          ),
        ],
      ),
    );
  }
}
