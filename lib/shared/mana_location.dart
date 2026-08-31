import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// P2 GPS — one place that knows how to get a fix, and how to fail.
///
/// THE GOVERNING RULE: **GPS never blocks anything.** A denied permission, a
/// disabled location service, a village with no sky view, an old handset —
/// none of these may stop a loan being issued or a customer being registered.
/// Every method here returns a [ManaFix] describing what happened rather than
/// throwing, so a caller cannot accidentally make GPS load-bearing by letting
/// an exception escape.
///
/// That is why the outcome is an enum rather than a nullable position: "the
/// user said no" and "we could not get a fix in time" need different words on
/// screen, and a null collapses them into one.
enum ManaFixStatus {
  /// A usable fix. `accuracyM` says how good.
  ok,

  /// The person declined, or declined permanently. Not an error — a choice.
  denied,

  /// Location is switched off on the device.
  serviceOff,

  /// Permission and service are fine, but no fix arrived in time. Common
  /// indoors and in narrow streets.
  timedOut,

  /// Something else went wrong. Carried rather than swallowed.
  failed,
}

class ManaFix {
  final ManaFixStatus status;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final String? detail;

  /// This position came from the phone's last known fix rather than a reading
  /// taken now. Good enough to record and to fill in a PIN code; deliberately
  /// NOT good enough to judge an address by, because its accuracy describes
  /// where the phone was, not where it is.
  final bool fromCache;

  const ManaFix({
    required this.status,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.detail,
    this.fromCache = false,
  });

  bool get hasPosition => status == ManaFixStatus.ok && latitude != null;

  /// Above this, `app.compare_address_gps` returns is_indeterminate and the UI
  /// must say "couldn't verify" rather than "doesn't match". Mirrored here so
  /// a caller can warn before spending time on a comparison the server will
  /// refuse to judge.
  static const indeterminateAboveM = 100.0;

  bool get isTooRoughToJudge =>
      fromCache || (accuracyM != null && accuracyM! > indeterminateAboveM);

  /// What to tell the person. Deliberately not "Error" — most of these are
  /// ordinary conditions in a village, not faults.
  String get message => switch (status) {
        ManaFixStatus.ok when fromCache =>
          "Used this phone's last known location, so the address was not "
              'checked against it.',
        ManaFixStatus.ok => isTooRoughToJudge
            ? 'Location is only accurate to about ${accuracyM!.round()}m, so it '
                'could not be checked against the address.'
            : 'Location captured.',
        ManaFixStatus.denied =>
          'Location permission was not given, so the address was not checked.',
        ManaFixStatus.serviceOff =>
          'Location is switched off on this phone, so the address was not '
              'checked.',
        ManaFixStatus.timedOut =>
          'Could not get a location in time, so the address was not checked.',
        ManaFixStatus.failed =>
          'Location could not be read, so the address was not checked.',
      };
}

class ManaLocation {
  /// A position this phone recorded moments ago is as good as one taken now,
  /// and it arrives instantly. Beyond this it is a different place.
  static const _instantIfNewerThan = Duration(minutes: 2);

  /// Once the fresh attempt has failed, an older fix still beats nothing: a
  /// doorstep ten minutes into the same round is the same village.
  static const _fallbackIfNewerThan = Duration(minutes: 10);

  /// The phone's last recorded position, if it is newer than [maxAge].
  ///
  /// Never throws and never waits — this reads what the platform already has,
  /// which is how Maps and the browser answer instantly on the same handset
  /// where this app was standing there waiting for a satellite.
  static Future<Position?> _lastKnown(Duration maxAge) async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      final at = pos?.timestamp;
      if (pos == null || at == null) return null;
      return DateTime.now().toUtc().difference(at.toUtc()) <= maxAge ? pos : null;
    } on Exception {
      return null;
    }
  }

  static ManaFix _cached(Position pos) => ManaFix(
        status: ManaFixStatus.ok,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyM: pos.accuracy,
        fromCache: true,
      );

  /// Asks for a fix. Never throws.
  ///
  /// THE ORDER MATTERS, and it is why this failed on a phone where Google Maps
  /// was working at the same moment:
  ///
  ///  1. A position recorded in the last two minutes is returned immediately.
  ///     Nothing can be faster, and it is what every other app on the handset
  ///     does. Marked [ManaFix.fromCache].
  ///  2. Otherwise a fresh reading, on a budget long enough to actually get
  ///     one. The old eight seconds asked the radio for a cold fix and gave up
  ///     before it could answer, so "Could not get a location in time" was the
  ///     ordinary outcome rather than the exceptional one.
  ///  3. If that fails, a fix from the last ten minutes rather than nothing.
  ///
  /// A cached position is recorded and fills fields, but never judges an
  /// address — see [ManaFix.fromCache].
  static Future<ManaFix> currentFix({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const ManaFix(status: ManaFixStatus.serviceOff);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const ManaFix(status: ManaFixStatus.denied);
      }

      final recent = await _lastKnown(_instantIfNewerThan);
      if (recent != null) return _cached(recent);

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          // `medium` rather than `best`: best keeps the radio hunting for a
          // tighter fix that this app has no use for, on phones where battery
          // is a real constraint. 100m is the threshold that matters, and
          // medium clears it comfortably outdoors.
          accuracy: LocationAccuracy.medium,
          timeLimit: timeout,
        ),
      );

      return ManaFix(
        status: ManaFixStatus.ok,
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyM: pos.accuracy,
      );
    } on Exception catch (e) {
      // Includes TimeoutException from timeLimit. Separated so the message can
      // say "try again outside" rather than something that sounds like a bug.
      final isTimeout = e.toString().toLowerCase().contains('time');
      final stale = await _lastKnown(_fallbackIfNewerThan);
      if (stale != null) return _cached(stale);
      return ManaFix(
        status: isTimeout ? ManaFixStatus.timedOut : ManaFixStatus.failed,
        detail: e.toString(),
      );
    }
  }

  /// A fix, plus the PIN code and village the platform's geocoder reads back
  /// from it — what the address forms' "use my location" button needs.
  ///
  /// Same never-throw contract as [currentFix]: a failed or empty geocode
  /// still returns the fix, with [ManaPlace.pinCode] and
  /// [ManaPlace.village] left null. Losing the labels must not lose the
  /// coordinates, because the coordinates are the part that cannot be
  /// retyped later.
  ///
  /// Uses the platform geocoder, not a web service — no API key and no
  /// per-lookup billing. It is also frequently vague in rural India, which
  /// is exactly why every field it fills stays editable: this button saves
  /// typing, it does not decide the address.
  static Future<ManaPlace> currentPlace({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final fix = await currentFix(timeout: timeout);
    if (!fix.hasPosition) return ManaPlace(fix: fix);

    try {
      final marks = await placemarkFromCoordinates(fix.latitude!, fix.longitude!);
      if (marks.isEmpty) return ManaPlace(fix: fix);
      final m = marks.first;
      final pin = (m.postalCode ?? '').replaceAll(RegExp(r'\D'), '');

      // locality is the town or village. subLocality is the colony or hamlet
      // inside it, and it used to WIN when present -- so standing in Aphb
      // Colony wrote "Aphb Colony" into the village field, a name that is not
      // in lgd_villages under any PIN and therefore could never be matched or
      // saved. The person was left staring at "not found -- add it" for a
      // village that already exists a level up.
      //
      // The two are kept apart now. [village] is the thing the directory might
      // actually know; [locality] is the colony, which is a house-address
      // detail and never a village.
      final village = (m.locality ?? '').trim();
      final locality = (m.subLocality ?? '').trim();
      return ManaPlace(
        fix: fix,
        pinCode: pin.length == 6 ? pin : null,
        village: village.isEmpty ? null : village,
        locality: locality.isEmpty ? null : locality,
      );
    } on Exception {
      // Geocoding is a convenience. Keep the fix, drop the labels.
      return ManaPlace(fix: fix);
    }
  }
}

class ManaPlace {
  final ManaFix fix;
  final String? pinCode;

  /// The town or village the geocoder read back — the level `lgd_villages`
  /// records. A SUGGESTION: it is matched against the PIN's directory before
  /// anything is filled in, because a geocoder name that is not in the
  /// directory cannot be saved and must not be typed into the village box.
  final String? village;

  /// The colony or hamlet inside that village. Part of a house address, never
  /// a village — writing it into the village field is what produced "Aphb
  /// Colony" against a PIN whose directory has no such place.
  final String? locality;

  const ManaPlace({
    required this.fix,
    this.pinCode,
    this.village,
    this.locality,
  });

  bool get hasPosition => fix.hasPosition;

  /// True when there is something worth writing into the form.
  bool get filledAnything => pinCode != null || village != null;

  String get message => switch (true) {
        _ when !fix.hasPosition => fix.message,
        _ when !filledAnything =>
          'Location captured, but the address could not be read from it — '
              'please type the PIN code and village.',
        _ => 'Location captured.',
      };
}
