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

  const ManaFix({
    required this.status,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.detail,
  });

  bool get hasPosition => status == ManaFixStatus.ok && latitude != null;

  /// Above this, `app.compare_address_gps` returns is_indeterminate and the UI
  /// must say "couldn't verify" rather than "doesn't match". Mirrored here so
  /// a caller can warn before spending time on a comparison the server will
  /// refuse to judge.
  static const indeterminateAboveM = 100.0;

  bool get isTooRoughToJudge =>
      accuracyM != null && accuracyM! > indeterminateAboveM;

  /// What to tell the person. Deliberately not "Error" — most of these are
  /// ordinary conditions in a village, not faults.
  String get message => switch (status) {
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
  /// Asks for a fix. Never throws.
  ///
  /// [timeout] is deliberately short. An agent is standing in front of a
  /// customer; waiting thirty seconds for a satellite is worse than recording
  /// the visit without a pin.
  static Future<ManaFix> currentFix({
    Duration timeout = const Duration(seconds: 8),
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
      return ManaFix(
        status: isTimeout ? ManaFixStatus.timedOut : ManaFixStatus.failed,
        detail: e.toString(),
      );
    }
  }
}
