import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/spacing.dart';
import 'mana_text.dart';

/// Who this person is, at the top of their own profile.
///
/// OW-016 and AG-009 both open on a photo beside a name and an MLID, and both
/// follow it with label/value rows. They differ in exactly one thing that
/// matters, and it is a rule rather than a style: the Owner may change their
/// photo and the Agent may not.
///
/// That rule is [onChangePhoto]. Null means view-only, and view-only means
/// NO affordance is drawn -- not a greyed-out one. A disabled edit button
/// still tells somebody the door exists; AG-009's own note already insisted
/// on this ("deliberately has no `onEdit` affordance of any kind, not even
/// disabled"), and the point survives the move into a shared widget only if
/// it is written down where the widget is built.
///
/// A test asserts it, because a shared component is exactly where a rule like
/// this gets lost: one careless default and an Agent is handed an edit
/// affordance the role is not allowed.
class ManaIdentityHeader extends StatelessWidget {
  final String fullName;
  final String mlid;

  /// Shown under the name when there is one. The Agent's screen shows a
  /// membership status here; the Owner's shows nothing.
  final String? statusLabel;
  final ManaStatus statusKind;

  final String? photoUrl;

  /// The ring's meaning, not a decoration: green edge = identity verified,
  /// red = not (BR-191/GC-002). AG-009 hardcoded true when this lived in two
  /// places; here it has to be stated.
  final bool isVerified;

  /// Announced to a screen reader in place of the photo, and it should name
  /// the ACTION rather than the image -- "Change Profile Photo", not
  /// "photo". Only used when the photo is editable.
  final String? photoActionLabel;

  /// Null = this person may not change their photo, and no control is drawn.
  final VoidCallback? onChangePhoto;

  /// Shows a spinner in place of the photo control while an upload is in
  /// flight. Meaningless when [onChangePhoto] is null.
  final bool savingPhoto;

  /// Label/value rows under the divider. Locked rows carry a padlock; see
  /// [ManaIdentityField].
  final List<ManaIdentityField> fields;

  const ManaIdentityHeader({
    super.key,
    required this.fullName,
    required this.mlid,
    this.statusLabel,
    this.statusKind = ManaStatus.neutral,
    this.photoUrl,
    this.isVerified = true,
    this.photoActionLabel,
    this.onChangePhoto,
    this.savingPhoto = false,
    this.fields = const [],
  });

  bool get _editable => onChangePhoto != null;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ManaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _photo(),
                const SizedBox(width: ManaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ManaText.raw(fullName, style: text.titleLarge),
                      const SizedBox(height: 2),
                      ManaText.raw(mlid, style: text.bodySmall),
                    ],
                  ),
                ),
                if (statusLabel != null) ...[
                  const SizedBox(width: ManaSpacing.xs),
                  Flexible(
                    child: ManaStatusPill(label: statusLabel!, status: statusKind),
                  ),
                ],
              ],
            ),
            if (fields.isNotEmpty) ...[
              const Divider(height: ManaSpacing.xl),
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: ManaSpacing.sm),
                _row(context, fields[i]),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _photo() {
    final ring = ManaVerificationRing(
      isVerified: isVerified,
      photo: photoUrl != null ? NetworkImage(photoUrl!) : null,
      size: 56,
    );

    // No InkWell, no badge, no Semantics button when it is not editable --
    // nothing to press and nothing that looks pressable. This is the rule the
    // Agent's screen depends on.
    if (!_editable) return ring;

    return Semantics(
      button: true,
      label: photoActionLabel,
      excludeSemantics: photoActionLabel != null,
      child: InkWell(
        onTap: savingPhoto ? null : onChangePhoto,
        borderRadius: BorderRadius.circular(999),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            ring,
            // The badge says the photo is changeable, and doubles as the
            // progress indicator during an upload -- which also keeps the
            // tap target past the 48dp floor.
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: ManaColors.brandDeep,
                shape: BoxShape.circle,
              ),
              child: savingPhoto
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: ManaColors.textOnDark),
                    )
                  : Icon(Icons.photo_camera,
                      size: 12, color: ManaColors.textOnDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ManaIdentityField f) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ManaText.raw(f.label, style: text.labelMedium),
              const SizedBox(height: 2),
              ManaText.raw(f.value, style: text.bodyMedium),
            ],
          ),
        ),
        if (f.locked)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.lock_outline,
                size: 16, color: ManaColors.textDisabled),
          ),
      ],
    );
  }
}

/// One label/value row in a [ManaIdentityHeader].
class ManaIdentityField {
  final String label;
  final String value;

  /// Draws a padlock, meaning this cannot be changed from here at all. It is
  /// a statement about the rule, not about the current screen state.
  final bool locked;

  const ManaIdentityField({
    required this.label,
    required this.value,
    this.locked = false,
  });
}
