/// Supabase project URL/anon key — placeholder/env-var style, not hardcoded
/// into a committed file. Read via --dart-define at build time:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=xxxxx
///
/// Lives here (rather than inline in main.dart, where it originated) so
/// auth_api_service.dart can also reach the anon key — needed to force
/// anon auth on Edge Function calls that must work without an existing
/// session (see that file's `_anonAuth` header override and the comment
/// on why a stale cached token makes that necessary).
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://REPLACE-ME.supabase.co',
  );
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'REPLACE-ME-ANON-KEY',
  );

  /// True when the app was built WITHOUT --dart-define, so it is pointing at
  /// a host that does not exist.
  ///
  /// This failure mode is vicious: requests to REPLACE-ME.supabase.co do not
  /// fail fast, they hang. The translation cache sat forever on its first
  /// fetch, so every screen rendered raw keys ("app_name",
  /// "choose_workspace"), and login reported "No internet connection" on a
  /// device whose network was completely fine. Nothing anywhere said the
  /// build was misconfigured.
  ///
  /// EMPTY COUNTS TOO, and it used to not.
  ///
  /// `--dart-define=SUPABASE_URL=$URL` with `$URL` unset in the shell does
  /// not omit the define -- it supplies it as the EMPTY STRING. Dart then
  /// returns '' rather than the default, the REPLACE-ME literal is folded
  /// away as unreachable, and `''.contains('REPLACE-ME')` is false. So the
  /// one guard written to catch a misconfigured build waved through the
  /// commonest way to produce one, and `Supabase.initialize(url: '')` failed
  /// somewhere further downstream with a message about nothing in
  /// particular.
  ///
  /// Caught on a real build, by grepping the bundle for the project ref and
  /// finding neither it NOR the placeholder -- which is the signature of this
  /// exact case and of nothing else.
  ///
  /// See run.ps1.txt for the correct command.
  static bool get isPlaceholder =>
      url.trim().isEmpty ||
      anonKey.trim().isEmpty ||
      url.contains('REPLACE-ME') ||
      anonKey.contains('REPLACE-ME');
}
