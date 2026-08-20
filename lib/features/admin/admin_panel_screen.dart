import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../design/tokens/colors.dart';
import '../../design/components/mana_amount.dart';
import '../../design/tokens/typography.dart';
import '../../design/tokens/spacing.dart';
import '../../shared/translation_service.dart';
import '../../design/components/mana_text.dart';


/// Admin Panel — Platform Admin's "super power" delete actions.
///
/// RESOLVED (was a confirmed real bug): the original version asked for
/// raw person_id/business_id, which nobody actually knows — every other
/// part of this app searches by MLID/MLBI. Now: search by the human-
/// facing code -> see full details -> confirm -> only then delete. Loan/
/// Collection have no equivalent human code, so they stay UUID-based,
/// but still show full details before deletion.
class AdminPanelScreen extends ConsumerWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: ManaText.raw(ref.t('admin_panel')),
        leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/lr-012')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(ManaSpacing.md),
              decoration: BoxDecoration(
                color: ManaColors.statusBad.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ManaColors.statusBad),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: ManaColors.statusBad),
                  const SizedBox(width: ManaSpacing.sm),
                  Expanded(
                    child: ManaText.raw(
                      'Every action below is permanent and cannot be undone. A snapshot is logged before deletion, but the live data itself is gone forever once you confirm.',
                      style: ManaType.noteBad,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ManaSpacing.lg),
            const _DeletePersonCard(),
            const SizedBox(height: ManaSpacing.md),
            const _DeleteBusinessCard(),
            const SizedBox(height: ManaSpacing.md),
            const _DeleteLoanCard(),
            const SizedBox(height: ManaSpacing.md),
            const _DeleteCollectionCard(),
          ],
        ),
      ),
    );
  }
}

class _DeletePersonCard extends ConsumerStatefulWidget {
  const _DeletePersonCard();
  @override
  ConsumerState<_DeletePersonCard> createState() => _DeletePersonCardState();
}

class _DeletePersonCardState extends ConsumerState<_DeletePersonCard> {
  final _mlidController = TextEditingController();
  final _reasonController = TextEditingController();
  Map<String, dynamic>? _found;
  bool _searching = false;
  bool _deleting = false;
  String? _error;

  Future<void> _search() async {
    final mlid = _mlidController.text.trim();
    if (mlid.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _found = null;
    });
    try {
      final rows = await Supabase.instance.client.schema('app').rpc('admin_lookup_person', params: {'p_mlid': mlid});
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = list.isEmpty ? null : list.first;
        if (list.isEmpty) _error = 'No person found with MLID "$mlid".';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Search failed: $e';
      });
    }
  }

  Future<void> _confirmAndDelete() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty || _found == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('are_you_absolutely_sure')),
        content: ManaText.raw(
          'Permanently delete ${_found!['full_name']} (${_found!['mlid']}) and everything referencing them — addresses, ${_found!['business_count']} business membership(s), loans, collections. This cannot be undone.\n\nReason: $reason',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.pop(context, true),
            child: const ManaText.raw('yes, permanently delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await Supabase.instance.client.schema('app').rpc('admin_delete_person', params: {
        'p_person_id': _found!['person_id'],
        'p_reason': reason,
      });
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _found = null;
        _mlidController.clear();
        _reasonController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Person deleted.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'Deletion failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw('Delete Person', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: ManaColors.statusBad)),
            const SizedBox(height: 4),
            ManaText.raw('Search by MLID first — deletes the person and everything referencing them.',
                style: ManaType.note),
            const SizedBox(height: ManaSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mlidController,
                    decoration: const InputDecoration(labelText: 'MLID', isDense: true),
                    onChanged: (_) => setState(() => _found = null),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ElevatedButton(
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(ref.t('search')),
                ),
              ],
            ),
            if (_found != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              Container(
                padding: const EdgeInsets.all(ManaSpacing.sm),
                decoration: BoxDecoration(color: ManaColors.surfaceSunken, borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ManaText.raw('${_found!['full_name']}', style: ManaType.strong),
                    ManaText.raw('MLID: ${_found!['mlid']}   Mobile: ${_found!['mobile_number']}', style: ManaType.small),
                    // Last four only. The RPC's out-parameter is still named
                    // aadhaar_number, but the number itself no longer exists
                    // to print — it is hashed at rest.
                    ManaText.raw(
                        _found!['aadhaar_number'] == null
                            ? 'Aadhaar: Not provided'
                            : 'Aadhaar: •••• •••• ${_found!['aadhaar_number']}',
                        style: ManaType.small),
                    ManaText.raw('Verification: ${_found!['verification_ring']}   Businesses: ${_found!['business_count']}',
                        style: ManaType.small),
                  ],
                ),
              ),
              const SizedBox(height: ManaSpacing.sm),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: 'Reason (required)', isDense: true),
                maxLines: 2,
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(_error!, style: ManaType.noteBad),
            ],
            const SizedBox(height: ManaSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
                onPressed: (_found != null && _reasonController.text.trim().isNotEmpty && !_deleting) ? _confirmAndDelete : null,
                child: _deleting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const ManaText.raw('delete permanently', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteBusinessCard extends ConsumerStatefulWidget {
  const _DeleteBusinessCard();
  @override
  ConsumerState<_DeleteBusinessCard> createState() => _DeleteBusinessCardState();
}

class _DeleteBusinessCardState extends ConsumerState<_DeleteBusinessCard> {
  final _mlbiController = TextEditingController();
  final _reasonController = TextEditingController();
  Map<String, dynamic>? _found;
  bool _searching = false;
  bool _deleting = false;
  String? _error;

  Future<void> _search() async {
    final mlbi = _mlbiController.text.trim();
    if (mlbi.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _found = null;
    });
    try {
      final rows = await Supabase.instance.client.schema('app').rpc('admin_lookup_business', params: {'p_mlbi': mlbi});
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = list.isEmpty ? null : list.first;
        if (list.isEmpty) _error = 'No business found with MLBI "$mlbi".';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Search failed: $e';
      });
    }
  }

  Future<void> _confirmAndDelete() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty || _found == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('are_you_absolutely_sure')),
        content: ManaText.raw(
          'Permanently delete "${_found!['business_name']}" (${_found!['mlbi']}) and everything under it — ${_found!['agent_count']} agent(s), ${_found!['customer_count']} customer(s), ${_found!['investor_count']} investor(s), all loans/collections/settlements. This cannot be undone.\n\nReason: $reason',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.pop(context, true),
            child: const ManaText.raw('yes, permanently delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await Supabase.instance.client.schema('app').rpc('admin_delete_business', params: {
        'p_business_id': _found!['business_id'],
        'p_reason': reason,
      });
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _found = null;
        _mlbiController.clear();
        _reasonController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Business deleted.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'Deletion failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw('Delete Business', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: ManaColors.statusBad)),
            const SizedBox(height: 4),
            ManaText.raw('Search by MLBI first — deletes the business and everything under it, not the people themselves.',
                style: ManaType.note),
            const SizedBox(height: ManaSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _mlbiController,
                    decoration: const InputDecoration(labelText: 'MLBI', isDense: true),
                    onChanged: (_) => setState(() => _found = null),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ElevatedButton(
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(ref.t('search')),
                ),
              ],
            ),
            if (_found != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              Container(
                padding: const EdgeInsets.all(ManaSpacing.sm),
                decoration: BoxDecoration(color: ManaColors.surfaceSunken, borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ManaText.raw('${_found!['business_name']}', style: ManaType.strong),
                    ManaText.raw('MLBI: ${_found!['mlbi']}   Status: ${_found!['business_status']}', style: ManaType.small),
                    ManaText.raw('Owner: ${_found!['owner_name']} (${_found!['owner_mlid']})', style: ManaType.small),
                    ManaText.raw(
                        'Agents: ${_found!['agent_count']}   Customers: ${_found!['customer_count']}   Investors: ${_found!['investor_count']}',
                        style: ManaType.small),
                  ],
                ),
              ),
              const SizedBox(height: ManaSpacing.sm),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: 'Reason (required)', isDense: true),
                maxLines: 2,
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(_error!, style: ManaType.noteBad),
            ],
            const SizedBox(height: ManaSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
                onPressed: (_found != null && _reasonController.text.trim().isNotEmpty && !_deleting) ? _confirmAndDelete : null,
                child: _deleting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const ManaText.raw('delete permanently', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteLoanCard extends ConsumerStatefulWidget {
  const _DeleteLoanCard();
  @override
  ConsumerState<_DeleteLoanCard> createState() => _DeleteLoanCardState();
}

class _DeleteLoanCardState extends ConsumerState<_DeleteLoanCard> {
  final _idController = TextEditingController();
  final _reasonController = TextEditingController();
  Map<String, dynamic>? _found;
  bool _searching = false;
  bool _deleting = false;
  String? _error;

  Future<void> _search() async {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _found = null;
    });
    try {
      final rows = await Supabase.instance.client.schema('app').rpc('admin_lookup_loan', params: {'p_loan_id': id});
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = list.isEmpty ? null : list.first;
        if (list.isEmpty) _error = 'No loan found with that ID.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Search failed — is this a valid Loan ID? $e';
      });
    }
  }

  Future<void> _confirmAndDelete() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty || _found == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('are_you_absolutely_sure')),
        content: ManaText.raw(
          'Permanently delete loan ${_found!['loan_number']} (${_found!['customer_name']}, ${manaRupees(_found!['remaining_balance'])} outstanding) and its collections/schedule. This cannot be undone.\n\nReason: $reason',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.pop(context, true),
            child: const ManaText.raw('yes, permanently delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await Supabase.instance.client.schema('app').rpc('admin_delete_loan', params: {
        'p_loan_id': _found!['loan_id'],
        'p_reason': reason,
      });
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _found = null;
        _idController.clear();
        _reasonController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loan deleted.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'Deletion failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw('Delete Loan (Transaction)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: ManaColors.statusBad)),
            const SizedBox(height: 4),
            ManaText.raw('No human-readable code exists for loans — Loan ID (UUID) only, found via Report Hub/History.',
                style: ManaType.note),
            const SizedBox(height: ManaSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idController,
                    decoration: const InputDecoration(labelText: 'Loan ID (UUID)', isDense: true),
                    onChanged: (_) => setState(() => _found = null),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ElevatedButton(
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(ref.t('search')),
                ),
              ],
            ),
            if (_found != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              Container(
                padding: const EdgeInsets.all(ManaSpacing.sm),
                decoration: BoxDecoration(color: ManaColors.surfaceSunken, borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ManaText.raw('Loan ${_found!['loan_number']}', style: ManaType.strong),
                    ManaText.raw('Customer: ${_found!['customer_name']} (${_found!['customer_mlid']})', style: ManaType.small),
                    ManaText.raw(
                        'Given: ${manaRupees(_found!['amount_given'])}   Outstanding: ${manaRupees(_found!['remaining_balance'])}   Status: ${_found!['loan_status']}',
                        style: const TextStyle(fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(height: ManaSpacing.sm),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: 'Reason (required)', isDense: true),
                maxLines: 2,
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(_error!, style: ManaType.noteBad),
            ],
            const SizedBox(height: ManaSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
                onPressed: (_found != null && _reasonController.text.trim().isNotEmpty && !_deleting) ? _confirmAndDelete : null,
                child: _deleting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const ManaText.raw('delete permanently', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteCollectionCard extends ConsumerStatefulWidget {
  const _DeleteCollectionCard();
  @override
  ConsumerState<_DeleteCollectionCard> createState() => _DeleteCollectionCardState();
}

class _DeleteCollectionCardState extends ConsumerState<_DeleteCollectionCard> {
  final _idController = TextEditingController();
  final _reasonController = TextEditingController();
  Map<String, dynamic>? _found;
  bool _searching = false;
  bool _deleting = false;
  String? _error;

  Future<void> _search() async {
    final id = _idController.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _found = null;
    });
    try {
      final rows = await Supabase.instance.client.schema('app').rpc('admin_lookup_collection', params: {'p_collection_id': id});
      final list = (rows as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _searching = false;
        _found = list.isEmpty ? null : list.first;
        if (list.isEmpty) _error = 'No collection found with that ID.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'Search failed — is this a valid Collection ID? $e';
      });
    }
  }

  Future<void> _confirmAndDelete() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty || _found == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: ManaText.raw(ref.t('are_you_absolutely_sure')),
        content: ManaText.raw(
          'Permanently delete this collection of ${manaRupees(_found!['collected_amount'])} from ${_found!['customer_name']}. This cannot be undone.\n\nReason: $reason',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: ManaText.raw(ref.t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.pop(context, true),
            child: const ManaText.raw('yes, permanently delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await Supabase.instance.client.schema('app').rpc('admin_delete_collection', params: {
        'p_collection_id': _found!['collection_id'],
        'p_reason': reason,
      });
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _found = null;
        _idController.clear();
        _reasonController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Collection deleted.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = 'Deletion failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManaText.raw('Delete Collection (Transaction)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: ManaColors.statusBad)),
            const SizedBox(height: 4),
            ManaText.raw('No human-readable code exists for collections — Collection ID (UUID) only, found via History.',
                style: ManaType.note),
            const SizedBox(height: ManaSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idController,
                    decoration: const InputDecoration(labelText: 'Collection ID (UUID)', isDense: true),
                    onChanged: (_) => setState(() => _found = null),
                  ),
                ),
                const SizedBox(width: ManaSpacing.sm),
                ElevatedButton(
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : ManaText.raw(ref.t('search')),
                ),
              ],
            ),
            if (_found != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              Container(
                padding: const EdgeInsets.all(ManaSpacing.sm),
                decoration: BoxDecoration(color: ManaColors.surfaceSunken, borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ManaText.raw(manaRupees(_found!['collected_amount']), style: ManaType.strong),
                    ManaText.raw('Customer: ${_found!['customer_name']} (${_found!['customer_mlid']})', style: const TextStyle(fontSize: 16)),
                    ManaText.raw('Loan: ${_found!['loan_number'] ?? 'N/A'}   Date: ${_found!['entry_timestamp']}', style: ManaType.small),
                  ],
                ),
              ),
              const SizedBox(height: ManaSpacing.sm),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: 'Reason (required)', isDense: true),
                maxLines: 2,
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: ManaSpacing.sm),
              ManaText.raw(_error!, style: ManaType.noteBad),
            ],
            const SizedBox(height: ManaSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: ManaColors.statusBad),
                onPressed: (_found != null && _reasonController.text.trim().isNotEmpty && !_deleting) ? _confirmAndDelete : null,
                child: _deleting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const ManaText.raw('delete permanently', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
