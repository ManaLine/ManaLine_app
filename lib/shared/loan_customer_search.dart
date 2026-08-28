import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_text.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import '../features/owner_workspace/state/customer_state.dart';
import 'network_error_handler.dart';
import 'translation_service.dart';

/// Step 1 of issuing a loan: who is this for.
///
/// ONE widget for both workspaces. OW-005 and AG-007 each had their own copy
/// of this step, and the copies drifted: the Owner's was rebuilt to list every
/// match and add a new borrower on the way through, while the Agent's kept
/// searching the global identity RPC and refusing any ambiguous name. Worse,
/// they share loanWizardProvider -- so when the notifier learned to reject a
/// customer with no customer_id, the Agent's screen kept handing it exactly
/// that and its Select button went silently dead.
///
/// Sharing the widget cannot merge the two workspaces' DATA. Who the loan is
/// recorded against is decided server-side from the caller's own membership,
/// and create_loan_with_bf_check checks `own_active_agent_membership_permits`
/// -- an Agent can only ever act as themselves. What changes with the role is
/// what this widget OFFERS, which is the [canAddCustomer] flag below.
class ManaLoanCustomerSearch extends ConsumerStatefulWidget {
  final String businessId;

  /// Whether this user may bring somebody onto the book from here.
  ///
  /// The Owner always may. An Agent may only with `can_create_customer`; the
  /// server enforces it either way, and hiding the button when it would be
  /// refused is kinder than letting them fill a form that cannot be saved.
  final bool canAddCustomer;

  /// What to do once a real customer has been chosen. Always called with a
  /// customer that HAS a customerId -- a person found by identity search is
  /// added to the book here first.
  final void Function(CustomerSummary customer) onSelected;

  const ManaLoanCustomerSearch({
    super.key,
    required this.businessId,
    required this.onSelected,
    this.canAddCustomer = true,
  });

  @override
  ConsumerState<ManaLoanCustomerSearch> createState() => _ManaLoanCustomerSearchState();
}

class _ManaLoanCustomerSearchState extends ConsumerState<ManaLoanCustomerSearch> {
  final _query = TextEditingController();
  List<CustomerSummary> _matches = const [];
  bool _searching = false;
  bool _searched = false;

  /// personId of the row being added to the book right now, so its own button
  /// shows the spinner and the others go inert. A second tap while the first
  /// is still writing would create the customer twice.
  String? _adding;

  @override
  void initState() {
    super.initState();
    // Clearing the box clears the results.
    //
    // Both old screens kept the last result on screen after the text was
    // deleted, so an empty search box sat above a customer nobody had asked
    // for -- and the next tap started a loan against them.
    _query.addListener(() {
      if (_query.text.trim().isEmpty && (_matches.isNotEmpty || _searched)) {
        setState(() {
          _matches = const [];
          _searched = false;
        });
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _searched = false;
    });
    // One query covers MLID, mobile, Aadhaar, name and village, so there is
    // nothing to classify by the shape of what was typed.
    //
    // Which people come back is the Owner's rule, read server-side from
    // businesses.loans_require_existing_customer.
    final result = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerListProvider.notifier).searchLoanCandidates(
            businessId: widget.businessId,
            query: _query.text,
          );
    });
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searched = true;
      // EVERY match, shown. Refusing an ambiguous name outright -- "3 people
      // match that name, search by MANA LINE ID" -- asks for the one thing
      // the user standing in front of the customer is least likely to know.
      // The three people are right here; village, father/husband name and
      // live loan count let them be told apart.
      _matches = result ?? const <CustomerSummary>[];
    });
  }

  /// Village first. It is the axis the book is organised on -- a round is a
  /// village, a customer is placed by one -- and it is what tells two people
  /// of the same name apart before anything else does.
  List<MapEntry<String, List<CustomerSummary>>> get _byVillage {
    final groups = <String, List<CustomerSummary>>{};
    for (final c in _matches) {
      groups.putIfAbsent(c.village.isEmpty ? '—' : c.village, () => []).add(c);
    }
    final keys = groups.keys.toList()..sort();
    return [for (final k in keys) MapEntry(k, groups[k]!)];
  }

  /// Somebody already on the book is simply selected. Somebody who is not
  /// gets the question, because adding them and lending to them are two
  /// decisions and this screen used to make both at once.
  Future<void> _choose(CustomerSummary c) async {
    if (c.customerId.isNotEmpty) {
      widget.onSelected(c);
      return;
    }
    if (c.personId == null) return;

    final andLend = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              ManaSpacing.lg, 0, ManaSpacing.lg, ManaSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(c.fullName, style: ManaType.sheetTitle),
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(ref.t('not_on_this_book_yet'), style: ManaType.note),
              const SizedBox(height: ManaSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  child: ManaText.raw(ref.t('add_and_issue_loan')),
                ),
              ),
              const SizedBox(height: ManaSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: ManaText.raw(ref.t('add_only')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (andLend == null || !mounted) return; // dismissed

    if (!andLend) {
      await _addOnly(c);
      return;
    }
    setState(() => _adding = c.personId);
    // Link Existing, not Create New: the person already has an identity and an
    // MLID somewhere in the system. Making a second one would split their
    // history across two records that can never be joined again.
    final customerId = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerApiServiceProvider).createCustomer(
            businessId: widget.businessId,
            existingPersonId: c.personId,
          );
    });
    if (!mounted) return;
    setState(() => _adding = null);
    if (customerId == null) return;
    widget.onSelected(CustomerSummary(
      customerId: customerId,
      personId: c.personId,
      fullName: c.fullName,
      fatherHusbandName: c.fatherHusbandName,
      village: c.village,
      phoneNumber: c.phoneNumber,
      mlid: c.mlid,
      activeLoanCount: 0,
      todaysDue: 0,
      outstandingBalance: 0,
      lineRepaymentIndex: 0,
      customerStatus: 'Active',
      membershipStatus: 'Active',
    ));
  }

  /// Add them to the book and stay here.
  ///
  /// The row becomes an ordinary customer, so the next thing the person does
  /// -- lend to somebody else, or close the wizard -- starts from a book that
  /// already has them on it.
  Future<void> _addOnly(CustomerSummary c) async {
    setState(() => _adding = c.personId);
    final customerId = await NetworkErrorHandler.run(context, () async {
      return ref.read(customerApiServiceProvider).createCustomer(
            businessId: widget.businessId,
            existingPersonId: c.personId,
          );
    });
    if (!mounted) return;
    setState(() => _adding = null);
    if (customerId == null) return;
    // Re-run the search so the row redraws as somebody on the book rather
    // than still offering to add them.
    await _search();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(ref.t('added_to_this_business'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        ManaText.raw(ref.t('select_customer'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: ManaSpacing.xs),
        ManaText.raw(ref.t('search_customer_note'), style: ManaType.note),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                decoration: InputDecoration(labelText: ref.t('search')),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  if (_query.text.trim().isNotEmpty && !_searching) _search();
                },
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            ElevatedButton(
              onPressed:
                  (_query.text.trim().isNotEmpty && !_searching) ? _search : null,
              child: _searching
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('search')),
            ),
          ],
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (_matches.isNotEmpty)
          for (final group in _byVillage) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xs),
              child: ManaText.raw(
                '${group.key}  ·  ${group.value.length}',
                style: ManaType.note.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final c in group.value) _matchCard(c),
          ]
        else if (_searched && !_searching)
          ManaText.raw(ref.t('no_matching_customer_note'), style: ManaType.note),
      ],
    );
  }

  Widget _matchCard(CustomerSummary c) {
    final isCustomer = c.customerId.isNotEmpty;
    // Somebody not on the book yet, when this user may not add them, is shown
    // greyed rather than hidden: "not found" and "found, but you may not lend
    // to them" are different facts, and hiding the second sends them hunting
    // for a person who is right there.
    final actionable = isCustomer || widget.canAddCustomer;

    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
      child: ListTile(
        leading: ManaVerificationRing(isVerified: isCustomer, size: 40),
        title: ManaText.raw(c.fullName, style: ManaType.strong),
        subtitle: ManaText.raw([
          if (c.fatherHusbandName.isNotEmpty) c.fatherHusbandName,
          if (c.mlid.isNotEmpty) c.mlid,
          if (c.phoneNumber.isNotEmpty) c.phoneNumber,
          // The deciding detail when two same-named people are both on
          // screen: one of them already owes this book money.
          if (c.activeLoanCount > 0) '${c.activeLoanCount} live',
          if (!isCustomer)
            widget.canAddCustomer
                ? 'Not on this book yet'
                : 'Not on this book — ask the Owner to add them',
        ].join(' · ')),
        onTap: (_adding != null || !actionable) ? null : () => _choose(c),
        trailing: !actionable
            ? null
            : isCustomer
                ? ElevatedButton(
                    onPressed: _adding != null ? null : () => _choose(c),
                    child: ManaText.raw(ref.t('select')),
                  )
                : OutlinedButton(
                    onPressed: _adding != null ? null : () => _choose(c),
                    child: _adding == c.personId
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : ManaText.raw(ref.t('add')),
                  ),
      ),
    );
  }
}
