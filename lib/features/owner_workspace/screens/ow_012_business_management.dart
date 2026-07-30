import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_text.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/business_name_checker.dart';
import '../state/business_management_state.dart';
import '../state/owner_workspace_state.dart';
import '../state/owner_api_service.dart' show AgentSummary;

// A failed load previously left every one of this screen's tabs looking
// like a legitimate empty state ("No Operating Areas yet.", "No active
// members yet.") with the real Postgrest/RLS error swallowed into
// `state.error` and never rendered anywhere — indistinguishable from a
// business that genuinely has no data. Surfacing it here so a load
// failure reads as "something broke, tap retry" instead of "empty".
class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            const ManaText('could not load data'),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: ManaColors.statusBad)),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(onPressed: onRetry, child: const ManaText('retry')),
          ],
        ),
      ),
    );
  }
}

/// OW-012 — Business Management. Owner only. Create and manage Businesses.
///
/// S1 Business List is the landing state (list of Business Summary Cards,
/// "Create Business" available above the list — BR-119 Revised: one Owner
/// may own multiple Businesses). Drilling into a card opens S3 Business
/// Detail with tabs for Operating Areas / Business Agreements / Business
/// Members / Account Periods.
class BusinessManagementScreen extends ConsumerStatefulWidget {
  // Set when reached from a business-scoped screen so the detail screen
  // knows WHICH business — but on its own this no longer causes a jump.
  //
  // FIXED (item 10): every business-scoped caller passes `extra: businessId`,
  // including OW-001's plain "Business Management" menu entry, so the
  // unconditional auto-push made this screen a pass-through — the Owner
  // could never reach the businesses list, which is the whole point of a
  // screen that supports multiple businesses (BR-119 Revised). The jump now
  // requires initialTab as well, i.e. the caller asked for a SPECIFIC tab
  // (the notifications sheet's Invitations/Acceptances rows, `?tab=members`).
  // "Just open Business Management" lands on the list.
  final String? initialBusinessId;
  final BusinessDetailTab? initialTab;
  const BusinessManagementScreen({super.key, this.initialBusinessId, this.initialTab});

  @override
  ConsumerState<BusinessManagementScreen> createState() => _BusinessManagementScreenState();
}

class _BusinessManagementScreenState extends ConsumerState<BusinessManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessListProvider.notifier).load();
      final businessId = widget.initialBusinessId;
      final initialTab = widget.initialTab;
      if (businessId != null && initialTab != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _BusinessDetailScreen(businessId: businessId, initialTab: initialTab),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessListProvider);

    return Scaffold(
      appBar: AppBar(title: const ManaText('business management')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const _CreateBusinessScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const ManaText('create business'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(businessListProvider.notifier).load(),
          child: state.loading && state.businesses.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
                  ? _ErrorBanner(message: state.error!, onRetry: () => ref.read(businessListProvider.notifier).load())
              : state.businesses.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(ManaSpacing.xxl),
                      children: const [
                        Center(
                          child: ManaText.raw(
                            'No businesses yet. Tap "Create Business" to get started.',
                            style: TextStyle(color: ManaColors.textSecondary),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                          ManaSpacing.lg, ManaSpacing.lg, ManaSpacing.lg, ManaSpacing.xxl * 2),
                      children: state.businesses
                          .map((b) => _BusinessSummaryCard(
                                business: b,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => _BusinessDetailScreen(businessId: b.businessId)),
                                ),
                              ))
                          .toList(),
                    ),
        ),
      ),
    );
  }
}

class _BusinessSummaryCard extends StatelessWidget {
  final BusinessSummary business;
  final VoidCallback onTap;
  const _BusinessSummaryCard({required this.business, required this.onTap});

  ManaStatus get _statusKind => switch (business.businessStatus) {
        'Active' => ManaStatus.good,
        'Suspended' => ManaStatus.bad,
        _ => ManaStatus.neutral, // Not Started
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: ManaSpacing.md),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: ManaColors.inkFaint,
                    backgroundImage: business.logoUrl != null ? NetworkImage(business.logoUrl!) : null,
                    child: business.logoUrl == null
                        ? const Icon(Icons.storefront, color: ManaColors.textSecondary)
                        : null,
                  ),
                  const SizedBox(width: ManaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ManaText.raw(business.businessName,
                            style: Theme.of(context).textTheme.titleLarge),
                        ManaText.raw(business.mlbi,
                            style: const TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  ManaStatusPill(label: business.businessStatus, status: _statusKind),
                ],
              ),
              const SizedBox(height: ManaSpacing.md),
              Wrap(
                spacing: ManaSpacing.md,
                runSpacing: ManaSpacing.xs,
                children: [
                  _StatChip(icon: Icons.location_on_outlined, label: '${business.operatingAreaCount} Areas'),
                  _StatChip(icon: Icons.people_outline, label: '${business.activeCustomers} Customers'),
                  _StatChip(icon: Icons.badge_outlined, label: '${business.activeAgents} Agents'),
                  _StatChip(icon: Icons.savings_outlined, label: '${business.activeInvestors} Investors'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: ManaColors.textSecondary),
        const SizedBox(width: 4),
        ManaText.raw(label, style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
      ],
    );
  }
}

// ============================================================================
// S2 — Create Business
// ============================================================================

class _CreateBusinessScreen extends ConsumerStatefulWidget {
  const _CreateBusinessScreen();

  @override
  ConsumerState<_CreateBusinessScreen> createState() => _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends ConsumerState<_CreateBusinessScreen> {
  final _businessName = TextEditingController();
  final _registeredFinanceName = TextEditingController();
  final _businessType = TextEditingController();
  final _businessAddress = TextEditingController();
  final _businessPhone = TextEditingController();
  final _businessEmail = TextEditingController();
  Uint8List? _logoBytes;

  bool get _valid => _businessName.text.trim().isNotEmpty && _registeredFinanceName.text.trim().isNotEmpty;

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _logoBytes = bytes);
  }

  Future<void> _submit() async {
    final available = await BusinessNameChecker.isAvailable(_businessName.text);
    if (!available) {
      if (!mounted) return;
      final alternatives = await BusinessNameChecker.suggestAlternatives(_businessName.text);
      if (!mounted) return;
      final chosen = await showDialog<String>(
        context: context,
        builder: (_) => BusinessNameTakenDialog(name: _businessName.text.trim(), alternatives: alternatives),
      );
      if (chosen != null) setState(() => _businessName.text = chosen);
      return;
    }
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(createBusinessFormProvider.notifier).submit(
            businessName: _businessName.text.trim(),
            registeredFinanceName: _registeredFinanceName.text.trim(),
            businessType: _businessType.text.trim().isEmpty ? null : _businessType.text.trim(),
            businessAddress: _businessAddress.text.trim().isEmpty ? null : _businessAddress.text.trim(),
            businessPhone: _businessPhone.text.trim().isEmpty ? null : _businessPhone.text.trim(),
            businessEmail: _businessEmail.text.trim().isEmpty ? null : _businessEmail.text.trim(),
          );
    });
    if (ok == true && mounted) {
      final businessId = ref.read(createBusinessFormProvider).createdBusinessId;
      if (businessId != null && _logoBytes != null) {
        try {
          final path = '$businessId/logo.jpg';
          await Supabase.instance.client.storage.from('business-logos').uploadBinary(
                path,
                _logoBytes!,
                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
          final url =
              await Supabase.instance.client.storage.from('business-logos').createSignedUrl(path, 60 * 60 * 24 * 365);
          await Supabase.instance.client.from('businesses').update({'logo_url': url}).eq('business_id', businessId);
        } catch (e) {
          // Non-fatal — the business itself was created successfully;
          // the logo can be added later, never block on this.
        }
      }
      ref.read(createBusinessFormProvider.notifier).reset();
      Navigator.of(context).pop();
      if (businessId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _BusinessDetailScreen(businessId: businessId)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(createBusinessFormProvider);

    return Scaffold(
      appBar: AppBar(title: const ManaText('create business')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            const ManaText.raw(
              'This is the same Create Business step covered in first-time setup — '
              'use it here to add another business, or to start one you skipped earlier.',
              style: TextStyle(color: ManaColors.textSecondary),
            ),
            const SizedBox(height: ManaSpacing.lg),
            Center(
              child: GestureDetector(
                onTap: _pickLogo,
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: ManaColors.surfaceSunken,
                  backgroundImage: _logoBytes != null ? MemoryImage(_logoBytes!) : null,
                  child: _logoBytes == null
                      ? const Icon(Icons.add_a_photo_outlined, color: ManaColors.textSecondary)
                      : null,
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _pickLogo,
                child: ManaText(_logoBytes == null ? 'add business photo' : 'change photo'),
              ),
            ),
            TextField(
              controller: _businessName,
              decoration: const InputDecoration(labelText: 'Business Name *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _registeredFinanceName,
              decoration: const InputDecoration(labelText: 'Registered Finance Name *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(controller: _businessType, decoration: const InputDecoration(labelText: 'Business Type')),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _businessAddress,
              decoration: const InputDecoration(labelText: 'Business Address'),
              maxLines: 2,
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _businessPhone,
              decoration: const InputDecoration(labelText: 'Business Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _businessEmail,
              decoration: const InputDecoration(labelText: 'Business Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: ManaSpacing.xxl),
            FilledButton(
              onPressed: (_valid && !formState.submitting) ? _submit : null,
              child: formState.submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const ManaText('save business'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// S3 — Business Detail (tabs)
// ============================================================================

class _BusinessDetailScreen extends ConsumerStatefulWidget {
  final String businessId;
  final BusinessDetailTab? initialTab;
  const _BusinessDetailScreen({required this.businessId, this.initialTab});

  @override
  ConsumerState<_BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends ConsumerState<_BusinessDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(businessDetailProvider(widget.businessId).notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessDetailProvider(widget.businessId));
    final detail = state.detail;
    // DefaultTabController only reads `initialIndex` once, at construction —
    // so the tab requested via navigation (widget.initialTab, e.g. Members
    // from the Invitations pill) has to win on this very first build.
    // Deliberately NOT synced into businessDetailProvider's own `activeTab`
    // here: writing to a provider from initState/build is exactly what
    // Riverpod's "tried to modify a provider while the widget tree was
    // building" guard exists to catch (hit this for real — see fix note).
    // activeTab has no other reader in this file besides this one line, so
    // there's nothing to keep in sync; TabBar's own onTap already keeps the
    // provider updated for whichever tab the Owner picks from here on.
    final initialTab = widget.initialTab ?? state.activeTab;

    return DefaultTabController(
      length: 4,
      initialIndex: BusinessDetailTab.values.indexOf(initialTab),
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(detail?.summary.businessName ?? 'business detail'),
          bottom: TabBar(
            isScrollable: true,
            onTap: (i) => ref
                .read(businessDetailProvider(widget.businessId).notifier)
                .setTab(BusinessDetailTab.values[i]),
            tabs: const [
              Tab(text: 'Operating Areas'),
              Tab(text: 'Agreements'),
              Tab(text: 'Members'),
              Tab(text: 'Account Periods'),
            ],
          ),
        ),
        body: state.loading && detail == null
            ? const Center(child: CircularProgressIndicator())
            : state.error != null && detail == null
                ? _ErrorBanner(
                    message: state.error!,
                    onRetry: () => ref.read(businessDetailProvider(widget.businessId).notifier).load(),
                  )
            : TabBarView(
                children: [
                  _OperatingAreasTab(businessId: widget.businessId),
                  _AgreementsTab(businessId: widget.businessId),
                  _MembersTab(businessId: widget.businessId),
                  _AccountPeriodsTab(businessId: widget.businessId),
                ],
              ),
      ),
    );
  }
}

// --- Operating Areas tab -----------------------------------------------------
// Reuses the PIN → Village → Add flow already built for OW-000 Step 2. Also
// reachable to expand an already-Active business's areas (locked rule).

class _OperatingAreasTab extends ConsumerStatefulWidget {
  final String businessId;
  const _OperatingAreasTab({required this.businessId});

  @override
  ConsumerState<_OperatingAreasTab> createState() => _OperatingAreasTabState();
}

class _OperatingAreasTabState extends ConsumerState<_OperatingAreasTab> {
  final _pinCode = TextEditingController();
  final _areaName = TextEditingController();

  @override
  void dispose() {
    _pinCode.dispose();
    _areaName.dispose();
    super.dispose();
  }

  Future<void> _addSelected() async {
    final selected = ref.read(operatingAreaSearchProvider).selected;
    if (selected == null) return;
    // Default the name to the first village. A one-village round named
    // after its village is the common case and typing it again is friction;
    // the Owner can rename once a second village joins.
    final name = _areaName.text.trim().isEmpty ? selected.villageTownName : _areaName.text.trim();
    final ok = await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).addOperatingArea(
            name: name,
            locationId: selected.locationId,
          );
    });
    if (ok == true) {
      ref.read(operatingAreaSearchProvider.notifier).reset();
      _pinCode.clear();
      _areaName.clear();
    }
  }

  Future<void> _addVillage(OperatingAreaSummary area) async {
    final picked = await showModalBottomSheet<LocationOption>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VillagePickerSheet(areaName: area.name),
    );
    if (picked == null || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).addVillageToArea(
            operatingAreaId: area.operatingAreaId,
            locationId: picked.locationId,
          );
    });
  }

  Future<void> _removeVillage(OperatingAreaSummary area, AreaVillage village) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const ManaText('remove village?'),
        content: ManaText.raw(
          '${village.villageTownName} will no longer be part of ${area.name}. '
          'Customers already registered there are not affected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const ManaText('cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const ManaText('remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).removeVillageFromArea(
            operatingAreaId: area.operatingAreaId,
            operatingAreaLocationId: village.operatingAreaLocationId,
          );
    });
  }

  Future<void> _removeArea(OperatingAreaSummary area) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const ManaText('remove operating area?'),
        content: ManaText.raw(
          '${area.name} (${area.villagesLabel}) will be set Inactive. Its account '
          'periods and history are kept, and any assigned agent loses access to it.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const ManaText('cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.of(context).pop(true),
            child: const ManaText('remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(businessDetailProvider(widget.businessId).notifier)
          .removeOperatingArea(operatingAreaId: area.operatingAreaId);
    });
  }

  Future<void> _rename(OperatingAreaSummary area) async {
    final controller = TextEditingController(text: area.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const ManaText('rename operating area'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Area name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const ManaText('cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const ManaText('save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(businessDetailProvider(widget.businessId).notifier)
          .renameOperatingArea(operatingAreaId: area.operatingAreaId, name: name);
    });
  }

  Future<void> _assignAgent(OperatingAreaSummary area) async {
    final agents = await NetworkErrorHandler.run(context, () async {
      return ref.read(ownerApiServiceProvider).fetchAgents(businessId: widget.businessId, status: 'Active');
    });
    if (agents == null || !mounted) return;
    final choice = await showModalBottomSheet<_AreaAssignmentChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AssignAgentSheet(area: area, agents: agents),
    );
    if (choice == null || !mounted) return;
    final businessId = widget.businessId;
    if (choice.unassign) {
      await NetworkErrorHandler.run(context, () async {
        return ref.read(businessDetailProvider(businessId).notifier).unassignArea(
              businessId: businessId,
              operatingAreaId: area.operatingAreaId,
            );
      });
    } else if (choice.agent?.membershipId != null) {
      await NetworkErrorHandler.run(context, () async {
        return ref.read(businessDetailProvider(businessId).notifier).assignAreaToAgent(
              businessId: businessId,
              operatingAreaId: area.operatingAreaId,
              agentId: choice.agent!.agentId,
              agentMembershipId: choice.agent!.membershipId!,
            );
      });
    }
  }

  Future<void> _configureCycle(OperatingAreaSummary area) async {
    final result = await showDialog<_CycleConfigInput>(
      context: context,
      builder: (_) => _CycleConfigDialog(initial: area),
    );
    if (result == null || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).configureAccountCycle(
            operatingAreaId: area.operatingAreaId,
            durationDays: result.duration,
            cycleUnit: result.unit,
            submissionTime: result.submissionTime,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(businessDetailProvider(widget.businessId)).operatingAreas;
    final search = ref.watch(operatingAreaSearchProvider);

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const ManaText.raw(
          'An operating area is one round, covering as many villages as the '
          'round actually walks. Name it, add its first village here, then '
          'attach the rest from the area itself.',
          style: TextStyle(color: ManaColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _areaName,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Area name',
            helperText: 'Leave blank to name it after the first village',
          ),
        ),
        TextField(
          controller: _pinCode,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: 'PIN Code'),
          onChanged: (v) {
            if (v.trim().length == 6) {
              ref.read(operatingAreaSearchProvider.notifier).searchByPin(v.trim());
            }
          },
        ),
        if (search.searching) const Center(child: CircularProgressIndicator()),
        if (!search.searching && search.matches.isNotEmpty)
          ...search.matches.map((m) {
            final selected = search.selected?.locationId == m.locationId;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? ManaColors.statusGood : ManaColors.textSecondary,
              ),
              title: ManaText.raw('${m.villageTownName} — ${m.pinCode}'),
              onTap: () => ref.read(operatingAreaSearchProvider.notifier).selectVillage(m),
            );
          }),
        const SizedBox(height: ManaSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: search.selected != null ? _addSelected : null,
            icon: const Icon(Icons.add, size: 18),
            label: const ManaText('add area'),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        const Divider(),
        const SizedBox(height: ManaSpacing.sm),
        const ManaText('current operating areas', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: ManaSpacing.sm),
        if (areas.isEmpty)
          const ManaText.raw('No Operating Areas yet.', style: TextStyle(color: ManaColors.textSecondary))
        else
          ...areas.map((a) => Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.location_on,
                          color: a.status == 'Active' ? ManaColors.brand : ManaColors.textSecondary),
                      title: Row(
                        children: [
                          Expanded(child: ManaText.raw(a.name)),
                          if (a.status != 'Active')
                            const ManaStatusPill(label: 'Inactive', status: ManaStatus.neutral),
                        ],
                      ),
                      subtitle: ManaText.raw(a.cycleConfigured
                          ? 'Cycle: ${a.accountCycleDuration} ${a.accountCycleUnit}, submits ${a.submissionTime}'
                          : 'Account cycle not yet configured'),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Area options',
                        onSelected: (v) => switch (v) {
                          'cycle' => _configureCycle(a),
                          'rename' => _rename(a),
                          'village' => _addVillage(a),
                          _ => _removeArea(a),
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'cycle',
                              child: ManaText(a.cycleConfigured ? 'edit cycle' : 'configure cycle')),
                          const PopupMenuItem(value: 'rename', child: ManaText('rename area')),
                          const PopupMenuItem(value: 'village', child: ManaText('add village')),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'remove',
                            child: ManaText.raw('remove area',
                                style: TextStyle(color: ManaColors.statusBad)),
                          ),
                        ],
                      ),
                    ),
                    // The villages this round covers. Each chip carries its
                    // own remove affordance rather than hiding detachment in
                    // a menu — with N villages the Owner needs to see which
                    // one they are about to drop.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          ManaSpacing.md, 0, ManaSpacing.md, ManaSpacing.sm),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: ManaSpacing.sm,
                          runSpacing: ManaSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final v in a.villages)
                              InputChip(
                                label: ManaText.raw('${v.villageTownName} — ${v.pinCode}',
                                    style: const TextStyle(fontSize: 13)),
                                onDeleted: () => _removeVillage(a, v),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                deleteButtonTooltipMessage: 'Remove ${v.villageTownName} from ${a.name}',
                              ),
                            TextButton.icon(
                              onPressed: () => _addVillage(a),
                              icon: const Icon(Icons.add, size: 18),
                              label: const ManaText('add village'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      dense: true,
                      leading: Icon(
                        a.isUnassigned ? Icons.person_off_outlined : Icons.badge_outlined,
                        size: 18,
                        color: a.isUnassigned ? ManaColors.statusWarn : ManaColors.textSecondary,
                      ),
                      title: ManaText.raw(
                        a.isUnassigned
                            ? 'No agent assigned — not being worked'
                            : 'Assigned to ${a.assignedAgentName}',
                        style: TextStyle(
                          fontSize: 13,
                          color: a.isUnassigned ? ManaColors.statusWarn : ManaColors.textSecondary,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () => _assignAgent(a),
                        child: ManaText(a.isUnassigned ? 'assign agent' : 'reassign'),
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}

/// PIN → village picker, reused for "attach another village to this area".
/// Shares `operatingAreaSearchProvider` with the create panel above and
/// resets it on the way in and out, so a half-finished search in one place
/// never leaks into the other.
class _VillagePickerSheet extends ConsumerStatefulWidget {
  final String areaName;
  const _VillagePickerSheet({required this.areaName});

  @override
  ConsumerState<_VillagePickerSheet> createState() => _VillagePickerSheetState();
}

class _VillagePickerSheetState extends ConsumerState<_VillagePickerSheet> {
  final _pinCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Provider write, so it must not happen during build — same Riverpod
    // guard the tab controller note above documents.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(operatingAreaSearchProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _pinCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(operatingAreaSearchProvider);

    return Padding(
      padding: MediaQuery.of(context).viewInsets,
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            ManaText.raw('Add a village to ${widget.areaName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _pinCode,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'PIN Code'),
              onChanged: (v) {
                if (v.trim().length == 6) {
                  ref.read(operatingAreaSearchProvider.notifier).searchByPin(v.trim());
                }
              },
            ),
            if (search.searching) const Center(child: CircularProgressIndicator()),
            if (!search.searching && search.matches.isEmpty && _pinCode.text.trim().length == 6)
              const ManaText.raw('No villages found for that PIN.',
                  style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
            ...search.matches.map((m) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined, color: ManaColors.brand),
                  title: ManaText.raw('${m.villageTownName} — ${m.pinCode}'),
                  onTap: () {
                    ref.read(operatingAreaSearchProvider.notifier).reset();
                    Navigator.of(context).pop(m);
                  },
                )),
          ],
        ),
      ),
    );
  }
}

class _AreaAssignmentChoice {
  final AgentSummary? agent;
  final bool unassign;
  _AreaAssignmentChoice.agent(this.agent) : unassign = false;
  _AreaAssignmentChoice.unassign()
      : agent = null,
        unassign = true;
}

class _AssignAgentSheet extends StatelessWidget {
  final OperatingAreaSummary area;
  final List<AgentSummary> agents;
  const _AssignAgentSheet({required this.area, required this.agents});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(ManaSpacing.lg, ManaSpacing.lg, ManaSpacing.lg, ManaSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(area.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ManaText.raw(area.villagesLabel,
                    style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
              ],
            ),
          ),
          // Only offered once somebody is actually on the area. This is
          // "the agent left and there's no successor yet", NOT a way to run
          // an area without an agent — an Owner who works a round holds an
          // Agent membership and appears in the list below like anyone else.
          if (!area.isUnassigned) ...[
            ListTile(
              leading: const Icon(Icons.person_off_outlined, color: ManaColors.statusBad),
              title: const ManaText('unassign'),
              subtitle: ManaText.raw(
                  'Take ${area.assignedAgentName} off this area. It stops opening account periods until someone else is assigned.',
                  style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
              onTap: () => Navigator.of(context).pop(_AreaAssignmentChoice.unassign()),
            ),
            const Divider(height: 1),
          ],
          if (agents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw(
                  'No Active agents in this business yet — add one from Workforce Management first. '
                  'If you work this round yourself, add yourself as an agent.',
                  style: TextStyle(color: ManaColors.textSecondary, fontSize: 13)),
            )
          else
            ...agents.map((agent) => ListTile(
                  leading: const ManaVerificationRing(isVerified: true, size: 32),
                  title: ManaText.raw(agent.fullName),
                  subtitle: ManaText.raw(agent.mlid, style: const TextStyle(fontSize: 13)),
                  onTap: () => Navigator.of(context).pop(_AreaAssignmentChoice.agent(agent)),
                )),
          const SizedBox(height: ManaSpacing.md),
        ],
      ),
    );
  }
}

class _CycleConfigInput {
  final int duration;
  final String unit;
  final String submissionTime;
  _CycleConfigInput({required this.duration, required this.unit, required this.submissionTime});
}

class _CycleConfigDialog extends StatefulWidget {
  final OperatingAreaSummary initial;
  const _CycleConfigDialog({required this.initial});

  @override
  State<_CycleConfigDialog> createState() => _CycleConfigDialogState();
}

class _CycleConfigDialogState extends State<_CycleConfigDialog> {
  late final _duration = TextEditingController(text: '${widget.initial.accountCycleDuration ?? 3}');
  String _unit = 'Days';
  final _submissionTime = TextEditingController(text: '21:00');

  @override
  void initState() {
    super.initState();
    _unit = widget.initial.accountCycleUnit ?? 'Days';
    if (widget.initial.submissionTime != null) _submissionTime.text = widget.initial.submissionTime!;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const ManaText('configure account cycle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Account Cycle Duration'),
          ),
          const SizedBox(height: ManaSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'Account Cycle Unit'),
            items: const ['Days', 'Weeks', 'Months']
                .map((u) => DropdownMenuItem(value: u, child: ManaText.raw(u)))
                .toList(),
            onChanged: (v) => setState(() => _unit = v ?? _unit),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _submissionTime,
            decoration: const InputDecoration(labelText: 'Submission Time (HH:MM)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const ManaText('cancel')),
        FilledButton(
          onPressed: () {
            final duration = int.tryParse(_duration.text.trim()) ?? 3;
            Navigator.of(context).pop(
              _CycleConfigInput(duration: duration, unit: _unit, submissionTime: _submissionTime.text.trim()),
            );
          },
          child: const ManaText('save'),
        ),
      ],
    );
  }
}

// --- Business Agreements tab -------------------------------------------------

class _AgreementsTab extends ConsumerStatefulWidget {
  final String businessId;
  const _AgreementsTab({required this.businessId});

  @override
  ConsumerState<_AgreementsTab> createState() => _AgreementsTabState();
}

class _AgreementsTabState extends ConsumerState<_AgreementsTab> {
  Future<void> _createAgreement() async {
    final result = await showDialog<_AgreementInput>(
      context: context,
      builder: (_) => const _CreateAgreementDialog(),
    );
    if (result == null || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).createAgreement(
            agreementType: result.type,
            sourceType: result.sourceType,
            contentUrlOrText: result.content,
            effectiveDate: result.effectiveDate,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final agreements = ref.watch(businessDetailProvider(widget.businessId)).agreements;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        const ManaText.raw(
          'Business Agreements are business-specific — a multi-business Owner '
          'sets these independently per MLBI; they do not carry over.',
          style: TextStyle(color: ManaColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: ManaSpacing.md),
        FilledButton.tonalIcon(
          onPressed: _createAgreement,
          icon: const Icon(Icons.add, size: 18),
          label: const ManaText('create agreement'),
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (agreements.isEmpty)
          const ManaText.raw('No agreements created yet.', style: TextStyle(color: ManaColors.textSecondary))
        else
          ...agreements.map((a) => Card(
                child: ListTile(
                  leading: const Icon(Icons.description_outlined, color: ManaColors.ink),
                  title: ManaText.raw('${a.agreementType} Agreement · v${a.version}'),
                  subtitle: ManaText.raw('${a.sourceType} · effective ${a.effectiveDate}'),
                ),
              )),
      ],
    );
  }
}

class _AgreementInput {
  final String type;
  final String sourceType;
  final String content;
  final String effectiveDate;
  _AgreementInput({required this.type, required this.sourceType, required this.content, required this.effectiveDate});
}

class _CreateAgreementDialog extends StatefulWidget {
  const _CreateAgreementDialog();

  @override
  State<_CreateAgreementDialog> createState() => _CreateAgreementDialogState();
}

class _CreateAgreementDialogState extends State<_CreateAgreementDialog> {
  String _type = 'Customer';
  String _sourceType = 'In-App';
  final _content = TextEditingController();
  final _effectiveDate = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final valid = _content.text.trim().isNotEmpty && _effectiveDate.text.trim().isNotEmpty;

    return AlertDialog(
      title: const ManaText('create business agreement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Agreement Type'),
              items: const ['Customer', 'Agent', 'Investor']
                  .map((t) => DropdownMenuItem(value: t, child: ManaText.raw(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: ManaSpacing.md),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Uploaded PDF', label: ManaText.raw('Upload PDF')),
                ButtonSegment(value: 'In-App', label: ManaText.raw('Create Inside App')),
              ],
              selected: {_sourceType},
              onSelectionChanged: (s) => setState(() => _sourceType = s.first),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _content,
              decoration: InputDecoration(
                labelText: _sourceType == 'Uploaded PDF' ? 'Document URL' : 'Agreement Text',
              ),
              maxLines: _sourceType == 'Uploaded PDF' ? 1 : 4,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _effectiveDate,
              decoration: const InputDecoration(labelText: 'Effective Date (YYYY-MM-DD)'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const ManaText('cancel')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(_AgreementInput(
                    type: _type,
                    sourceType: _sourceType,
                    content: _content.text.trim(),
                    effectiveDate: _effectiveDate.text.trim(),
                  ))
              : null,
          child: const ManaText('save'),
        ),
      ],
    );
  }
}

// --- Business Members tab ----------------------------------------------------

class _MembersTab extends ConsumerStatefulWidget {
  final String businessId;
  const _MembersTab({required this.businessId});

  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  Future<void> _addExisting(String role) async {
    final personId = await showDialog<String>(
      context: context,
      builder: (_) {
        final controller = TextEditingController();
        return AlertDialog(
          title: ManaText('add existing $role'.toLowerCase()),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'MLID'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const ManaText('cancel')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const ManaText('add'),
            ),
          ],
        );
      },
    );
    if (personId == null || personId.isEmpty || !mounted) return;

    await NetworkErrorHandler.run(context, () async {
      final notifier = ref.read(businessDetailProvider(widget.businessId).notifier);
      return role == 'Agent'
          ? notifier.addExistingAgent(personId: personId)
          : notifier.addExistingCustomer(personId: personId);
    });
  }

  Future<void> _decideInvestorRequest(MembershipRequestSummary request, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await showDialog<String>(
        context: context,
        builder: (_) {
          final controller = TextEditingController();
          return AlertDialog(
            title: const ManaText('reject investor request'),
            content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Reason')),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const ManaText('cancel')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                child: const ManaText('reject'),
              ),
            ],
          );
        },
      );
      if (reason == null || !mounted) return;
    }
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(widget.businessId).notifier).decideInvestorRequest(
            requestId: request.requestId,
            approve: approve,
            rejectionReason: reason,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessDetailProvider(widget.businessId));
    final pendingInvitations = state.members.where((m) => m.membershipStatus == 'Pending Invitation').toList();
    final pendingAcceptance = state.members.where((m) => m.membershipStatus == 'Pending Acceptance').toList();
    final active = state.members.where((m) => m.membershipStatus == 'Active').toList();

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Wrap(
          spacing: ManaSpacing.sm,
          runSpacing: ManaSpacing.sm,
          children: [
            OutlinedButton(onPressed: () => _addExisting('Agent'), child: const ManaText('add existing agent')),
            OutlinedButton(
                onPressed: () => _addExisting('Customer'), child: const ManaText('add existing customer')),
          ],
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (state.membershipRequests.isNotEmpty) ...[
          const ManaText('request queue (investors)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: ManaSpacing.sm),
          ...state.membershipRequests.map((r) => Card(
                child: ListTile(
                  leading: const ManaVerificationRing(isVerified: false, size: 36),
                  title: ManaText.raw(r.fullName),
                  subtitle: ManaText.raw(
                    r.proposedInvestmentAmount != null
                        ? 'Proposed: ₹${r.proposedInvestmentAmount!.toStringAsFixed(0)}'
                        : r.requestedRole,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: ManaColors.statusBad),
                        onPressed: () => _decideInvestorRequest(r, false),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check, color: ManaColors.statusGood),
                        onPressed: () => _decideInvestorRequest(r, true),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: ManaSpacing.lg),
        ],
        if (pendingInvitations.isNotEmpty) ...[
          const ManaText('pending invitations', style: TextStyle(fontWeight: FontWeight.bold)),
          ...pendingInvitations.map((m) => _MemberRow(businessId: widget.businessId, member: m)),
          const SizedBox(height: ManaSpacing.lg),
        ],
        if (pendingAcceptance.isNotEmpty) ...[
          const ManaText('pending acceptance', style: TextStyle(fontWeight: FontWeight.bold)),
          ...pendingAcceptance.map((m) => _MemberRow(businessId: widget.businessId, member: m)),
          const SizedBox(height: ManaSpacing.lg),
        ],
        const ManaText('active members', style: TextStyle(fontWeight: FontWeight.bold)),
        if (active.isEmpty)
          const ManaText.raw('No active members yet.', style: TextStyle(color: ManaColors.textSecondary))
        else
          ...active.map((m) => _MemberRow(businessId: widget.businessId, member: m)),
      ],
    );
  }
}

class _MemberRow extends ConsumerWidget {
  final String businessId;
  final MemberSummary member;
  const _MemberRow({required this.businessId, required this.member});

  ManaStatus get _statusKind => switch (member.membershipStatus) {
        'Active' => ManaStatus.good,
        'Pending Invitation' || 'Pending Acceptance' || 'Pending Approval' => ManaStatus.warn,
        'Suspended' || 'Removed' => ManaStatus.bad,
        _ => ManaStatus.neutral,
      };

  Future<void> _changeStatus(BuildContext context, WidgetRef ref, String status) async {
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(businessId).notifier).updateMembershipStatus(
            membershipId: member.membershipId,
            status: status,
          );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // BUG FIXED this pass: Business Members had no status-change action
    // at all — Agent/Investor/Customer profiles all already have one
    // (their own PopupMenuButton in the AppBar), this was the one place
    // an Owner couldn't suspend/reactivate/remove a member. The Owner's
    // own row is exempt — never offer to suspend/remove yourself.
    return Card(
      child: ListTile(
        leading: const ManaVerificationRing(isVerified: true, size: 36),
        title: ManaText.raw(member.fullName),
        subtitle: ManaText.raw(member.role),
        trailing: member.role == 'Owner'
            ? ManaStatusPill(label: member.membershipStatus, status: _statusKind)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ManaStatusPill(label: member.membershipStatus, status: _statusKind),
                  PopupMenuButton<String>(
                    onSelected: (status) => _changeStatus(context, ref, status),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'Active', child: ManaText('reactivate')),
                      PopupMenuItem(value: 'Suspended', child: ManaText('suspend')),
                      PopupMenuItem(value: 'Removed', child: ManaText('remove')),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

// --- Account Periods tab -----------------------------------------------------

/// Item 9: this tab was a dead end. It said "No Account Periods yet." and
/// stopped — true, but useless, because nothing on screen said where an
/// Account Period comes from. It comes from ONE place: assigning an
/// Operating Area to an Agent seeds that area's first Running period
/// (assignOperatingAreaToAgent -> _seedFirstAccountPeriodIfNeeded). An
/// Owner with five areas and no agents could stare at this forever.
///
/// So the empty state names the actual reason out of the three that are
/// possible, and routes to the tab that fixes it.
class _AccountPeriodsEmptyState extends StatelessWidget {
  final List<OperatingAreaSummary> areas;
  const _AccountPeriodsEmptyState({required this.areas});

  @override
  Widget build(BuildContext context) {
    final active = areas.where((a) => a.status == 'Active').toList();
    final assigned = active.where((a) => !a.isUnassigned).toList();

    final (String headline, String detail) = switch ((active.isEmpty, assigned.isEmpty)) {
      // No areas at all — the first domino, upstream of everything.
      (true, _) => (
          'No operating areas yet',
          'An account period covers one operating area. Add an area first, '
              'then assign it to an agent.',
        ),
      // Areas exist, none assigned. An unassigned area isn't being worked
      // at all, so it opens no period — assigning an agent is the whole
      // answer, and it is the only answer.
      (false, true) => (
          'No agent is assigned to an area yet',
          'Account periods open when you assign an operating area to an agent. '
              'None of your ${active.length} areas has one yet. If you work a '
              'round yourself, add yourself as an agent and assign it to you.',
        ),
      // Assigned areas exist but no period — shouldn't happen, so don't
      // pretend to explain it.
      (false, false) => (
          'No account periods yet',
          '${assigned.length} of your areas are assigned to an agent, so a '
              'period was expected here. Pull to refresh; if it stays empty '
              'this is worth reporting.',
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.event_note_outlined, size: 40, color: ManaColors.textSecondary),
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(headline,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: ManaColors.textSecondary)),
          const SizedBox(height: ManaSpacing.lg),
          FilledButton.tonalIcon(
            // Same DefaultTabController this tab is already inside, so this
            // is a tab switch, not a navigation push — the Owner stays put.
            onPressed: () => DefaultTabController.of(context).animateTo(0),
            icon: const Icon(Icons.location_on_outlined, size: 18),
            label: const ManaText('go to operating areas'),
          ),
        ],
      ),
    );
  }
}

class _AccountPeriodsTab extends ConsumerWidget {
  final String businessId;
  const _AccountPeriodsTab({required this.businessId});

  ManaStatus _statusKind(String status) => switch (status) {
        'Running' => ManaStatus.good,
        'Overdue' => ManaStatus.bad,
        'Submitted' => ManaStatus.warn,
        _ => ManaStatus.neutral, // Approved / Locked
      };

  Future<void> _reviewSubmitted(BuildContext context, WidgetRef ref, AccountPeriodSummary period) async {
    // Inline Owner Review — no separate screen (spec NAVIGATION note).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const ManaText('approve account period?'),
        content: ManaText.raw(
          '${period.operatingAreaLabel} · ${period.agentName}\n'
          'Approving locks this Account Period. Locked accounts cannot be modified.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const ManaText('cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const ManaText('approve')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await NetworkErrorHandler.run(context, () async {
      return ref
          .read(businessDetailProvider(businessId).notifier)
          .approveAccountPeriod(accountPeriodId: period.accountPeriodId);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessDetailProvider(businessId));
    final periods = state.accountPeriods;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        if (periods.isEmpty)
          _AccountPeriodsEmptyState(areas: state.operatingAreas)
        else
          ...periods.map((p) => Card(
                child: ListTile(
                  title: ManaText.raw('${p.operatingAreaLabel} · ${p.agentName}'),
                  subtitle: ManaText.raw(
                    '${p.businessStartDate.toIso8601String().split("T").first} → '
                    '${p.plannedBusinessEndDate.toIso8601String().split("T").first}',
                  ),
                  trailing: p.status == 'Submitted'
                      ? FilledButton(
                          onPressed: () => _reviewSubmitted(context, ref, p),
                          child: const ManaText('review'),
                        )
                      : ManaStatusPill(label: p.status, status: _statusKind(p.status)),
                ),
              )),
      ],
    );
  }
}
