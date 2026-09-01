import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns what is stored in a `*_url` column into a link that works now, and
/// stops working shortly afterwards.
///
/// THE PROBLEM THIS EXISTS FOR: the upload helpers signed their URLs for a
/// YEAR and the full signed URL went into the database — `loans.live_photo_url`,
/// `persons.profile_photo_url`, `businesses.logo_url`. A signed URL carries its
/// own authorisation, so each of those rows was a link that anybody who ever
/// saw it could fetch for twelve months, with no login, no RLS, and no way to
/// revoke it short of deleting the object. These are photographs of people's
/// faces taken as fraud evidence at their own doorstep.
///
/// What is stored now is the object PATH, which authorises nothing on its own.
/// A URL is minted when a screen actually needs to show the image and is dead
/// within minutes.
///
/// TWO SHAPES, ON PURPOSE: rows written before this change hold a full signed
/// URL. Rather than a flag day, [pathOf] recovers the path from either shape,
/// so old rows keep working and become paths the next time they are written.
/// The backfill migration converts the ones already there.
class ManaStoredFile {
  ManaStoredFile._();

  /// How long a display URL lives. Long enough to load an image on a bad rural
  /// connection, short enough that a leaked link is worthless by the time it
  /// travels anywhere.
  static const displayTtl = Duration(minutes: 10);

  /// Re-signing on every rebuild would hit storage once per frame — these
  /// appear in headers that rebuild constantly. Cached until nearly expired.
  static final Map<String, _Signed> _cache = {};

  /// Written by the migration importer for loans that predate the app, where
  /// no photo was ever taken. Not a path and not a URL; never resolve it.
  static const migratedSentinel = 'migrated:pre-existing-loan:no-live-photo';

  /// The object path inside its bucket, from either shape.
  ///
  /// A Supabase signed URL looks like
  /// `https://<ref>.supabase.co/storage/v1/object/sign/<bucket>/<path>?token=…`
  /// so the path is everything after the bucket segment, minus the query.
  /// Anything that is not a URL is already a path and comes back untouched.
  static String? pathOf(String? stored) {
    final value = stored?.trim();
    if (value == null || value.isEmpty || value == migratedSentinel) return null;
    if (!value.startsWith('http')) return value;

    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    // .../object/sign/<bucket>/<path...>
    final signIndex = segments.indexOf('sign');
    if (signIndex == -1 || segments.length < signIndex + 3) return null;
    return segments.sublist(signIndex + 2).join('/');
  }

  /// A short-lived URL for [stored], or null when there is nothing to show.
  ///
  /// Never throws: a photo that cannot be resolved is a placeholder on screen,
  /// which is what every caller already renders for a missing one. Throwing
  /// would take down a dashboard header over an image.
  static Future<String?> signedUrl({
    required String bucket,
    required String? stored,
    Duration ttl = displayTtl,
  }) async {
    final path = pathOf(stored);
    if (path == null) return null;

    final key = '$bucket/$path';
    final cached = _cache[key];
    // A minute of headroom, so a URL handed out now is not about to die in
    // the middle of the download it was requested for.
    if (cached != null &&
        cached.expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return cached.url;
    }

    try {
      final url = await Supabase.instance.client.storage
          .from(bucket)
          .createSignedUrl(path, ttl.inSeconds);
      _cache[key] = _Signed(url, DateTime.now().add(ttl));
      return url;
    } on Exception {
      return null;
    }
  }

  /// Drops the memoised URLs. For tests, and for logout — a cached link to
  /// somebody else's photograph must not outlive their session.
  static void clearCache() => _cache.clear();
}

class _Signed {
  final String url;
  final DateTime expiresAt;
  const _Signed(this.url, this.expiresAt);
}
