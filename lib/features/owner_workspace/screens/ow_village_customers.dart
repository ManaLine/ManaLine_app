import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/components/mana_amount.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/tokens/typography.dart';
import '../../../shared/mana_time.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/translation_service.dart';
import '../state/bulk_onboarding_service.dart';
import 'ow_pre_existing_loan_sheet.dart';
import '../state/village_book_summary.dart';

/// One village's customers, one per page, with their loans.
///
/// Seventeen people is a sitting an Owner can finish. Two hundred is not, which
/// is why the book is entered village by village -- and it is how the paper
/// book and the collection round are organised anyway.
class VillageCustomersScreen extends ConsumerStatefulWidget {
  final String businessId;

  /// What to call this village on screen. The out-of-area group passes its own
  /// heading rather than a village name.
  final String title;

  /// This village's rows, as the book list already fetched them. Passed in
  /// rather than re-queried: the list has them, and a second round trip on a
  /// village connection to redraw what is already on screen is latency for
  /// nothing.
  final List<ManaLoanPosition> positions;

  const VillageCustomersScreen({
    super.key,
    required this.businessId,
    required this.title,
    required this.positions,
  });

  @override
  ConsumerState<VillageCustomersScreen> createState() =>
      _VillageCustomersScreenState();
}

class _VillageCustomersScreenState
    extends ConsumerState<VillageCustomersScreen> {
  late List<ManaLoanPosition> _positions = widget.positions;

  /// MLIDs saved in this sitting, so a page says so rather than looking
  /// identical before and after.
  final Set<String> _savedNow = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The village's people, A to Z, each with whatever loans they already have.
  ///
  /// Distinct by person: the rows are per LOAN, so somebody with two loans
  /// appears twice in the source and must appear once here.
  List<_Customer> get _customers {
    final byPerson = <String, _Customer>{};
    for (final row in _positions) {
      final existing = byPerson[row.personId];
      byPerson[row.personId] = _Customer(
        personId: row.personId,
        mlid: row.mlid,
        fullName: row.fullName,
        loans: [...?existing?.loans, if (row.hasLoan) row],
      );
    }
    final list = byPerson.values.toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return list;
  }

  Future<void> _reload() async {
    final rows = await NetworkErrorHandler.run(context, () async {
      return ref
          .read(bulkOnboardingServiceProvider)
          .customerPositions(widget.businessId);
    });
    if (rows == null || !mounted) return;
    // Re-filtered to this village by the same key the list grouped on, so a
    // customer whose village changed under us does not silently appear here.
    final mine = widget.positions.isEmpty
        ? <ManaLoanPosition>[]
        : rows
            .where((r) =>
                r.village == widget.positions.first.village &&
                r.inOperatingArea == widget.positions.first.inOperatingArea)
            .toList();
    setState(() => _positions = mine);
  }

  Future<void> _addLoan(_Customer who) async {
    final saved = await manaEnterPreExistingLoan(
      context,
      ref,
      businessId: widget.businessId,
      mlid: who.mlid,
      fullName: who.fullName,
    );
    if (!saved || !mounted) return;
    setState(() => _savedNow.add(who.mlid));
    await _reload();
  }

  /// What the Owner has typed into the header search, lower-cased.
  ///
  /// A village of fifteen is a list you read; a village of sixty is a list you
  /// scroll past the person you wanted. Name and MLID both, because an Owner
  /// looking somebody up has whichever of the two they happen to remember.
  String _query = '';
  bool _searching = false;
  final _search = TextEditingController();

  List<_Customer> get _matching {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _customers;
    return _customers
        .where((c) =>
            c.fullName.toLowerCase().contains(q) ||
            c.mlid.toLowerCase().contains(q))
        .toList();
  }

  /// The one row open for entry, or null with the list closed.
  String? _openMlid;

  @override
  Widget build(BuildContext context) {
    final all = _customers;
    final customers = _matching;

    return Scaffold(
      appBar: ManaAppBar(
        title: widget.title,
        // The search lives in the header's right edge, where every other
        // screen in this app puts one, and only appears once there is a list
        // to search. A magnifier over an empty village is a control that
        // cannot do anything.
        actions: all.isEmpty
            ? const []
            : [
                IconButton(
                  icon: Icon(_searching ? Icons.close : Icons.search),
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) {
                      _search.clear();
                      _query = '';
                    }
                  }),
                ),
              ],
      ),
      body: SafeArea(
        child: all.isEmpty
            ? Center(
                child: ManaText.raw(ref.t('nobody_in_this_stage_yet'),
                    style: ManaType.secondary),
              )
            : Column(
                children: [
                  if (_searching)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(ManaSpacing.lg,
                          ManaSpacing.sm, ManaSpacing.lg, 0),
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: ref.t('search_by_name_or_mlid'),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  // The count is the reconfirmation the Owner asked for: a
                  // village they believe holds eighteen people should say
                  // eighteen. While a search is narrowing it, it says how many
                  // of how many, so a filtered list is never mistaken for the
                  // whole village.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(ManaSpacing.lg,
                        ManaSpacing.sm, ManaSpacing.lg, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ManaText.raw(
                        customers.length == all.length
                            ? ref
                                .t('customers_count_note')
                                .replaceAll('{count}', '${all.length}')
                            : '${customers.length} / ${all.length}',
                        style: ManaType.note,
                      ),
                    ),
                  ),
                  Expanded(
                    child: customers.isEmpty
                        ? Center(
                            child: ManaText.raw(
                                ref.t('no_matching_customer_note'),
                                style: ManaType.secondary),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(ManaSpacing.lg),
                            itemCount: customers.length,
                            itemBuilder: (context, i) => _row(customers[i]),
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  /// One customer, closed until tapped.
  ///
  /// This replaced a PageView of one customer per page. In a village of
  /// twenty, reaching the last person meant swiping past nineteen, and the
  /// only thing saying how many there were was a "1 of 20" counter beneath.
  /// A list answers both questions by existing.
  Widget _row(_Customer who) {
    final open = _openMlid == who.mlid;
    final saved = _savedNow.contains(who.mlid);
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: ManaText.raw(who.fullName),
            subtitle: ManaText.raw(
              who.loans.isEmpty
                  ? who.mlid
                  : '${who.mlid} - ${ref.t('loans_already_entered').replaceAll('{count}', '${who.loans.length}')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ManaType.note,
            ),
            trailing: saved
                ? Icon(Icons.check_circle,
                    size: 20, color: ManaColors.statusGood)
                : Icon(open ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _openMlid = open ? null : who.mlid),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // What this person already carries, before the button:
                  // the question an Owner asks on opening a row is "have I
                  // done them yet".
                  for (final loan in who.loans)
                    Card(
                      margin: const EdgeInsets.only(bottom: ManaSpacing.xs),
                      child: ListTile(
                        dense: true,
                        title: ManaAmount.compact(loan.balance,
                            semanticLabel: ref.t('remaining_balance')),
                        subtitle: ManaText.raw(
                          loan.lastCollection == null
                              ? ref.t('no_collections_yet')
                              : manaDisplayDate(loan.lastCollection),
                          style: ManaType.note,
                        ),
                      ),
                    ),
                  if (saved) ...[
                    ManaText.raw(ref.t('entered_in_this_sitting'),
                        style: TextStyle(
                            color: ManaColors.statusGood, fontSize: 13)),
                    const SizedBox(height: ManaSpacing.sm),
                  ],
                  FilledButton.icon(
                    onPressed: () => _addLoan(who),
                    icon: const Icon(Icons.add, size: 18),
                    label: ManaText.raw(ref.t('add_loan')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Customer {
  final String personId;
  final String mlid;
  final String fullName;
  final List<ManaLoanPosition> loans;
  const _Customer({
    required this.personId,
    required this.mlid,
    required this.fullName,
    required this.loans,
  });
}

/// The loan itself.
///
/// BALANCE AS IT STANDS TODAY, and no instalment history. MigrationPlan carries
/// an emiHistory flag precisely because some books record a running balance and
/// no history at all, and this door is for the Owner typing from paper on a
/// phone. app.migrate_loan derives what was collected as
/// `repayment - remaining`, so a balance alone is a complete, correct loan --
/// what it cannot do is reproduce the individual instalments, and the sheet
/// says so rather than letting somebody assume it has.
