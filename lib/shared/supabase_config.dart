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
}
