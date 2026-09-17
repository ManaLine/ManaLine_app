import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../design/components/mana_stored_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../design/tokens/icons.dart';
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
import '../../login_registration/state/auth_flow_state.dart';
import '../state/owner_workspace_state.dart';
import '../state/owner_api_service.dart' show AgentSummary;
import 'ow_018_business_migration.dart';
import 'ow_019_cheti_management.dart';
import '../../../design/components/mana_info_hint.dart';
import '../../../shared/widgets/village_picker_field.dart';
import '../../../shared/widgets/village_search_field.dart';
import '../../../shared/location_api_service.dart';
import 'ow_one_by_one_migration.dart';
import '../../../shared/widgets/mana_tab_heading.dart';

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
                  ManaStoredImage(
                    bucket: 'business-logos',
                    stored: business.logoUrl,
                    builder: (context, image) => CircleAvatar(
                      backgroundColor: ManaColors.inkFaint,
                      backgroundImage: image,
                      child: image == null
                          ? Icon(Icons.storefront, color: ManaColors.textSecondary)
                          : null,
                    ),
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
                      icon: ManaIcons.investor,
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

  /// The village picked for the BUSINESS address. Never resolved into a
  /// `locations` row: a registered office is not an operating area, and
  /// writing one would put a place into the operating directory that no
  /// collection round ever visits.
  ManaVillage? _addressVillage;
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
            // Composed from the picked village, so a stored address always
            // carries mandal, district, state and PIN. Falls back to whatever
            // was typed when no village was picked — the field is optional.
            businessAddress: _addressVillage != null
                ? manaComposeAddress(
                    doorNo: _businessAddress.text, village: _addressVillage!)
                : (_businessAddress.text.trim().isEmpty
                    ? null
                    : _businessAddress.text.trim()),
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
          // The path, not a year-long signed URL -- see ManaStoredFile.
          await Supabase.instance.client
              .from('businesses')
              .update({'logo_url': path}).eq('business_id', businessId);
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
            // Door number plus a picked village, the same process registration
            // uses. This was one free-text box two lines tall, so two people
            // typing the same place produced two different addresses and
            // neither carried a PIN.
            TextField(
              controller: _businessAddress,
              decoration: InputDecoration(labelText: ref.t('door_no_street_field')),
            ),
            const SizedBox(height: ManaSpacing.sm),
            ManaVillageSearchField(
              label: ref.t('business_address_field'),
              onPicked: (v) => setState(() => _addressVillage = v),
            ),
            if (_addressVillage != null) ...[
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw(
                manaComposeAddress(
                    doorNo: _businessAddress.text, village: _addressVillage!),
                style: ManaType.note,
              ),
            ],
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
        appBar: ManaAppBar(
          homeRoute: '/ow-012',
          title: detail?.summary.businessName ?? ref.t('business_detail'),
          actions: [
            // OW-018 — for a business that was already running before it
            // joined. Lives here rather than on OW-001 because it is a
            // one-off setup act, not daily work.
            // ADD A USER, FIRST. The body used to carry this as a full-width
            // outlined button sharing a row with the sort, which is a lot of
            // a 360dp screen spent on an action that is not what an Owner
            // opens this tab to do -- they open it to look at people. The
            // header is where every other screen in this app puts its add.
            IconButton(
              tooltip: ref.t('add_a_user'),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () =>
                  context.push('/ow-search', extra: widget.businessId),
            ),
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
              icon: const Icon(ManaIcons.cheti),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChetiManagementScreen(businessId: widget.businessId),
                ),
              ),
            ),
          ],
          // ONE HEADING, CENTRED, instead of five labels in a scrolling strip.
          //
          // isScrollable meant the strip itself scrolled sideways, so the tabs
          // past the second were off the edge with nothing saying they were
          // there -- the Owner had to discover them by dragging a row of text
          // that did not look draggable. Now the screen names the section it
          // is showing and puts a chevron on each side, so the fact that there
          // is more sideways is visible rather than inferred.
          //
          // The TabBar itself is GONE, not restyled. Swiping still works
          // because TabBarView owns that gesture, not the bar, and the
          // DefaultTabController and its positional mapping to
          // BusinessDetailTab are untouched -- but nothing here is a TabBar
          // any more, and anything looking for Tab widgets will not find them.
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: ManaTabHeading(
              labels: [
                ref.t('members'),
                ref.t('operating_areas'),
                ref.t('account_periods'),
                ref.t('agreements'),
                ref.t('lending_rules'),
              ],
              onChanged: (i) => ref
                  .read(businessDetailProvider(widget.businessId).notifier)
                  .setTab(BusinessDetailTab.values[i]),
            ),
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
                  _MembersTab(businessId: widget.businessId),
                  _OperatingAreasTab(businessId: widget.businessId),
                  _AccountPeriodsTab(businessId: widget.businessId),
                  _AgreementsTab(businessId: widget.businessId),
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
  final _areaName = TextEditingController();

  /// The village chosen in the shared field.
  ///
  /// This tab used to hand-roll its own PIN box, its own village-name box and
  /// its own results list on top of operatingAreaSearchProvider -- the NINTH
  /// private copy of a village search in this app, and the one Plan 4 missed
  /// when it consolidated the other eight, because it returned a different
  /// type. So the Owner got PIN-only search here while registration had
  /// offered PIN-or-village-name for two builds.
  ManaVillage? _picked;

  @override
  void dispose() {
    _areaName.dispose();
    super.dispose();
  }

  Future<void> _addSelected() async {
    final selected = _picked;
    if (selected == null) return;
    // Default the name to the first village. A one-village round named
    // after its village is the common case and typing it again is friction;
    // the Owner can rename once a second village joins.
    final name = _areaName.text.trim().isEmpty ? selected.name : _areaName.text.trim();
    final ok = await NetworkErrorHandler.run(context, () async {
      // A village the LGD reference knows but no business works in yet has no
      // location_id until this call writes one. resolveId is
      // resolveLocationId's twin -- both short-circuit on an existing id and
      // otherwise call add_location_if_missing with the same six fields.
      final locationId =
          await ref.read(locationApiServiceProvider).resolveId(selected);
      return ref.read(businessDetailProvider(widget.businessId).notifier).addOperatingArea(
            name: name,
            locationId: locationId,
          );
    });
    if (ok == true) {
      // The field clears itself on a fresh pick; what has to be cleared here
      // is the name, and the pick, so the button goes back to disabled rather
      // than offering to add the same village twice.
      setState(() => _picked = null);
      _areaName.clear();
    }
  }

  Future<void> _addVillage(OperatingAreaSummary area) async {
    // ManaVillage, not LocationOption. The sheet pops whatever the shared
    // field produced, and a stale type argument here would NOT fail to
    // compile -- Navigator.pop takes a dynamic -- it would throw on the cast
    // the first time somebody picked a village.
    final picked = await showModalBottomSheet<ManaVillage>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VillagePickerSheet(areaName: area.name),
    );
    if (picked == null || !mounted) return;
    await NetworkErrorHandler.run(context, () async {
      final locationId =
          await ref.read(locationApiServiceProvider).resolveId(picked);
      return ref.read(businessDetailProvider(widget.businessId).notifier).addVillageToArea(
            operatingAreaId: area.operatingAreaId,
            locationId: locationId,
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
    await _remove(area, force: false);
  }

  /// Does the removal, and asks a second time if the server says people are
  /// still being collected from there.
  ///
  /// The second question is deliberately a different question, with a count in
  /// it. "Are you sure?" twice teaches people to tap through both; "22 loans
  /// are still being collected in Uranduru" is information they did not have
  /// when they answered the first one.
  Future<void> _remove(OperatingAreaSummary area, {required bool force}) async {
    final result = await NetworkErrorHandler.run(context, () async {
      return ref
          .read(businessDetailProvider(widget.businessId).notifier)
          .removeOperatingArea(
              operatingAreaId: area.operatingAreaId, force: force);
    });
    if (result == null || !mounted) return;

    if (result['status'] == 'blocked') {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: ManaText.raw(ref.t('area_still_has_loans_question')),
          content: ManaText.raw(ref
              .t('area_still_has_loans_note')
              .replaceAll('{count}', '${result['live_loans']}')
              .replaceAll('{area}', area.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: ManaText.raw(ref.t('back')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: ManaColors.statusBad),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: ManaText.raw(ref.t('remove')),
            ),
          ],
        ),
      );
      if (proceed == true && mounted) await _remove(area, force: true);
      return;
    }

    // Deleted outright, or kept as Inactive because account periods reference
    // it. Saying which is the difference between "it is gone" and "it is out
    // of the way", and the Owner will look for it later either way.
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ManaText.raw(result['status'] == 'deleted'
          ? ref.t('area_removed_note').replaceAll('{area}', area.name)
          : ref.t('area_kept_for_history_note').replaceAll('{area}', area.name)),
    ));
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
      builder: (_) => _AssignAgentSheet(
          area: area, agents: agents, businessId: widget.businessId),
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

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(businessDetailProvider(widget.businessId));
    final areas = detail.operatingAreas;

    // areas holds ACTIVE areas only; the summary counts every row. When those
    // disagree, this business has areas that were removed and kept for their
    // account periods -- and an Owner staring at an empty list needs telling,
    // because their agents are meanwhile reading "No areas enabled for you
    // yet" and neither screen was explaining the other.
    final removedCount =
        (detail.detail?.summary.operatingAreaCount ?? areas.length) - areas.length;

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
        // The same field registration uses: PIN by default, village name for
        // somebody who does not know their postal code. What it replaces was
        // two bare boxes and a results list wired to this screen's own
        // provider -- PIN-only in practice, because the village-name box
        // could not search without a PIN beside it.
        ManaVillageSearchField(
          label: ref.t('village_name_field'),
          onPicked: (v) => setState(() => _picked = v),
        ),
        const SizedBox(height: ManaSpacing.md),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _picked == null ? null : _addSelected,
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
          ManaText.raw(
            removedCount > 0
                ? ref
                    .t('only_removed_areas_note')
                    .replaceAll('{count}', '$removedCount')
                : ref.t('no_operating_areas_yet'),
            style: ManaType.secondary,
          )
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
                      // The cycle configuration is gone: an account runs from
                      // the last submission to the next one, so there is no
                      // duration, unit or submission time to report. What is
                      // worth saying about an area is where it is.
                      subtitle: ManaText.raw(a.villagesLabel, style: ManaType.note),
                      trailing: PopupMenuButton<String>(
                        tooltip: ref.t('area_options'),
                        onSelected: (v) => switch (v) {
                          'rename' => _rename(a),
                          'village' => _addVillage(a),
                          _ => _removeArea(a),
                        },
                        itemBuilder: (_) => [
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

/// Mandal and district for a village row, for telling near-identical names
/// apart in a list a PIN can fill with fifty entries.
///
/// Empty when the reference carries neither, which is what the callers check
/// "Add a village to <area>", from the Operating Areas tab.
///
/// WHAT THIS REPLACES: a PIN box, a village-name box and a results list, all
/// wired to this screen's own operatingAreaSearchProvider. It was the ninth
/// private copy of a village search in the app and the one Plan 4 missed when
/// it consolidated the other eight -- missed because it returned a
/// LocationOption rather than a ManaVillage, which is a difference in
/// plumbing and not one an Owner can see.
///
/// It now uses the same field as registration: PIN by default, village name
/// for somebody who does not know their postal code.
class _VillagePickerSheet extends ConsumerStatefulWidget {
  final String areaName;
  const _VillagePickerSheet({required this.areaName});

  @override
  ConsumerState<_VillagePickerSheet> createState() =>
      _VillagePickerSheetState();
}

class _VillagePickerSheetState extends ConsumerState<_VillagePickerSheet> {
  ManaVillage? _picked;

  @override
  Widget build(BuildContext context) {
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
            ManaText.raw(
                ref.t('add_village_to_note').replaceAll('{area}', widget.areaName),
                style: ManaType.sheetTitle),
            const SizedBox(height: ManaSpacing.md),
            ManaVillageSearchField(
              label: ref.t('village_name_field'),
              onPicked: (v) => setState(() => _picked = v),
            ),
            const SizedBox(height: ManaSpacing.lg),
            FilledButton(
              // Disabled until something is actually chosen: the field emits
              // null when a pick is edited away or the mode is switched, and
              // adding whatever was picked before that would file a village
              // the Owner had already changed their mind about.
              onPressed:
                  _picked == null ? null : () => Navigator.of(context).pop(_picked),
              child: ManaText.raw(ref.t('add')),
            ),
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
  final String businessId;
  const _AssignAgentSheet(
      {required this.area, required this.agents, required this.businessId});

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
          // Anyone already on the round is filtered out -- assigning the same
          // agent twice is rejected by uq_area_assignment_live.
          ...() {
            final assignable = agents
                .where((agent) =>
                    !area.assignedAgents.any((a) => a.agentId == agent.agentId))
                .toList();
            return [
              // A REAL ACTION, not a heading.
              //
              // This was a bold grey label with a list under it, and the list
              // was the assignable agents. With every agent already on the
              // round that list is empty and `agents.isEmpty` is FALSE, so
              // neither the rows nor the "no active agents" note rendered:
              // the words "Add an Agent" sat over a blank gap, which is
              // exactly what "add an agent is not working" looked like.
              //
              // It goes to Universal Search now, which is the one way into
              // the business for every kind of member. Assigning somebody who
              // is already an Agent and adding a new one are two different
              // errands, and this sheet only ever offered the first while
              // being named for the second.
              ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: ManaText.raw(ref.t('add_an_agent')),
                trailing: const Icon(Icons.chevron_right),
                // The sheet closes first. Pushing a screen over a modal sheet
                // leaves the sheet underneath to come back to, which is not
                // where somebody who has just gone looking for a new agent
                // wants to land.
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/ow-search', extra: businessId);
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(ManaSpacing.lg,
                    ManaSpacing.md, ManaSpacing.lg, ManaSpacing.xs),
                child: ManaText.raw(ref.t('assign_to_this_round'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: ManaColors.textSecondary)),
              ),
              // Both empty cases say something. The second one -- agents
              // exist but every one of them is already on this round -- is
              // the case that used to render nothing at all.
              if (assignable.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  child: ManaText.raw(
                      agents.isEmpty
                          ? ref.t('no_active_agents_note')
                          : ref.t('every_agent_already_on_this_round_note'),
                      style: ManaType.note),
                ),
              ...assignable
                  .map((agent) => ListTile(
                        leading: const ManaVerificationRing(
                            isVerified: true, size: 32),
                        title: ManaText.raw(agent.fullName),
                        subtitle:
                            ManaText.raw(agent.mlid, style: ManaType.small),
                        onTap: () => Navigator.of(context)
                            .pop(_AreaAssignmentChoice.agent(agent)),
                      )),
            ];
          }(),
          const SizedBox(height: ManaSpacing.md),
        ],
      ),
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
              // isExpanded: a DropdownButton sizes to its widest item's natural
              // width and overflows rather than shrinking. A dialog is narrower
              // than a screen, so this is the tightest place one can sit -- three
              // were measured overflowing at 1.0x, in English, by 127px, 233px and
              // 180px. See ow_011_day_closure.dart's adjustment dialog.
              isExpanded: true,
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
  // _addExisting is gone, and with it the two MLID dialogs.
  //
  // They asked for a MANA LINE ID typed from memory, into a box that could
  // not search, could not tell you whether the ID belonged to the person you
  // meant, and offered nothing at all if you did not have one. Two buttons --
  // "Add Existing Agent" and "Add Existing Customer" -- each opened their own
  // copy of it, and neither could add an Investor at all.
  //
  // One link now, to Universal Search: it takes a phone number, an MLID, an
  // Aadhaar or a name, shows the village that tells two people of one name
  // apart, and asks which of the three roles before adding.

  /// Name or village. Name first, because looking somebody up is the commoner
  /// errand; village is for planning a round.
  bool _byVillage = false;

  /// The village currently open, or null with them all closed.
  ///
  /// Only meaningful while [_byVillage] is on, and cleared when the sort
  /// changes so switching back does not leave a village open under a list
  /// that is no longer grouped.
  String? _openVillage;

  /// Active members grouped under their village, A to Z.
  ///
  /// The no-village group is LAST and named rather than hidden. Somebody with
  /// no current address on file is a real state, and dropping them from a
  /// village-sorted roster would quietly shorten the book.
  /// Which role the roster is narrowed to, or null for everybody.
  ///
  /// A PERSON, NOT A MEMBERSHIP, is still the row -- somebody who is both an
  /// Agent and a Customer appears under either filter, once. The filter asks
  /// "does this person do that here", which is the question an Owner is
  /// actually asking when they pick one.
  String? _roleFilter;

  List<Widget> _villageGroups(List<MemberSummary> members, bool migrationOpen) {
    final byVillage = <String, List<MemberSummary>>{};
    for (final m in members) {
      byVillage.putIfAbsent(m.village.trim(), () => []).add(m);
    }
    final names = byVillage.keys.toList()
      ..sort((a, b) {
        if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return [
      for (final name in names) ...[
        Card(
          margin: const EdgeInsets.only(bottom: ManaSpacing.sm),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: ManaText.raw(
                    name.isEmpty ? ref.t('no_village_on_file') : name),
                subtitle: ManaText.raw(
                  ref
                      .t('members_count_note')
                      .replaceAll('{count}',
                          '${manaRosterByPerson(byVillage[name]!).length}'),
                  style: ManaType.note,
                ),
                trailing: Icon(_openVillage == name
                    ? Icons.expand_less
                    : Icons.expand_more),
                onTap: () => setState(
                    () => _openVillage = _openVillage == name ? null : name),
              ),
              if (_openVillage == name)
                ...manaRosterByPerson(byVillage[name]!).map((who) => _MemberRow(
                      businessId: widget.businessId,
                      person: who,
                      migrationOpen: migrationOpen,
                    )),
            ],
          ),
        ),
      ],
    ];
  }

  /// Sorted copy, never the provider's list in place.
  ///
  /// An empty village sorts LAST rather than first. A member with no current
  /// address on file is a real state, and burying the addressed majority under
  /// the unaddressed few would make the sort useless for the round it exists
  /// for. Name is the tie-break within a village, so a village's people read
  /// alphabetically too.
  List<MemberSummary> _sorted(List<MemberSummary> members) {
    final list = [...members];
    list.sort((a, b) {
      if (_byVillage) {
        final av = a.village.trim().toLowerCase();
        final bv = b.village.trim().toLowerCase();
        if (av.isEmpty != bv.isEmpty) return av.isEmpty ? 1 : -1;
        final byVillage = av.compareTo(bv);
        if (byVillage != 0) return byVillage;
      }
      return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(businessDetailProvider(widget.businessId));
    final members = _sorted(state.members);
    final pendingInvitations = members.where((m) => m.membershipStatus == 'Pending Invitation').toList();
    final pendingAcceptance = members.where((m) => m.membershipStatus == 'Pending Acceptance').toList();
    // ITEM 4, AND THE HALF OF IT THAT IS NOT A WORD.
    //
    // "Active Members" was literally true and quietly useless: the list was
    // filtered to Active, so suspending somebody made them VANISH from the
    // only screen that lists members. There was no orange row to look at
    // because there was no row at all, and an Owner who suspended the wrong
    // person had nowhere to go and undo it.
    //
    // The heading is "Members" now and the list is everybody whose state the
    // ring can show -- active, suspended, removed. The two Pending sections
    // above keep their own headings, because an unanswered invitation is a
    // thing waiting on somebody else rather than a state of the membership,
    // and it needs words rather than a colour.
    const shown = {'Active', 'Suspended', 'Removed'};
    final roster = members
        .where((m) => shown.contains(m.membershipStatus))
        // The role filter narrows MEMBERSHIPS, which is what makes it narrow
        // people correctly: manaRosterByPerson groups whatever it is given,
        // so filtering first means a person with two roles appears under
        // either filter and once under All.
        .where((m) => _roleFilter == null || m.role == _roleFilter)
        .toList();
    // Unknown counts as locked. The missed-entry door is only meaningful
    // while a migration is open, and offering it on a business whose detail
    // has not loaded would put a dead link in front of the Owner.
    final migrationOpen = state.detail?.migrationLocked == false;

    return ListView(
      padding: const EdgeInsets.all(ManaSpacing.lg),
      children: [
        // The button and the sort on ONE line.
        //
        // They were stacked, which cost a whole row of a 360dp screen to a
        // control with two options. The sort is a dropdown now rather than a
        // segmented pair for the same reason: "Village (A-Z)" and
        // "Name (A-Z)" side by side left no room for the button beside them.
        //
        // Flexible, not fixed: a Telugu label is longer than its English, and
        // a fixed-width child beside a flexible one is the overflow this
        // project has shipped four times.
        Row(
          children: [
            Flexible(
              // THE ROLE FILTER, where the Add button used to be. An Owner
              // opening this tab is looking for somebody, and "which kind"
              // narrows two hundred rows faster than any sort does.
              //
              // ALL IS KEPT AND IS THE DEFAULT. The Owner named three
              // options; without a fourth the screen would lose the one thing
              // it could do before, which is show the whole book at once --
              // and an Owner counting heads against a page counts everybody.
              child: DropdownButtonFormField<String?>(
                initialValue: _roleFilter,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  labelText: ref.t('role'),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                      value: null, child: ManaText.raw(ref.t('all'))),
                  for (final r in const ['Customer', 'Agent', 'Investor'])
                    DropdownMenuItem(
                        value: r,
                        child: ManaText.raw(
                            ref.t(switch (r) {
                              'Customer' => 'customers',
                              'Agent' => 'agents',
                              _ => 'investors',
                            }),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _roleFilter = v;
                  _openVillage = null;
                }),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            Flexible(
              child: DropdownButtonFormField<bool>(
                initialValue: _byVillage,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  labelText: ref.t('sort_by'),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                      value: false,
                      child: ManaText.raw(ref.t('sort_by_name'),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(
                      value: true,
                      child: ManaText.raw(ref.t('sort_by_village'),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _byVillage = v ?? false;
                  _openVillage = null;
                }),
              ),
            ),
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
          ...manaRosterByPerson(pendingInvitations).map((who) => _MemberRow(
              businessId: widget.businessId,
              person: who,
              migrationOpen: migrationOpen)),
          const SizedBox(height: ManaSpacing.lg),
        ],
        if (pendingAcceptance.isNotEmpty) ...[
          ManaText.raw(ref.t('pending_acceptance_status'), style: ManaType.strong),
          ...manaRosterByPerson(pendingAcceptance).map((who) => _MemberRow(
              businessId: widget.businessId,
              person: who,
              migrationOpen: migrationOpen)),
          const SizedBox(height: ManaSpacing.lg),
        ],
        ManaText.raw(ref.t('members'), style: ManaType.strong),
        // THE ONE PLACE THE GESTURES ARE NAMED. Taking the three dots off
        // every row also took away the only thing on screen saying suspend
        // and remove exist, and a gesture nobody is told about is a feature
        // nobody has. Said once, here, rather than drawn on two hundred rows
        // -- and only when there are rows for it to describe.
        if (roster.isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.xs),
          ManaText.raw(ref.t('members_gesture_hint'), style: ManaType.note),
          const SizedBox(height: ManaSpacing.xs),
        ],
        if (roster.isEmpty)
          ManaText.raw(ref.t('no_active_members_yet'), style: ManaType.secondary)
        else if (_byVillage)
          // SORTED BY VILLAGE MEANS THE VILLAGES ARE THE LIST.
          //
          // It used to mean the people were still the list, merely ordered by
          // where they live -- which on a book of two hundred is two hundred
          // rows with the village repeated down the side, and no answer to
          // "how many are in Someswaram". The villages come first now, each
          // with its count, and open to show who is in them.
          ..._villageGroups(roster, migrationOpen)
        else
          ...manaRosterByPerson(roster).map((who) => _MemberRow(
              businessId: widget.businessId,
              person: who,
              migrationOpen: migrationOpen)),
      ],
    );
  }
}

/// One person on the roster, with every role they hold on this book.
class ManaRosterPerson {
  /// Everybody one person is on this book, as one row.
  ///
  /// ONE ROW PER PERSON, NOT PER MEMBERSHIP. business_members is keyed
  /// (person_id, business_id, role), so somebody who is both an Agent and a
  /// Customer has two rows in the table -- and had two rows on this screen,
  /// identical but for one word. Six people on the live books hold more than
  /// one role and every Owner is also an Agent, so this was not a corner.
  ///
  /// The roles collapse into letters instead: C, A, I, joined by "&", which
  /// is the Owner's own notation.
  final List<MemberSummary> memberships;
  const ManaRosterPerson(this.memberships);

  /// The membership every person-level fact is read from -- name, MLID,
  /// village, care-of, status. All of this person's memberships carry the
  /// same value for each, because they are facts about the person.
  MemberSummary get any => memberships.first;

  String get personId => any.personId;
  String get status => any.membershipStatus;

  bool get isOwner => memberships.any((m) => m.role == 'Owner');
}

/// Groups a roster into one entry per person, keeping the order it arrived in.
///
/// The list is already sorted -- by name, or by village then name -- and both
/// orders put one person's memberships next to each other, so preserving
/// insertion order preserves the sort.
///
/// Public because the guard test builds a roster and asserts the letters.
List<ManaRosterPerson> manaRosterByPerson(List<MemberSummary> members) {
  final byPerson = <String, List<MemberSummary>>{};
  for (final m in members) {
    byPerson.putIfAbsent(m.personId, () => []).add(m);
  }
  return [for (final e in byPerson.values) ManaRosterPerson(e)];
}

class _MemberRow extends ConsumerWidget {
  final String businessId;
  final ManaRosterPerson person;

  /// Whether this book is still being migrated. The missed-entry door is
  /// offered only while it is: once the migration is locked there is no
  /// pre-existing entry left to add, and the door would be a dead link.
  final bool migrationOpen;
  const _MemberRow({
    required this.businessId,
    required this.person,
    this.migrationOpen = false,
  });

  /// Which stage of the one-by-one door a given membership belongs to.
  ///
  /// Null for an Owner and for anyone whose MLID did not come back, because
  /// the door is keyed by MLID and has nothing to open without one.
  ManaEntryStage? _entryStageOf(MemberSummary member) {
    if (!migrationOpen || member.mlid.isEmpty) return null;
    return switch (member.role) {
      'Agent' => ManaEntryStage.agents,
      'Investor' => ManaEntryStage.investors,
      'Customer' => ManaEntryStage.customers,
      _ => null,
    };
  }

  /// The door that was built and never opened.
  ///
  /// OneByOneMigrationScreen has taken an `onlyMlid` since it was written --
  /// the whole point being that finishing ONE person's entry should not mean
  /// walking the wizard's seven pages again -- and nothing in the app passed
  /// one. This is the caller. A member roster is where an Owner notices
  /// somebody was missed, so it is where the way to fix it belongs.
  void _openEntry(BuildContext context, ManaEntryStage stage,
      MemberSummary member) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OneByOneMigrationScreen(
        businessId: businessId,
        initialStage: stage,
        onlyMlid: member.mlid,
      ),
    ));
  }

  /// The ring's colour on THIS list, which is membership status rather than
  /// identity verification.
  ///
  /// The Owner's rule, in their words: active green, suspended red, removed
  /// orange. The ring was already on every row and already green, so this is
  /// the circle finally saying something -- and it is what let the word
  /// "Active" come off the heading. A heading saying Active over rows that
  /// include suspended people is worse than one saying nothing.
  Color get _ringColor => switch (person.status) {
        'Active' => ManaColors.statusGood,
        'Suspended' => ManaColors.statusBad,
        'Removed' => ManaColors.statusWarn,
        _ => ManaColors.textSecondary,
      };

  ManaStatus get _statusKind => switch (person.status) {
        'Active' => ManaStatus.good,
        'Pending Invitation' || 'Pending Acceptance' || 'Pending Approval' =>
          ManaStatus.warn,
        'Suspended' || 'Removed' => ManaStatus.bad,
        _ => ManaStatus.neutral,
      };

  /// Which of this person's roles the action is about.
  ///
  /// Asked only when it is a real question. Suspending somebody who is both
  /// an Agent and a Customer is two different decisions -- an Owner may well
  /// want to stop them collecting and go on lending to them -- and choosing
  /// one silently would make the other unreachable. With a single role there
  /// is nothing to ask and no sheet is shown.
  Future<MemberSummary?> _pickRole(
    BuildContext context,
    WidgetRef ref,
    List<MemberSummary> among,
  ) async {
    if (among.isEmpty) return null;
    if (among.length == 1) return among.first;
    return showModalBottomSheet<MemberSummary>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: ManaText.raw(ref.t('which_role'), style: ManaType.strong),
            ),
            const Divider(height: 1),
            for (final m in among)
              ListTile(
                title: ManaText.raw(m.role),
                onTap: () => Navigator.pop(sheetContext, m),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeStatus(BuildContext context, WidgetRef ref,
      String status, MemberSummary member) async {
    // WARN, DO NOT BLOCK, when the Owner is removing their own Agent role.
    //
    // It is authorised and it is legitimate: business_members_owner_all lets
    // the Owner change any membership in their own business, and somebody who
    // hires two agents and stops collecting themselves is an ordinary
    // business. Forbidding it would be the app deciding how a book is run.
    //
    // What it must not do is let the Owner find out the next time they open a
    // collection round. An Owner is created with BOTH memberships precisely
    // because the owner of a village book usually works it themselves, so
    // removing the agent half changes what they can do tomorrow.
    if (status == 'Removed' && member.role == 'Agent') {
      final me = ref.read(authFlowProvider).personId;
      if (me != null && me == member.personId) {
        final go = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: ManaText.raw(ref.t('remove')),
            content: ManaText.raw(ref.t('owner_agent_removal_warning')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: ManaText.raw(ref.t('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: ManaText.raw(ref.t('remove')),
              ),
            ],
          ),
        );
        if (go != true || !context.mounted) return;
      }
    }
    await NetworkErrorHandler.run(context, () async {
      return ref.read(businessDetailProvider(businessId).notifier).updateMembershipStatus(
            membershipId: member.membershipId,
            status: status,
          );
    });
  }

  /// What a tap on the row does, and what it says when it cannot do it.
  ///
  /// THE TAP IS THE ERRAND. An Owner opens this roster while entering a book
  /// from paper, and the thing they are doing to nine rows out of ten is
  /// finishing somebody's entry. That is the tap; the three-dot menu that
  /// used to hold it is gone.
  ///
  /// When there is nowhere to go it says which of the two reasons applies.
  /// Silence on a tap reads as a broken row, and the reasons differ: a locked
  /// migration is the BOOK being finished, a missing MLID is one PERSON's
  /// record being incomplete.
  Future<void> _tap(BuildContext context, WidgetRef ref) async {
    final open = [
      for (final m in person.memberships)
        if (_entryStageOf(m) != null) m,
    ];
    if (open.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: ManaText.raw(person.any.mlid.isEmpty
            ? ref.t('entry_needs_mlid_note')
            : ref.t('entry_closed_note')),
      ));
      return;
    }
    final chosen = await _pickRole(context, ref, open);
    if (chosen == null || !context.mounted) return;
    _openEntry(context, _entryStageOf(chosen)!, chosen);
  }

  /// Suspend, remove, reactivate -- behind a three-second hold.
  ///
  /// THE OWNER'S RULE, and the reason the menu is not a menu any more: these
  /// sat one tap away on a three-dot button, beside the errand above, on a
  /// row an Owner taps constantly. Taking somebody off a book is not a
  /// neighbour of finishing their entry.
  ///
  /// A BOTTOM SHEET rather than a popup, because there is no longer a button
  /// for a popup to hang off, and because a sheet arrives under the thumb of
  /// somebody holding the phone one-handed.
  ///
  /// REACTIVATE IS NOT OFFERED TO SOMEBODY ACTIVE. It was, and it was the
  /// Owner's complaint: an option that cannot mean anything still has to be
  /// read and dismissed, and on a row that IS active it invites the thought
  /// that they might not be.
  Future<void> _holdActions(BuildContext context, WidgetRef ref) async {
    final active = person.status == 'Active';
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: ManaText.raw(person.any.fullName,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: ManaText.raw(person.status, style: ManaType.note),
            ),
            const Divider(height: 1),
            // Remove first, then Suspend: the Owner's own order.
            ListTile(
              leading: Icon(Icons.person_remove_outlined,
                  color: ManaColors.statusBad),
              title: ManaText.raw(ref.t('remove')),
              onTap: () => Navigator.pop(sheetContext, 'Removed'),
            ),
            if (person.status != 'Suspended')
              ListTile(
                leading: const Icon(Icons.pause_circle_outline),
                title: ManaText.raw(ref.t('suspend')),
                onTap: () => Navigator.pop(sheetContext, 'Suspended'),
              ),
            if (!active)
              ListTile(
                leading: Icon(Icons.play_circle_outline,
                    color: ManaColors.statusGood),
                title: ManaText.raw(ref.t('reactivate')),
                onTap: () => Navigator.pop(sheetContext, 'Active'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final which = await _pickRole(context, ref, person.memberships);
    if (which == null || !context.mounted) return;
    await _changeStatus(context, ref, choice, which);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Owner's own row is exempt from both gestures -- never offer to
    // suspend or remove yourself, and an Owner has no pre-existing entry.
    final owner = person.isOwner;
    final member = person.any;
    return Card(
      child: _HoldForActions(
        enabled: !owner,
        onTap: owner ? null : () => _tap(context, ref),
        onHold: () => _holdActions(context, ref),
        child: ListTile(
          leading: ManaVerificationRing(
              isVerified: true, size: 36, ringColor: _ringColor),
          // THE NAME GETS THE ROW. It used to share it with the status pill
          // and the menu, both in `trailing`, and ListTile hands trailing its
          // intrinsic width FIRST -- so "Pending Invitation" plus a 48dp menu
          // button left the title about one character wide and "Ashok Goud"
          // came down the screen a letter per line. One line, ellipsised: a
          // name that does not fit is cut, not folded.
          title: ManaText.raw(
            member.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          // C/O AND VILLAGE, NOT THE ROLE. The role used to be the first
          // thing on this line and is a letter at the end of it now, which
          // frees the words for what actually identifies somebody: in a
          // village where three men are called Ramesh the care-of name is
          // the only thing that separates them. The village stays because it
          // is what the Village sort orders by, and a sort you cannot see
          // the key of looks like it did nothing.
          subtitle: Row(
            children: [
              Flexible(
                child: ManaText.raw(
                  [
                    if (member.fatherHusbandName.isNotEmpty)
                      '${ref.t('care_of')} ${member.fatherHusbandName}',
                    if (member.village.isNotEmpty) member.village,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // THE STATUS PILL ONLY WHEN IT IS NOT ACTIVE. The ring carries
              // the state now and the Owner asked for the word "Active" to
              // go. Suspended and Removed keep their words, because a colour
              // on its own is a legend nobody was given -- and those are the
              // two rows where being sure matters.
              if (person.status != 'Active') ...[
                const SizedBox(width: ManaSpacing.sm),
                ManaTrailingStatus(label: person.status, status: _statusKind),
              ],
              // THE C / A / I LETTERS ARE GONE, one build after they were
              // added. They were the Owner's own request and they read
              // correctly on the handset -- and then the role moved into a
              // filter above the list, which says the same thing in words and
              // does something with it. A letter repeating what the dropdown
              // already states is two answers to one question.
              //
              // ManaRosterPerson.roleLetters went with them. It had one
              // reader and this was it; the filter reasons about
              // MemberSummary.role directly. Keeping a getter nothing calls
              // because it was written yesterday is how dead code gets a
              // sentimental defence.
            ],
          ),
          // NO TRAILING WIDGET AT ALL. The three-dot button that lived here
          // is what item 5 asked to be rid of, and nothing replaces it: the
          // row's whole width is the tap target for the errand, and the hold
          // is the way to the rest. The list's own heading says so once,
          // rather than every row carrying an affordance.
        ),
      ),
    );
  }
}

class _HoldForActions extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback onHold;
  final bool enabled;
  const _HoldForActions({
    required this.child,
    required this.onTap,
    required this.onHold,
    required this.enabled,
  });

  @override
  State<_HoldForActions> createState() => _HoldForActionsState();
}

class _HoldForActionsState extends State<_HoldForActions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      // Fired. The tap that arrives on release must not also open the entry
      // screen behind the sheet.
      _fired = true;
      HapticFeedback.mediumImpact();
      _hold.value = 0;
      widget.onHold();
    });

  bool _fired = false;

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _down() {
    if (!widget.enabled) return;
    _fired = false;
    _hold.forward(from: 0);
  }

  /// A release, a drag away, or the list scrolling under the finger. All three
  /// mean the same thing: the hold did not happen.
  void _up() {
    if (_hold.isAnimating) _hold.stop();
    _hold.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      onTap: () {
        if (_fired) {
          _fired = false;
          return;
        }
        widget.onTap?.call();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.child,
          // Two pixels, and zero-width until a finger is down, so a settled
          // list looks exactly as it did.
          AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => SizedBox(
              height: 2,
              child: _hold.value == 0
                  ? null
                  : LinearProgressIndicator(
                      value: _hold.value,
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                    ),
            ),
          ),
        ],
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
                            // An open account has no end to show. It used to
                            // print a predicted one, which read as a deadline
                            // and was the forecast-as-boundary mistake in
                            // visible form -- the Owner saw a date the agent
                            // routinely worked past.
                            ManaText.raw(
                              '${p.businessStartDate.toIso8601String().split("T").first} → '
                              '${p.plannedBusinessEndDate?.toIso8601String().split("T").first ?? ref.t("until_submitted")}',
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

