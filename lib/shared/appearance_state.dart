import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// P2 Appearance — how big the text is.
///
/// WHY THERE IS NO DARK MODE HERE, stated plainly so nobody assumes it was
/// forgotten: the app has 840 direct `ManaColors.*` references across 82 files
/// and reads colour from `Theme.of(context)` in exactly zero places. Supplying
/// a dark ThemeData would restyle Material's own chrome and leave every card,
/// label and status pill light — a half-dark screen. In an app where a pill's
/// colour carries money meaning (Short vs Excess, penalty, defaulted) that is
/// worse than staying light. Dark mode is a design-system migration, not a
/// settings toggle, and it is listed as such rather than half-shipped.
///
/// Font size, by contrast, is genuinely ready: every screen is already tested
/// at 1.0x through 2.0x on a 360x640 surface, because text scaling has been a
/// first-class constraint from the start. This just lets a person choose the
/// scale themselves instead of going into Android settings — which matters for
/// Owners who are older than their agents and are reading rupee figures.
enum ManaTextSize {
  small(0.9, 'small'),
  normal(1.0, 'normal'),
  large(1.15, 'large'),
  larger(1.3, 'larger');

  const ManaTextSize(this.scale, this.label);

  final double scale;
  final String label;

  /// Capped at 1.3 deliberately. The layout tests prove the app survives 2.0x,
  /// but that is survival — nothing overflows — not comfort. Above about 1.3
  /// the denser money screens start wrapping figures onto two lines, and a
  /// person who genuinely needs more can still use Android's own display
  /// setting, which stacks on top of this one.
  static ManaTextSize fromName(String? n) =>
      ManaTextSize.values.firstWhere((v) => v.name == n,
          orElse: () => ManaTextSize.normal);
}

class AppearanceNotifier extends Notifier<ManaTextSize> {
  static const _key = 'mana_text_size';

  /// flutter_secure_storage rather than a new preferences dependency. It is
  /// heavier than this preference needs, but it is already used for the PIN
  /// and device fingerprint, and adding a package for one enum is not worth
  /// another build-compatibility risk on AGP 9.
  static const _storage = FlutterSecureStorage();

  @override
  ManaTextSize build() {
    // Loaded after the first frame rather than awaited: the app must not wait
    // on disk to draw its first screen, and one frame at the default size is
    // imperceptible next to a blocked launch.
    _restore();
    return ManaTextSize.normal;
  }

  Future<void> _restore() async {
    try {
      state = ManaTextSize.fromName(await _storage.read(key: _key));
    } catch (_) {
      // A preference that cannot be read is not worth surfacing; the default
      // is a perfectly usable app.
    }
  }

  Future<void> set(ManaTextSize size) async {
    state = size;
    try {
      await _storage.write(key: _key, value: size.name);
    } catch (_) {
      // Applied for this session even if it could not be saved. Telling
      // someone their font choice failed, while showing it visibly working,
      // would be the confusing outcome.
    }
  }
}

final appearanceProvider =
    NotifierProvider<AppearanceNotifier, ManaTextSize>(AppearanceNotifier.new);
