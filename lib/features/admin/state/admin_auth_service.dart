import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/supabase_config.dart';
import '../../login_registration/state/auth_flow_state.dart';

/// Platform Admin's own auth path — completely separate from
/// AuthApiService/auth_flow_state's person-based login. Calls admin-login /
/// admin-password-reset-request / admin-password-reset-confirm (see
/// supabase/migrations/20260807125210_admin_own_identity_system.sql for the
/// backend). No `persons` row is ever involved: an admin is not a business
/// user, and `ManaSession.setAdminSession` stores the resulting token
/// without a personId.
class AdminAuthService {
  // A GETTER, not a field default — resolving Supabase.instance.client at
  // construction time (e.g. `final _authApi = AdminAuthService();` as a
  // State field initializer) touches it before Supabase.initialize() has
  // necessarily run, which throws in every widget test process. Deferring
  // to first actual use (inside login()/requestPasswordReset()/etc.)
  // matches the rest of this app's *ApiService classes.
  final SupabaseClient? _clientOverride;
  AdminAuthService({SupabaseClient? client}) : _clientOverride = client;
  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  static const Map<String, String> _anonAuth = {
    'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
  };

  /// Unwraps the standard `{data, meta, errors}` envelope every Edge
  /// Function in this deployment returns.
  ///
  /// BUG FIXED: this used to hand back the ENVELOPE, so `data['success']`
  /// read the envelope's top level — where no such key exists — and came
  /// back null on every call. `null != true`, so login threw "Invalid
  /// username or password" no matter what was typed: the admin panel could
  /// never be opened, with correct credentials or otherwise. The same
  /// mistake made requestPasswordReset read a null otp_id and throw a
  /// TypeError, which the screen rendered as "Could not reach the server"
  /// while the server had in fact answered 200.
  ///
  /// This is a copy of AuthApiService._asMap, whose own comment already
  /// says unwrapping centrally fixes every caller at once. The admin
  /// service simply never got that fix.
  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Unexpected Edge Function response shape');
    }
    final inner = raw['data'];
    if (inner is Map<String, dynamic>) return inner;
    return raw;
  }

  /// Throws [AdminAuthException] on a wrong username/password — the caller
  /// shows that inline, same convention as the person login screens.
  Future<void> login({required String username, required String password}) async {
    final res = await _client.functions.invoke('admin-login', headers: _anonAuth, body: {
      'username': username,
      'password': password,
    });
    final data = _asMap(res.data);
    if (data['success'] != true) {
      throw const AdminAuthException('Invalid username or password.');
    }
    await ManaSession.instance.setAdminSession(accessToken: data['token'] as String);
  }

  /// Always succeeds from the caller's point of view (never reveals
  /// whether the username matched — same contract as the person-side
  /// password reset). Returns the otp_id to carry into confirmRequest.
  Future<String> requestPasswordReset({required String username}) async {
    final res = await _client.functions.invoke('admin-password-reset-request', headers: _anonAuth, body: {
      'username': username,
    });
    final data = _asMap(res.data);
    return data['otp_id'] as String;
  }

  Future<void> confirmPasswordReset({
    required String otpId,
    required String code,
    required String newPassword,
  }) async {
    final res = await _client.functions.invoke('admin-password-reset-confirm', headers: _anonAuth, body: {
      'otp_id': otpId,
      'code': code,
      'new_password': newPassword,
    });
    final data = _asMap(res.data);
    if (data['success'] != true) {
      throw const AdminAuthException('Could not reset password.');
    }
  }
}

class AdminAuthException implements Exception {
  final String message;
  const AdminAuthException(this.message);
  @override
  String toString() => message;
}

final adminAuthServiceProvider = Provider<AdminAuthService>((ref) => AdminAuthService());
