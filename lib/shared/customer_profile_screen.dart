import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/components/mana_app_bar.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import 'customer_profile_state.dart';
import 'location_api_service.dart';
import 'mlti_upgrade_sheet.dart';
import 'mlti_upgrade_state.dart';
import 'network_error_handler.dart';
import 'translation_service.dart';
import 'widgets/village_search_field.dart';

/// One customer, in full — and the one place their details can be corrected.
///
/// WHY IT EXISTS. Nothing in this app showed a customer after registration.
/// The badge on a collection row opened the MLTI upgrade sheet, which asks for
/// an Aadhaar, a date of birth and a photo because its job is converting a
/// temporary ID — so there was no way to simply LOOK at somebody, and a
/// mistyped mobile number was permanent.
///
/// The Owner's instruction was to open this from the identity symbol rather
/// than from a long press, and they were right: a long press on a settled row
/// already corrects a collection, and that is the one gesture on this screen
/// that moves money.
///
/// WHAT IS EDITABLE IS DECIDED BY WHAT THE SERVER ALREADY ACCEPTS, not by what
/// would be convenient to draw. Mobile, date of birth, Aadhaar and photo have
/// `app.owner_update_member_identity`; door number, PIN and village have
/// `app.owner_update_customer_address`. Name, care-of and gender have neither,
/// and gender is not merely missing an RPC — the MLID is built from it, so
/// changing it would leave an ID that no longer describes its owner. Those
/// three are shown, labelled, and not editable, with the reason on screen.
class ManaCustomerProfileScreen extends ConsumerStatefulWidget {
  final String customerId;

  /// Where Back goes. The collection round passes its own route so an agent
  /// lands on the round rather than a dashboard they did not come from.
  final String? homeRoute;

  /// Needed only to make a temporary ID permanent, which is a business-scoped
  /// act. Null hides that button rather than failing on it: a profile opened
  /// from somewhere with no business in hand is still worth reading.
  final String? businessId;

  const ManaCustomerProfileScreen({
    super.key,
    required this.customerId,
    this.homeRoute,
    this.businessId,
  });

  @override
  ConsumerState<ManaCustomerProfileScreen> createState() =>
      _ManaCustomerProfileScreenState();
}

class _ManaCustomerProfileScreenState
    extends ConsumerState<ManaCustomerProfileScreen> {
  ManaCustomerProfile? _profile;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;

  final _mobile = TextEditingController();
  final _doorNo = TextEditingController();
  final _aadhaar = TextEditingController();
  DateTime? _dob;
  ManaVillage? _village;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _mobile.dispose();
    _doorNo.dispose();
    _aadhaar.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await NetworkErrorHandler.run(
      context,
      () => ref.read(customerProfileApiServiceProvider).fetch(widget.customerId),
    );
    if (!mounted) return;
    setState(() {
      _profile = p;
      _loading = false;
      if (p != null) {
        _mobile.text = p.mobile;
        _doorNo.text = p.doorNo;
        _dob = p.dob == null ? null : DateTime.tryParse(p.dob!);
      }
    });
  }

  Future<void> _save() async {
    final p = _profile;
    if (p == null) return;
    setState(() => _saving = true);
    final api = ref.read(customerProfileApiServiceProvider);

    final ok = await NetworkErrorHandler.run(context, () async {
      // NULL MEANS "LEAVE IT", which is what the RPC's COALESCE is for. Sending
      // the unchanged value back would be harmless today and a silent
      // overwrite the day somebody edits the same person from two devices.
      final mobile = _mobile.text.trim();
      final aadhaar = _aadhaar.text.trim();
      await api.updateIdentity(
        personId: p.personId,
        mobileNumber: mobile == p.mobile ? null : mobile,
        dob: _dob == null
            ? null
            : '${_dob!.year.toString().padLeft(4, '0')}-'
                '${_dob!.month.toString().padLeft(2, '0')}-'
                '${_dob!.day.toString().padLeft(2, '0')}',
        aadhaarNumber:
            p.aadhaarIsLocked || aadhaar.isEmpty ? null : aadhaar,
        profilePhotoUrl: null,
      );

      // The address is only written when there is a village to write it
      // against: owner_update_customer_address derives mandal, district and
      // state from it, so a door number with no village has nowhere to go.
      final villageId = _village?.locationId ?? p.villageId;
      if (villageId != null && villageId.isNotEmpty) {
        await api.updateAddress(
          personId: p.personId,
          doorNo: _doorNo.text.trim(),
          pinCode: _village?.pinCode ?? p.pinCode,
          villageId: villageId,
        );
      }
      return true;
    });

    if (!mounted) return;
    setState(() => _saving = false);
    if (ok != true) return;
    setState(() => _editing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: ManaText.raw(ref.t('profile_saved'))),
    );
    // Read back rather than patching the local copy: the RPCs normalise what
    // they store, and the screen should show what is on the server.
    await _load();
  }

  /// Turn a temporary ID into a permanent one.
  ///
  /// MOVED HERE FROM THE COLLECTION ROW, where it was what the identity symbol
  /// did. The symbol opens this screen now, and the capability had to keep its
  /// home rather than be deleted with the tap that reached it: an Aadhaar card
  /// is in the customer's house, and the agent collecting at the door is the
  /// only person ever standing next to it.
  ///
  /// SEPARATE FROM THE AADHAAR FIELD IN EDIT MODE, and they are not the same
  /// act. `owner_update_member_identity` records an Aadhaar against a person;
  /// only `app.convert_customer_to_mlpi` re-mints the MLID from it. Editing
  /// the field on a temporary person would leave MLTI printed on a receipt for
  /// somebody whose Aadhaar is on file -- so the conversion gets its own
  /// button, and its own sheet, which already asks for the photo and the date
  /// of birth that conversion requires.
  Future<void> _makePermanent(String businessId) async {
    final person = await ref
        .read(mltiUpgradeApiServiceProvider)
        .fetchOneByCustomer(widget.customerId);
    if (!mounted) return;
    if (person == null) {
      // Converted by somebody else since this screen loaded. Re-read rather
      // than complain -- the screen is stale, not wrong.
      await _load();
      return;
    }
    final mlid = await MltiUpgradeSheet.open(
      context,
      person: person,
      businessId: businessId,
    );
    if (mlid == null || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ManaText.raw(ref
          .t('id_now_permanent')
          .replaceAll('{name}', person.fullName)
          .replaceAll('{mlid}', mlid)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      appBar: ManaAppBar(
        title: ref.t('customer_profile'),
        homeRoute: widget.homeRoute,
        actions: [
          if (p != null && !_editing)
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: ManaText.raw(ref.t('profile_edit')),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : p == null
                ? Center(
                    child: ManaText.raw(ref.t('profile_could_not_load'),
                        style: ManaType.secondary),
                  )
                : ListView(
                    padding: const EdgeInsets.all(ManaSpacing.lg),
                    children: _editing ? _editBody(p) : _viewBody(p),
                  ),
      ),
    );
  }

  // --- view -----------------------------------------------------------------

  List<Widget> _viewBody(ManaCustomerProfile p) => [
        _header(p),
        const SizedBox(height: ManaSpacing.lg),
        _section(ref.t('profile_identity_section')),
        _row(ref.t('full_name'), p.fullName),
        _row(ref.t('father_husband_name'), p.careOf),
        _row(ref.t('gender'), _genderLabel(p.genderDigit)),
        _row(ref.t('profile_dob'), _dayMonthYear(p.dob)),
        _row(
          ref.t('profile_aadhaar_on_file'),
          // NEVER THE WHOLE NUMBER. Only the last four are kept in the clear;
          // the rest exists as a hash. A screen that printed it would be
          // printing something the database deliberately does not hold.
          p.aadhaarLast4 == null || p.aadhaarLast4!.isEmpty
              ? ref.t('profile_not_on_file')
              : '•••• •••• ${p.aadhaarLast4}',
        ),
        const SizedBox(height: ManaSpacing.md),
        _section(ref.t('profile_contact_section')),
        _row(ref.t('mobile_number'),
            p.mobile.isEmpty ? ref.t('profile_not_on_file') : p.mobile),
        const SizedBox(height: ManaSpacing.md),
        _section(ref.t('profile_address_section')),
        _row(ref.t('village'),
            p.village.isEmpty ? ref.t('profile_not_on_file') : p.village),
        _row(ref.t('door_house_no'),
            p.doorNo.isEmpty ? ref.t('profile_not_on_file') : p.doorNo),
        _row(ref.t('pin_code_field'),
            p.pinCode.isEmpty ? ref.t('profile_not_on_file') : p.pinCode),
        if (p.isTemporary && (widget.businessId ?? '').isNotEmpty) ...[
          const SizedBox(height: ManaSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => _makePermanent(widget.businessId!),
            icon: const Icon(Icons.badge_outlined),
            label: ManaText.raw(ref.t('make_permanent')),
          ),
        ],
      ];

  Widget _header(ManaCustomerProfile p) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: ManaColors.brandFaint,
            child: Icon(Icons.person_outline,
                color: ManaColors.brandDeep, size: 28),
          ),
          const SizedBox(width: ManaSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ManaText.raw(p.fullName, style: ManaType.sheetTitle),
                const SizedBox(height: 2),
                // The MLID is quoted down a phone and written on receipts, so
                // it is copyable rather than merely printed.
                InkWell(
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: p.mlid));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: ManaText.raw(ref.t('copied'))),
                    );
                  },
                  child: ManaText.raw(p.mlid, style: ManaType.note),
                ),
                const SizedBox(height: ManaSpacing.xs),
                ManaStatusPill(
                  label: p.isTemporary ? 'MLTI' : 'MLPI',
                  status:
                      p.isTemporary ? ManaStatus.warn : ManaStatus.good,
                ),
              ],
            ),
          ),
        ],
      );

  // --- edit -----------------------------------------------------------------

  List<Widget> _editBody(ManaCustomerProfile p) => [
        _header(p),
        const SizedBox(height: ManaSpacing.md),
        // SAID OUT LOUD RATHER THAN LEFT TO BE DISCOVERED. Three fields on
        // this screen cannot be changed, and a form that simply omits them
        // reads as an oversight.
        ManaText.raw(ref.t('profile_readonly_note'), style: ManaType.note),
        const SizedBox(height: ManaSpacing.md),
        _section(ref.t('profile_contact_section')),
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          decoration: InputDecoration(labelText: ref.t('mobile_number')),
        ),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _dob ?? DateTime(1990),
              firstDate: DateTime(1900),
              // A date of birth in the future is not a typo worth storing.
              lastDate: DateTime.now(),
            );
            if (picked != null && mounted) setState(() => _dob = picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: ref.t('profile_dob')),
            child: ManaText.raw(_dob == null
                ? ref.t('profile_not_on_file')
                : '${_dob!.day.toString().padLeft(2, '0')}/'
                    '${_dob!.month.toString().padLeft(2, '0')}/${_dob!.year}'),
          ),
        ),
        const SizedBox(height: ManaSpacing.md),
        if (p.aadhaarIsLocked)
          ManaText.raw(ref.t('profile_aadhaar_locked'), style: ManaType.note)
        else
          TextField(
            controller: _aadhaar,
            keyboardType: TextInputType.number,
            maxLength: 12,
            decoration:
                InputDecoration(labelText: ref.t('aadhaar_optional_note')),
          ),
        const SizedBox(height: ManaSpacing.md),
        _section(ref.t('profile_address_section')),
        TextField(
          controller: _doorNo,
          decoration: InputDecoration(labelText: ref.t('door_house_no')),
        ),
        const SizedBox(height: ManaSpacing.sm),
        // The same field every other screen uses to choose a village. Leaving
        // it untouched keeps the village they already have — _save falls back
        // to the stored id.
        ManaVillageSearchField(
          label: ref.t('village_name_field'),
          initialPin: p.pinCode.isEmpty ? null : p.pinCode,
          onPicked: (v) => setState(() => _village = v),
        ),
        const SizedBox(height: ManaSpacing.lg),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : ManaText.raw(ref.t('profile_save')),
              ),
            ),
            const SizedBox(width: ManaSpacing.sm),
            TextButton(
              onPressed: _saving
                  ? null
                  : () {
                      // Discard: put the controllers back to what is stored,
                      // so leaving edit mode never half-applies anything.
                      setState(() {
                        _editing = false;
                        _village = null;
                        _aadhaar.clear();
                        _mobile.text = p.mobile;
                        _doorNo.text = p.doorNo;
                        _dob = p.dob == null ? null : DateTime.tryParse(p.dob!);
                      });
                    },
              child: ManaText.raw(ref.t('cancel')),
            ),
          ],
        ),
      ];

  // --- bits -----------------------------------------------------------------

  /// 1 male, 0 female, 2 others -- the digits app.mint_person_mlid is given
  /// and the MLID then carries. Anything else is a row nothing in this app
  /// should have written, and it reads as unanswered rather than as a guess.
  String _genderLabel(String digit) => switch (digit) {
        '1' => ref.t('male'),
        '0' => ref.t('female'),
        '2' => ref.t('others'),
        _ => ref.t('profile_not_on_file'),
      };

  /// A stored date is `YYYY-MM-DD`; a date read at a doorstep is not. Edit
  /// mode already showed DD/MM/YYYY and view mode showed the raw column, so
  /// the same date changed shape when the Edit button was pressed.
  String _dayMonthYear(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) return ref.t('profile_not_on_file');
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: ManaSpacing.xs),
        child: ManaText.raw(title, style: ManaType.strong),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        // Wrap, not Row: a Telugu label beside a long value does not share a
        // 360dp line at a 2.0x text scale, and a bare child next to a flexible
        // one is the overflow this project has shipped four times.
        child: Wrap(
          spacing: ManaSpacing.sm,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ManaText.raw(label, style: ManaType.note),
            ManaText.raw(value, style: ManaType.smallStrong),
          ],
        ),
      );
}
