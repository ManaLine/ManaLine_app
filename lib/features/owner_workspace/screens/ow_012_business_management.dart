import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/colors.dart';
import '../../../design/tokens/typography.dart';
import '../../../design/tokens/spacing.dart';
import '../../../design/components/mana_app_bar.dart';
import '../../../design/components/mana_text.dart';
import '../../../design/components/mana_skeleton.dart';
import '../../../shared/network_error_handler.dart';
import '../../../shared/business_name_checker.dart';
import '../../../shared/photo_compression.dart';
import '../../../shared/translation_service.dart';
import '../state/business_management_state.dart';
import '../state/owner_workspace_state.dart';
import '../state/owner_api_service.dart' show AgentSummary;
import 'ow_018_business_migration.dart';
import 'ow_019_cheti_management.dart';
import '../../../design/components/mana_info_hint.dart';

// A failed load previously left every one of this screen's tabs looking
// like a legitimate empty state ("No Operating Areas yet.", "No active
// members yet.") with the real Postgrest/RLS error swallowed into
// `state.error` and never rendered anywhere — indistinguishable from a
// business that genuinely has no data. Surfacing it here so a load
// failure reads as "something broke, tap retry" instead of "empty".
class _ErrorBanner extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 40, color: ManaColors.textSecondary),
            const SizedBox(height: ManaSpacing.md),
            ManaText.raw(ref.t('could_not_load_data')),
            const SizedBox(height: ManaSpacing.sm),
            ManaText.raw(message, textAlign: TextAlign.center, style: ManaType.noteBad),
            const SizedBox(height: ManaSpacing.sm),
            ElevatedButton(onPressed: onRetry, child: ManaText.raw(ref.t('retry'))),
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
      // A business id is enough. It used to also require a tab, so arriving
      // from the drawer — which passes the id the Owner is already working in
      // but no ?tab= — dropped them on the business LIST and asked them to
      // choose a business they had chosen two taps earlier. The tab is a
      // deep-link refinement, not the thing that decides whether we know
      // which business this is.
      if (businessId != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _BusinessDetailScreen(
              businessId: businessId,
              initialTab: widget.initialTab,
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessListProvider);

    // A translated "Create Business" label plus icon can outgrow a narrow
    // phone width at large text scales — FloatingActionButton.extended has
    // no way to shrink its own label, and Scaffold doesn't clip a FAB
    // against the screen edge, so the button just renders partway off
    // screen. Icon-only (with the same label as a tooltip) sidesteps that
    // entirely rather than picking a scale threshold to gate on.
    final bigText = MediaQuery.textScalerOf(context).scale(14) > 20;
    return Scaffold(
      appBar: ManaAppBar(title: ref.t('business_management')),
      floatingActionButton: bigText
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _CreateBusinessScreen()),
              ),
              tooltip: ref.t('create_business'),
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _CreateBusinessScreen()),
              ),
              icon: const Icon(Icons.add),
              label: ManaText.raw(ref.t('create_business')),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(businessListProvider.notifier).load(),
          child: state.loading && state.businesses.isEmpty
              ? const ManaSkeletonList()
              : state.error != null
                  ? _ErrorBanner(message: state.error!, onRetry: () => ref.read(businessListProvider.notifier).load())
              : state.businesses.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(ManaSpacing.xxl),
                      children: [
                        Center(
                          child: ManaText.raw(
                            ref.t('no_businesses_yet_note'),
                            style: ManaType.secondary,
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

class _BusinessSummaryCard extends ConsumerWidget {
  final BusinessSummary business;
  final VoidCallback onTap;
  const _BusinessSummaryCard({required this.business, required this.onTap});

  ManaStatus get _statusKind => switch (business.businessStatus) {
        'Active' => ManaStatus.good,
        'Suspended' => ManaStatus.bad,
        _ => ManaStatus.neutral, // Not Started
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: ManaColors.inkFaint,
                    backgroundImage: business.logoUrl != null ? NetworkImage(business.logoUrl!) : null,
                    child: business.logoUrl == null
                        ? Icon(Icons.storefront, color: ManaColors.textSecondary)
                        : null,
                  ),
                  const SizedBox(width: ManaSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ManaText.raw(business.businessName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge),
                        ManaText.raw(business.mlbi,
                            style: ManaType.note),
                      ],
                    ),
                  ),
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(
                    child: ManaStatusPill(label: business.businessStatus, status: _statusKind),
                  ),
                ],
              ),
              const SizedBox(height: ManaSpacing.md),
              Wrap(
                spacing: ManaSpacing.md,
                runSpacing: ManaSpacing.xs,
                children: [
                  _StatChip(
                      icon: Icons.location_on_outlined,
                      label: ref.t('areas_count_note').replaceAll('{count}', '${business.operatingAreaCount}')),
                  _StatChip(
                      icon: Icons.people_outline,
                      label: ref.t('customers_count_note').replaceAll('{count}', '${business.activeCustomers}')),
                  _StatChip(
                      icon: Icons.badge_outlined,
                      label: ref.t('agents_count_note').replaceAll('{count}', '${business.activeAgents}')),
                  _StatChip(
                      icon: Icons.savings_outlined,
                      label: ref.t('investors_count_note').replaceAll('{count}', '${business.activeInvestors}')),
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
        Flexible(
          child: ManaText.raw(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ManaType.note),
        ),
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

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _businessName.dispose();
    _registeredFinanceName.dispose();
    _businessType.dispose();
    _businessAddress.dispose();
    _businessPhone.dispose();
    _businessEmail.dispose();
    super.dispose();
  }
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
    if (!mounted) return;
    if (!mounted) return;
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
      if (!mounted) return;
      if (chosen != null) setState(() => _businessName.text = chosen);
      return;
    }
    if (!mounted) return;
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
          // Compressed before upload: the business-logos bucket now has a
          // 512KB ceiling, and a gallery pick at full resolution would sail
          // past it and fail. The logo renders at 40px in the header, so
          // there is nothing to lose by resizing it.
          final logoBytes = ManaPhotoCompressor.compress(
              _logoBytes!, ManaPhotoPreset.logo);
          await Supabase.instance.client.storage.from('business-logos').uploadBinary(
                path,
                logoBytes,
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
      if (!mounted) return;
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
      appBar: ManaAppBar(title: ref.t('create_business')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ManaSpacing.lg),
          children: [
            ManaText.raw(
              ref.t('create_business_repeat_note'),
              style: ManaType.secondary,
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
                      ? Icon(Icons.add_a_photo_outlined, color: ManaColors.textSecondary)
                      : null,
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _pickLogo,
                child: ManaText.raw(ref.t(_logoBytes == null ? 'add_business_photo' : 'change_photo')),
              ),
            ),
            TextField(
              controller: _businessName,
              decoration: InputDecoration(labelText: ref.t('business_name_field')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _registeredFinanceName,
              decoration: InputDecoration(labelText: ref.t('registered_finance_name_field')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(controller: _businessType, decoration: InputDecoration(labelText: ref.t('business_type_field'))),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _businessAddress,
              decoration: InputDecoration(labelText: ref.t('business_address_field')),
              maxLines: 2,
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _businessPhone,
              decoration: InputDecoration(labelText: ref.t('business_phone_field')),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _businessEmail,
              decoration: InputDecoration(labelText: ref.t('business_email_field')),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: ManaSpacing.xxl),
            FilledButton(
              onPressed: (_valid && !formState.submitting) ? _submit : null,
              child: formState.submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : ManaText.raw(ref.t('save_business')),
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
      length: 5,
      initialIndex: BusinessDetailTab.values.indexOf(initialTab),
      child: Scaffold(
        appBar: AppBar(
          title: ManaText.raw(detail?.summary.businessName ?? ref.t('business_detail')),
          actions: [
            // OW-018 — for a business that was already running before it
            // joined. Lives here rather than on OW-001 because it is a
            // one-off setup act, not daily work.
            IconButton(
              tooltip: ref.t('pre_existing_business'),
              icon: const Icon(Icons.move_to_inbox_outlined),
              // Navigator, not go_router: this detail screen is pushed as a
              // MaterialPageRoute from the list, so it is outside the
              // router's stack.
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BusinessMigrationScreen(businessId: widget.businessId),
                ),
              ),
            ),
            // OW-019 — the Owner's own chetis. Sits beside migration for the
            // same reason: it is the business's financing, not daily work.
            IconButton(
              tooltip: ref.t('cheti'),
              icon: const Icon(Icons.savings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChetiManagementScreen(businessId: widget.businessId),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            onTap: (i) => ref
                .read(businessDetailProvider(widget.businessId).notifier)
                .setTab(BusinessDetailTab.values[i]),
            tabs: [
              Tab(text: ref.t('operating_areas')),
              Tab(text: ref.t('agreements')),
              Tab(text: ref.t('members')),
              Tab(text: ref.t('account_periods')),
              Tab(text: ref.t('lending_rules')),
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
                  _LendingRulesTab(businessId: widget.businessId),
                ],
              ),
      ),
    );
  }
}

// --- Lending Rules tab -------------------------------------------------------
// Decisions about how this book lends, as opposed to who is in it. One rule
// today; this is where the next one goes rather than a dialog buried in a
// screen that happens to be nearby.

class _LendingRulesTab extends ConsumerWidget {
  final String businessId;
  const _LendingRulesTab({required this.businessId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(businessDetailProvider(businessId));
    final detail = state.detail;
    if (detail == null) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                value: detail.loansRequireExistingCustomer,
                onChanged: (v) => ref
                    .read(businessDetailProvider(businessId).notifier)
                    .setLoansRequireExistingCustomer(v),
                title: ManaText.raw(ref.t('existing_customers_only'), style: ManaType.strong),
                subtitle: ManaText.raw(
                  detail.loansRequireExistingCustomer
                      ? ref.t('existing_customers_only_on_note')
                      : ref.t('existing_customers_only_off_note'),
                  style: ManaType.note,
                ),
              ),
            ],
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(state.error!, style: ManaType.bad),
        ],
      ],
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
        title: ManaText.raw(ref.t('remove_village_question')),
        content: ManaText.raw(
          ref
              .t('remove_village_note')
              .replaceAll('{village}', village.villageTownName)
              .replaceAll('{area}', area.name),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: ManaText.raw(ref.t('cancel'))),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: ManaText.raw(ref.t('remove'))),
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
        title: ManaText.raw(ref.t('remove_operating_area_question')),
        content: ManaText.raw(
          ref
              .t('remove_operating_area_note')
              .replaceAll('{area}', area.name)
              .replaceAll('{villages}', area.villagesLabel),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ManaColors.statusBad),
            onPressed: () => Navigator.of(context).pop(true),
            child: ManaText.raw(ref.t('remove')),
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
        title: ManaText.raw(ref.t('rename_area')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(labelText: ref.t('area_name_field')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: ManaText.raw(ref.t('cancel'))),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: ManaText.raw(ref.t('save')),
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
    if (choice.unassignAgentId != null) {
      await NetworkErrorHandler.run(context, () async {
        return ref.read(businessDetailProvider(businessId).notifier).unassignAgent(
              businessId: businessId,
              operatingAreaId: area.operatingAreaId,
              agentId: choice.unassignAgentId!,
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
        ManaText.raw(
          ref.t('operating_area_intro_note'),
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.md),
        TextField(
          controller: _areaName,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: ref.t('area_name_field'),
            suffixIcon: ManaInfoHint(ref.t('area_name_helper')),
          ),
        ),
        TextField(
          controller: _pinCode,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(labelText: ref.t('pin_code_field')),
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
            label: ManaText.raw(ref.t('add_area')),
          ),
        ),
        const SizedBox(height: ManaSpacing.lg),
        const Divider(),
        const SizedBox(height: ManaSpacing.sm),
        ManaText.raw(ref.t('current_operating_areas'), style: ManaType.strong),
        const SizedBox(height: ManaSpacing.sm),
        if (areas.isEmpty)
          ManaText.raw(ref.t('no_operating_areas_yet'), style: ManaType.secondary)
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
                          if (a.status != 'Active') ...[
                            const SizedBox(width: ManaSpacing.xs),
                            Flexible(
                              child: ManaStatusPill(label: ref.t('inactive'), status: ManaStatus.neutral),
                            ),
                          ],
                        ],
                      ),
                      subtitle: ManaText.raw(a.cycleConfigured
                          ? ref
                              .t('cycle_configured_note')
                              .replaceAll('{duration}', '${a.accountCycleDuration}')
                              .replaceAll('{unit}', '${a.accountCycleUnit}')
                              .replaceAll('{time}', '${a.submissionTime}')
                          : ref.t('account_cycle_not_configured')),
                      trailing: PopupMenuButton<String>(
                        tooltip: ref.t('area_options'),
                        onSelected: (v) => switch (v) {
                          'cycle' => _configureCycle(a),
                          'rename' => _rename(a),
                          'village' => _addVillage(a),
                          _ => _removeArea(a),
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'cycle',
                              child: ManaText.raw(ref.t(a.cycleConfigured ? 'edit_cycle' : 'configure_cycle'))),
                          PopupMenuItem(value: 'rename', child: ManaText.raw(ref.t('rename_area'))),
                          PopupMenuItem(value: 'village', child: ManaText.raw(ref.t('add_village'))),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'remove',
                            child: ManaText.raw(ref.t('remove_area'),
                                style: ManaType.bad),
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
                                    style: ManaType.small),
                                onDeleted: () => _removeVillage(a, v),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                deleteButtonTooltipMessage: 'Remove ${v.villageTownName} from ${a.name}',
                              ),
                            TextButton.icon(
                              onPressed: () => _addVillage(a),
                              icon: const Icon(Icons.add, size: 18),
                              label: ManaText.raw(ref.t('add_village')),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    // A ListTile's trailing slot has a hard width assertion —
                    // built from a plain Row instead, same reasoning as the
                    // blocking-issues row on OW-011.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: ManaSpacing.md, vertical: ManaSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            a.isUnassigned ? Icons.person_off_outlined : Icons.badge_outlined,
                            size: 18,
                            color: a.isUnassigned ? ManaColors.statusWarn : ManaColors.textSecondary,
                          ),
                          const SizedBox(width: ManaSpacing.sm),
                          Expanded(
                            child: ManaText.raw(
                              a.isUnassigned
                                  ? ref.t('no_agent_assigned_not_worked')
                                  : ref
                                      .t(a.assignedAgents.length == 1 ? 'agent_colon_note' : 'agents_colon_note')
                                      .replaceAll('{names}', a.assignedAgentsLabel),
                              style: TextStyle(
                                fontSize: 13,
                                color: a.isUnassigned ? ManaColors.statusWarn : ManaColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: ManaSpacing.sm),
                          Flexible(
                            child: TextButton(
                              onPressed: () => _assignAgent(a),
                              child: ManaText.raw(ref.t(a.isUnassigned ? 'assign_agent' : 'manage_agents')),
                            ),
                          ),
                        ],
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
            ManaText.raw(ref.t('add_village_to_note').replaceAll('{area}', widget.areaName),
                style: ManaType.sheetTitle),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _pinCode,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(labelText: ref.t('pin_code_field')),
              onChanged: (v) {
                if (v.trim().length == 6) {
                  ref.read(operatingAreaSearchProvider.notifier).searchByPin(v.trim());
                }
              },
            ),
            if (search.searching) const Center(child: CircularProgressIndicator()),
            if (!search.searching && search.matches.isEmpty && _pinCode.text.trim().length == 6)
              ManaText.raw(ref.t('no_villages_found_for_pin'),
                  style: ManaType.note),
            ...search.matches.map((m) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.location_on_outlined, color: ManaColors.brand),
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
  /// Set when the Owner chose to take one specific agent off the round.
  final String? unassignAgentId;
  _AreaAssignmentChoice.agent(this.agent) : unassignAgentId = null;
  _AreaAssignmentChoice.unassign(this.unassignAgentId) : agent = null;
}

class _AssignAgentSheet extends ConsumerWidget {
  final OperatingAreaSummary area;
  final List<AgentSummary> agents;
  const _AssignAgentSheet({required this.area, required this.agents});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    style: ManaType.cardTitle),
                ManaText.raw(area.villagesLabel,
                    style: ManaType.note),
              ],
            ),
          ),
          // Agents already on this round, each removable on its own. A
          // round may be shared (GLOBAL BR-065), so taking one person off
          // must not disturb the others.
          if (!area.isUnassigned) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, ManaSpacing.xs),
              child: ManaText.raw(ref.t('working_this_round'),
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: ManaColors.textSecondary)),
            ),
            ...area.assignedAgents.map((a) => ListTile(
                  leading: const ManaVerificationRing(isVerified: true, size: 32),
                  title: ManaText.raw(a.fullName),
                  trailing: TextButton(
                    style: TextButton.styleFrom(foregroundColor: ManaColors.statusBad),
                    onPressed: () =>
                        Navigator.of(context).pop(_AreaAssignmentChoice.unassign(a.agentId)),
                    child: ManaText.raw(ref.t('remove')),
                  ),
                )),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(
                ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, ManaSpacing.xs),
            child: ManaText.raw(ref.t('add_an_agent'),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: ManaColors.textSecondary)),
          ),
          if (agents.isEmpty)
            Padding(
              padding: const EdgeInsets.all(ManaSpacing.lg),
              child: ManaText.raw(
                  ref.t('no_active_agents_note'),
                  style: ManaType.note),
            )
          else
            // Anyone already on the round is filtered out — assigning the
            // same agent twice is rejected by uq_area_assignment_live.
            ...agents
                .where((agent) => !area.assignedAgents.any((a) => a.agentId == agent.agentId))
                .map((agent) => ListTile(
                      leading: const ManaVerificationRing(isVerified: true, size: 32),
                      title: ManaText.raw(agent.fullName),
                      subtitle: ManaText.raw(agent.mlid, style: ManaType.small),
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

class _CycleConfigDialog extends ConsumerStatefulWidget {
  final OperatingAreaSummary initial;
  const _CycleConfigDialog({required this.initial});

  @override
  ConsumerState<_CycleConfigDialog> createState() => _CycleConfigDialogState();
}

class _CycleConfigDialogState extends ConsumerState<_CycleConfigDialog> {
  late final _duration = TextEditingController(text: '${widget.initial.accountCycleDuration ?? 3}');
  String _unit = 'Days';
  final _submissionTime = TextEditingController(text: '21:00');

  @override
  void initState() {
    super.initState();
    _unit = widget.initial.accountCycleUnit ?? 'Days';
    if (widget.initial.submissionTime != null) _submissionTime.text = widget.initial.submissionTime!;
  }

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _submissionTime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: ManaText.raw(ref.t('configure_cycle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: ref.t('account_cycle_duration_field')),
          ),
          const SizedBox(height: ManaSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            decoration: InputDecoration(labelText: ref.t('account_cycle_unit_field')),
            items: [
              DropdownMenuItem(value: 'Days', child: ManaText.raw(ref.t('days'))),
              DropdownMenuItem(value: 'Weeks', child: ManaText.raw(ref.t('weeks'))),
              DropdownMenuItem(value: 'Months', child: ManaText.raw(ref.t('months'))),
            ],
            onChanged: (v) => setState(() => _unit = v ?? _unit),
          ),
          const SizedBox(height: ManaSpacing.md),
          TextField(
            controller: _submissionTime,
            decoration: InputDecoration(labelText: ref.t('submission_time_field')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: ManaText.raw(ref.t('cancel'))),
        FilledButton(
          onPressed: () {
            final duration = int.tryParse(_duration.text.trim()) ?? 3;
            Navigator.of(context).pop(
              _CycleConfigInput(duration: duration, unit: _unit, submissionTime: _submissionTime.text.trim()),
            );
          },
          child: ManaText.raw(ref.t('save')),
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
        ManaText.raw(
          ref.t('business_agreements_note'),
          style: ManaType.note,
        ),
        const SizedBox(height: ManaSpacing.md),
        FilledButton.tonalIcon(
          onPressed: _createAgreement,
          icon: const Icon(Icons.add, size: 18),
          label: ManaText.raw(ref.t('create_agreement')),
        ),
        const SizedBox(height: ManaSpacing.lg),
        if (agreements.isEmpty)
          ManaText.raw(ref.t('no_agreements_yet'), style: ManaType.secondary)
        else
          ...agreements.map((a) => Card(
                child: ListTile(
                  leading: Icon(Icons.description_outlined, color: ManaColors.ink),
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

class _CreateAgreementDialog extends ConsumerStatefulWidget {
  const _CreateAgreementDialog();

  @override
  ConsumerState<_CreateAgreementDialog> createState() => _CreateAgreementDialogState();
}

class _CreateAgreementDialogState extends ConsumerState<_CreateAgreementDialog> {

  // Disposed with the State that owns them.
  //
  // These outlived every visit: a TextEditingController holds a listener list
  // and a ChangeNotifier, and a State that never disposes them leaks one set
  // each time the screen is opened. Attached per class rather than in bulk --
  // disposing a controller that belongs to a different State would be a
  // use-after-dispose, which is worse than the leak.
  @override
  void dispose() {
    _content.dispose();
    _effectiveDate.dispose();
    super.dispose();
  }
  String _type = 'Customer';
  String _sourceType = 'In-App';
  final _content = TextEditingController();
  final _effectiveDate = TextEditingController();

  static const _typeKeys = {'Customer': 'customer', 'Agent': 'agent', 'Investor': 'investor'};

  @override
  Widget build(BuildContext context) {
    final valid = _content.text.trim().isNotEmpty && _effectiveDate.text.trim().isNotEmpty;

    return AlertDialog(
      title: ManaText.raw(ref.t('create_business_agreement')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(labelText: ref.t('agreement_type_field')),
              items: ['Customer', 'Agent', 'Investor']
                  .map((t) => DropdownMenuItem(value: t, child: ManaText.raw(ref.t(_typeKeys[t]!))))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: ManaSpacing.md),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'Uploaded PDF', label: ManaText.raw(ref.t('upload_pdf'))),
                ButtonSegment(value: 'In-App', label: ManaText.raw(ref.t('create_inside_app'))),
              ],
              selected: {_sourceType},
              onSelectionChanged: (s) => setState(() => _sourceType = s.first),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _content,
              decoration: InputDecoration(
                labelText: ref.t(_sourceType == 'Uploaded PDF' ? 'document_url_field' : 'agreement_text_field'),
              ),
              maxLines: _sourceType == 'Uploaded PDF' ? 1 : 4,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: ManaSpacing.md),
            TextField(
              controller: _effectiveDate,
              decoration: InputDecoration(labelText: ref.t('effective_date_ymd_field')),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: ManaText.raw(ref.t('cancel'))),
        FilledButton(
          onPressed: valid
              ? () => Navigator.of(context).pop(_AgreementInput(
                    type: _type,
                    sourceType: _sourceType,
                    content: _content.text.trim(),
                    effectiveDate: _effectiveDate.text.trim(),
                  ))
              : null,
          child: ManaText.raw(ref.t('save')),
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
          title: ManaText.raw(ref.t(role == 'Agent' ? 'add_existing_agent' : 'add_existing_customer')),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: ref.t('mlid_field')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: ManaText.raw(ref.t('cancel'))),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: ManaText.raw(ref.t('add')),
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
            OutlinedButton(onPressed: () => _addExisting('Agent'), child: ManaText.raw(ref.t('add_existing_agent'))),
            OutlinedButton(
                onPressed: () => _addExisting('Customer'), child: ManaText.raw(ref.t('add_existing_customer'))),
          ],
        ),
        const SizedBox(height: ManaSpacing.lg),
        // The investor request queue with its tick/cross buttons used to sit
        // here. It moved to the shared Notifications inbox so an Owner
        // approves a membership request in one place rather than three.
        //
        // The pending GROUPINGS below stay: they are roster information —
        // "who have I invited, who has not answered" — not a second copy of
        // the decision. Reading that here is part of managing a business;
        // deciding it belongs in the inbox.
        if (pendingInvitations.isNotEmpty) ...[
          ManaText.raw(ref.t('pending_invitations_header'), style: ManaType.strong),
          ...pendingInvitations.map((m) => _MemberRow(businessId: widget.businessId, member: m)),
          const SizedBox(height: ManaSpacing.lg),
        ],
        if (pendingAcceptance.isNotEmpty) ...[
          ManaText.raw(ref.t('pending_acceptance_status'), style: ManaType.strong),
          ...pendingAcceptance.map((m) => _MemberRow(businessId: widget.businessId, member: m)),
          const SizedBox(height: ManaSpacing.lg),
        ],
        ManaText.raw(ref.t('active_members'), style: ManaType.strong),
        if (active.isEmpty)
          ManaText.raw(ref.t('no_active_members_yet'), style: ManaType.secondary)
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
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'Active', child: ManaText.raw(ref.t('reactivate'))),
                      PopupMenuItem(value: 'Suspended', child: ManaText.raw(ref.t('suspend'))),
                      PopupMenuItem(value: 'Removed', child: ManaText.raw(ref.t('remove'))),
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
class _AccountPeriodsEmptyState extends ConsumerWidget {
  final List<OperatingAreaSummary> areas;
  const _AccountPeriodsEmptyState({required this.areas});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = areas.where((a) => a.status == 'Active').toList();
    final assigned = active.where((a) => !a.isUnassigned).toList();

    final (String headline, String detail) = switch ((active.isEmpty, assigned.isEmpty)) {
      // No areas at all — the first domino, upstream of everything.
      (true, _) => (
          ref.t('no_operating_areas_yet_headline'),
          ref.t('no_operating_areas_yet_detail'),
        ),
      // Areas exist, none assigned. An unassigned area isn't being worked
      // at all, so it opens no period — assigning an agent is the whole
      // answer, and it is the only answer.
      (false, true) => (
          ref.t('no_agent_assigned_area_headline'),
          ref.t('no_agent_assigned_area_detail').replaceAll('{count}', '${active.length}'),
        ),
      // Assigned areas exist but no period — shouldn't happen, so don't
      // pretend to explain it.
      (false, false) => (
          ref.t('no_account_periods_yet_headline'),
          ref.t('no_account_periods_yet_detail').replaceAll('{count}', '${assigned.length}'),
        ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ManaSpacing.xl),
      child: Column(
        children: [
          Icon(Icons.event_note_outlined, size: 40, color: ManaColors.textSecondary),
          const SizedBox(height: ManaSpacing.md),
          ManaText.raw(headline,
              textAlign: TextAlign.center,
              style: ManaType.cardTitle),
          const SizedBox(height: ManaSpacing.sm),
          ManaText.raw(detail,
              textAlign: TextAlign.center,
              style: ManaType.note),
          const SizedBox(height: ManaSpacing.lg),
          FilledButton.tonalIcon(
            // Same DefaultTabController this tab is already inside, so this
            // is a tab switch, not a navigation push — the Owner stays put.
            onPressed: () => DefaultTabController.of(context).animateTo(0),
            icon: const Icon(Icons.location_on_outlined, size: 18),
            label: ManaText.raw(ref.t('go_to_operating_areas')),
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
        title: ManaText.raw(ref.t('approve_account_period_question')),
        content: ManaText.raw(
          ref
              .t('approve_account_period_note')
              .replaceAll('{area}', period.operatingAreaLabel)
              .replaceAll('{agent}', period.agentName),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: ManaText.raw(ref.t('cancel'))),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: ManaText.raw(ref.t('approve'))),
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
          // A ListTile's trailing slot has a hard width assertion — built
          // from a plain Row instead, same reasoning as OW-011's
          // blocking-issues row.
          ...periods.map((p) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(ManaSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ManaText.raw('${p.operatingAreaLabel} · ${p.agentName}'),
                            ManaText.raw(
                              '${p.businessStartDate.toIso8601String().split("T").first} → '
                              '${p.plannedBusinessEndDate.toIso8601String().split("T").first}',
                              style: ManaType.note,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: ManaSpacing.sm),
                      Flexible(
                        child: p.status == 'Submitted'
                            ? FilledButton(
                                onPressed: () => _reviewSubmitted(context, ref, p),
                                child: ManaText.raw(ref.t('review')),
                              )
                            : ManaStatusPill(label: p.status, status: _statusKind(p.status)),
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }
}
