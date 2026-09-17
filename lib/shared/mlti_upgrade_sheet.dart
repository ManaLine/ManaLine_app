import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../design/components/mana_app_bar.dart';
import '../design/components/mana_fit_text.dart';
import '../design/components/mana_text.dart';
import '../design/tokens/colors.dart';
import '../design/tokens/spacing.dart';
import '../design/tokens/typography.dart';
import 'live_face_capture_screen.dart';
import 'live_photo_upload.dart';
import 'photo_compression.dart';
import 'mlti_upgrade_state.dart';
import 'translation_service.dart';

final _dobFmt = DateFormat('dd MMM yyyy');

/// The form that turns one temporary ID into a permanent one.
///
/// ONE FORM, TWO DOORS. The Owner reaches it from the Temporary IDs list; the
/// agent reaches it by tapping the marker on a customer in the collection
/// round. The agent's door is the important one — an Aadhaar card is at the
/// customer's house, not in an office — and a second implementation of this
/// form would be a second place for the Aadhaar rules to drift.
///
/// Returns the new MLID when a conversion happened, null when it did not.
class MltiUpgradeSheet extends ConsumerStatefulWidget {
  final MltiPerson person;
  final String businessId;

  const MltiUpgradeSheet({
    super.key,
    required this.person,
    required this.businessId,
  });

  static Future<String?> open(
    BuildContext context, {
    required MltiPerson person,
    required String businessId,
  }) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (_) => MltiUpgradeSheet(person: person, businessId: businessId),
      );

  @override
  ConsumerState<MltiUpgradeSheet> createState() => _MltiUpgradeSheetState();
}

class _MltiUpgradeSheetState extends ConsumerState<MltiUpgradeSheet> {
  final _aadhaar = TextEditingController();
  DateTime? _dob;
  Uint8List? _photo;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _aadhaar.dispose();
    super.dispose();
  }

  String get _digits => _aadhaar.text.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _takePhoto() async {
    final bytes = await LiveFaceCaptureScreen.capture(context);
    if (bytes == null || !mounted) return;
    setState(() => _photo = bytes);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 30),
      // Nobody borrowing money is under 18 or over 120. A picker that offers
      // next week invites a typo that becomes a permanent record.
      firstDate: DateTime(now.year - 120),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked == null || !mounted) return;
    setState(() => _dob = picked);
  }

  Future<void> _submit() async {
    // THE AADHAAR IS THE ONLY REQUIREMENT, and this is the second version of
    // this method. The first demanded a photograph and a date of birth too,
    // which was a stricter standard than the app applies to the 34 people who
    // already hold a permanent ID -- 30 of them have no date of birth and 28
    // no photograph. The Owner settled it: "MLPI generates once Aadhar number
    // (only) provided, along with that other profile or kyc update is user's
    // choice."
    //
    // Checked here AND in the RPC. This one says which field is missing before
    // a round trip; the server's exists because a client check is not a rule.
    if (_digits.length != 12) {
      setState(() => _error = ref.t('aadhaar_12_digits'));
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Only when one was taken. The photo goes up before the RPC and the RPC
      // is told its PATH, not the bytes: if the conversion then fails, an
      // orphaned object is the cost, which is the right way round -- the
      // alternative is converting the identity and then losing a photograph
      // that had to be taken in person.
      String? path;
      if (_photo != null) {
        path = await LivePhotoUpload.upload(
          bytes: _photo!,
          businessId: widget.businessId,
          pathSegment: 'persons/${widget.person.personId}',
          preset: ManaPhotoPreset.profile,
        );
      }
      final mlid = await ref.read(mltiUpgradeApiServiceProvider).convert(
            personId: widget.person.personId,
            businessId: widget.businessId,
            aadhaarNumber: _digits,
            dob: _dob,
            livePhotoUrl: path,
          );
      if (!mounted) return;
      Navigator.of(context).pop(mlid);
    } catch (e) {
      if (!mounted) return;
      // SHOWN AS IT CAME. Every failure this RPC raises is a sentence written
      // for a person -- "This Aadhaar Number is already associated with an
      // existing account" is the most useful thing this screen can say, since
      // it means the customer is in the book twice. A generic message would
      // throw that away.
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst(RegExp(r'^[A-Za-z]*Exception[: ]*'), '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.person;
    final identity = [
      if (p.careOf.isNotEmpty) 'C/o ${p.careOf}',
      if (p.village.isNotEmpty) p.village,
    ].join(' · ');

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: ManaSpacing.lg,
          right: ManaSpacing.lg,
          top: ManaSpacing.lg,
          // The keyboard is up the whole time this form is used -- it opens on
          // a number field -- so the sheet has to sit above it or the Save
          // button is behind the keys.
          bottom: MediaQuery.of(context).viewInsets.bottom + ManaSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaFitText(p.fullName, style: ManaType.sheetTitle),
              if (identity.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaFitText(identity, style: ManaType.note),
              ],
              const SizedBox(height: ManaSpacing.xs),
              ManaText.raw('${ref.t('temporary_id')}: ${p.mlid}',
                  style: ManaType.note),
              const SizedBox(height: ManaSpacing.md),

              TextField(
                controller: _aadhaar,
                keyboardType: TextInputType.number,
                autofocus: true,
                // 12 digits, digits only. The number is never stored raw -- the
                // server hashes it and keeps the last four -- so this field is
                // the only place it ever exists in full.
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(12),
                ],
                decoration: InputDecoration(
                  labelText: '${ref.t('aadhaar_number')} *',
                  counterText: '${_digits.length}/12',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ManaSpacing.md),

              // Date of birth and photo as rows rather than fields: neither is
              // typed, and a disabled-looking text box that opens a picker is
              // a control people tap twice.
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cake_outlined),
                title: ManaText.raw(ref.t('date_of_birth')),
                subtitle: ManaText.raw(
                    _dob == null ? ref.t('optional') : _dobFmt.format(_dob!),
                    style: ManaType.note),
                trailing: _dob == null
                    ? const Icon(Icons.chevron_right)
                    : Icon(Icons.check_circle, color: ManaColors.statusGood),
                onTap: _saving ? null : _pickDob,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.camera_alt_outlined),
                title: ManaText.raw(_photo == null
                    ? ref.t('take_live_photo')
                    : ref.t('photo_captured')),
                subtitle: ManaText.raw(
                    _photo == null ? ref.t('optional') : ref.t('retake'),
                    style: ManaType.note),
                trailing: _photo == null
                    ? const Icon(Icons.chevron_right)
                    : Icon(Icons.check_circle, color: ManaColors.statusGood),
                onTap: _saving ? null : _takePhoto,
              ),

              if (_error != null) ...[
                const SizedBox(height: ManaSpacing.sm),
                ManaText.raw(_error!,
                    style: ManaType.note.copyWith(color: ManaColors.statusBad)),
              ],

              const SizedBox(height: ManaSpacing.md),
              // WRAP, NOT ROW, and the layout tests caught this at 1.0x in
              // ENGLISH -- 34 pixels over, on every phone, not just at a large
              // text scale. Two buttons side by side with "Make Permanent" on
              // one of them is wider than a 360dp sheet once its padding is
              // taken off, and a Row has nowhere to put the difference. This
              // is the shape this project has shipped six times.
              //
              // A Wrap drops the second button onto its own line instead, and
              // keeps them right-aligned on both.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: ManaSpacing.sm,
                runSpacing: ManaSpacing.xs,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: ManaText.raw(ref.t('cancel')),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: ManaText.raw(ref.t('make_permanent')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list of everybody on a book still carrying a temporary ID.
class MltiUpgradeScreen extends ConsumerStatefulWidget {
  final String businessId;
  const MltiUpgradeScreen({super.key, required this.businessId});

  @override
  ConsumerState<MltiUpgradeScreen> createState() => _MltiUpgradeScreenState();
}

class _MltiUpgradeScreenState extends ConsumerState<MltiUpgradeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(mltiUpgradeProvider.notifier).load(widget.businessId));
  }

  Future<void> _open(MltiPerson p) async {
    final mlid = await MltiUpgradeSheet.open(
      context,
      person: p,
      businessId: widget.businessId,
    );
    if (mlid == null || !mounted) return;
    ref.read(mltiUpgradeProvider.notifier).forget(p.personId);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: ManaText.raw(ref
          .t('id_now_permanent')
          .replaceAll('{name}', p.fullName)
          .replaceAll('{mlid}', mlid)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mltiUpgradeProvider);

    return Scaffold(
      appBar: ManaAppBar(title: ref.t('temporary_ids'), homeRoute: '/ow-001'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(mltiUpgradeProvider.notifier).load(widget.businessId),
          child: state.loading && state.people.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(ManaSpacing.lg),
                  children: [
                    if (state.people.isNotEmpty) ...[
                      ManaText.raw(ref.t('temporary_id_explainer'),
                          style: ManaType.note),
                      const SizedBox(height: ManaSpacing.md),
                    ],
                    if (state.people.isEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: ManaSpacing.xxl),
                        child: Center(
                          child: ManaText.raw(ref.t('no_temporary_ids'),
                              style: ManaType.secondary),
                        ),
                      ),
                    for (final p in state.people) ...[
                      _PendingCard(person: p, onTap: () => _open(p)),
                      const SizedBox(height: ManaSpacing.sm),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _PendingCard extends ConsumerWidget {
  final MltiPerson person;
  final VoidCallback onTap;
  const _PendingCard({required this.person, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = [
      if (person.careOf.isNotEmpty) 'C/o ${person.careOf}',
      if (person.village.isNotEmpty) person.village,
    ].join(' · ');

    return Card(
      elevation: 0,
      color: ManaColors.surfaceMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ManaSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaFitText(person.fullName, style: ManaType.heavy),
              if (identity.isNotEmpty) ...[
                const SizedBox(height: ManaSpacing.xs),
                ManaFitText(identity, style: ManaType.note),
              ],
              const SizedBox(height: ManaSpacing.xs),
              // The temporary ID itself, because it is what the Owner sees
              // everywhere else and is how they recognise the row.
              ManaText.raw(person.mlid, style: ManaType.note),
            ],
          ),
        ),
      ),
    );
  }
}

/// The way into [MltiUpgradeScreen] from a customer list.
///
/// COUNTED FROM THE LIST THAT IS ALREADY LOADED. Both customer screens carry
/// each person's MLID, and an MLTI is literally what the prefix says — so the
/// banner costs no query at all. Asking the server how many temporary IDs
/// exist, on a screen that is holding the answer, would be a round trip to
/// learn something already in memory.
///
/// It draws nothing when [count] is zero. A permanent banner saying "0
/// temporary IDs" is a row of pixels that never changes and is read once.
class MltiUpgradeBanner extends ConsumerWidget {
  final int count;
  final String businessId;

  const MltiUpgradeBanner({
    super.key,
    required this.count,
    required this.businessId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (count <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          ManaSpacing.lg, ManaSpacing.sm, ManaSpacing.lg, 0),
      child: Material(
        color: ManaColors.statusWarnFaint,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => MltiUpgradeScreen(businessId: businessId),
          )),
          child: Padding(
            padding: const EdgeInsets.all(ManaSpacing.sm),
            child: Row(
              children: [
                Icon(Icons.badge_outlined,
                    size: 18, color: ManaColors.statusWarn),
                const SizedBox(width: ManaSpacing.sm),
                // Flexible, so the sentence gives way rather than the chevron
                // being pushed off a 360dp row at 2.0x in Telugu.
                Flexible(
                  child: ManaFitText(
                    ref.t('temporary_ids_pending').replaceAll('{n}', '$count'),
                    style: ManaType.note,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
