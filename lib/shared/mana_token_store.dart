import 'mana_token_store_io.dart'
    if (dart.library.js_interop) 'mana_token_store_web.dart' as impl;

/// Where the session token lives.
///
/// Android and iOS: flutter_secure_storage, i.e. the Keystore — exactly what
/// ManaSession used before this file existed, unchanged.
///
/// Web: sessionStorage. flutter_secure_storage's web implementation is
/// localStorage, which any XSS on the origin can read and which SURVIVES the
/// browser closing. The token carries the person_id claim that RLS trusts, so
/// on a shared or public machine a localStorage token is a signed-in session
/// left behind for the next person. sessionStorage dies with the tab; the cost
/// is that a web user re-enters their PIN after closing it, which for a
/// lending book is the right side of the trade.
///
/// The one-hour expiry bounds this either way. It does not remove it.
class ManaTokenStore {
  const ManaTokenStore();

  Future<void> write({required String key, required String? value}) =>
      impl.write(key, value);

  Future<String?> read({required String key}) => impl.read(key);

  Future<void> delete({required String key}) => impl.delete(key);
}
