import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/stored_file.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../shared/widgets/language_selector.dart';

/// In-memory state carried across the LR-001..LR-013 flow.
///
/// TYPE FIX (this session): `selectedBusinessId` and `Membership.businessId`
/// were previously `int`, but every `business_id` in the real delivered
/// schema (supabase/migrations/0002_module1_tenancy.sql, confirmed against
/// live DDL this session) is `UUID` — i.e. a `String` in Dart. Both are now
/// `String`/`String?`. `personId` was already `String` here (schema has
/// persons.person_id as BIGINT, so in principle a numeric string — kept as
/// String throughout for simplicity, matching how the stub already modeled
/// it; only business_id/membership_id needed the type change).
///
/// RIPPLE WARNING (flagged in END RESULT, not silently fixed): ~40 files
/// outside login_registration/ under owner_workspace/, agent_workspace/,
/// investor_workspace/, and customer_workspace/ also read
/// `.selectedBusinessId` or `Membership.businessId`. This chat's file
/// ownership boundary explicitly forbids editing those four directories,
/// so this type change WILL fail to compile against those call sites until
/// a chat that owns those directories propagates the same int->String fix
/// there. See END RESULT for the full list and the exact boundary conflict.
class AuthFlowState {
  final String? personId;
  final String? mlid;
  final String? mlidType;
  final bool? pinExists;
  final String? token;
  final ManaLanguage language;
  final List<Membership> memberships;
  final String? selectedBusinessId; // set on LR-012 selection (or its auto-collapse)
  final String? selectedRole; // set on LR-013 selection (or its auto-collapse)

  /// Transient — set when register()/passwordResetRequest()/pinResetRequest()
  /// (or the account-unlock path) triggers a server-side OTP send. LR-005
  /// reads this (via ref.watch) instead of taking it as a constructor param,
  /// so router.dart's existing `GoRoute(path: '/lr-005', builder: (c, s) =>
  /// OtpVerificationScreen(purpose: ...))` doesn't need to change — this
  /// chat is not allowed to touch router.dart. Cleared once verifyOtp()
  /// succeeds or the flow otherwise completes.
  final String? pendingOtpId;

  /// Transient — set by LR-004 with the live photo captured at
  /// registration. Registration itself has no session/JWT yet (only
  /// login mints one), so persons_self_update RLS can't be satisfied at
  /// that point — the bytes are carried here and actually uploaded +
  /// written to persons.profile_photo_url right after LR-007's first
  /// successful login, when a real session finally exists. Cleared once
  /// that upload completes (or is skipped/fails non-fatally).
  final Uint8List? pendingProfilePhotoBytes;

  const AuthFlowState({
    this.personId,
    this.mlid,
    this.mlidType,
    this.pinExists,
    this.token,
    this.language = ManaLanguage.english,
    this.memberships = const [],
    this.selectedBusinessId,
    this.selectedRole,
    this.pendingOtpId,
    this.pendingProfilePhotoBytes,
  });

  AuthFlowState copyWith({
    String? personId,
    String? mlid,
    String? mlidType,
    bool? pinExists,
    String? token,
    ManaLanguage? language,
    List<Membership>? memberships,
    String? selectedBusinessId,
    String? selectedRole,
    String? pendingOtpId,
    bool clearPendingOtpId = false,
    Uint8List? pendingProfilePhotoBytes,
    bool clearPendingProfilePhotoBytes = false,
  }) {
    return AuthFlowState(
      personId: personId ?? this.personId,
      mlid: mlid ?? this.mlid,
      mlidType: mlidType ?? this.mlidType,
      pinExists: pinExists ?? this.pinExists,
      token: token ?? this.token,
      language: language ?? this.language,
      memberships: memberships ?? this.memberships,
      selectedBusinessId: selectedBusinessId ?? this.selectedBusinessId,
      selectedRole: selectedRole ?? this.selectedRole,
      pendingOtpId: clearPendingOtpId ? null : (pendingOtpId ?? this.pendingOtpId),
      pendingProfilePhotoBytes: clearPendingProfilePhotoBytes
          ? null
          : (pendingProfilePhotoBytes ?? this.pendingProfilePhotoBytes),
    );
  }
}

class Membership {
  final String membershipId;
  final String businessId;
  final String businessName;
  final String role;
  final String membershipStatus;
  /// businesses.business_status — distinct from membershipStatus (LR-012:
  /// a Suspended business can still show for a person with an Active
  /// membership row, visually flagged, not hidden).
  final String businessStatus;
  /// business_members.verification_status — gates role visibility on
  /// LR-013 (BR-188/190/191): 'Verified' or 'Not Required' are eligible,
  /// 'Pending Verification' is hidden entirely from that screen.
  final String verificationStatus;

  const Membership({
    required this.membershipId,
    required this.businessId,
    required this.businessName,
    required this.role,
    required this.membershipStatus,
    this.businessStatus = 'Active',
    this.verificationStatus = 'Not Required',
  });
}

/// The profile screen of whichever role this device last resolved.
///
/// Checked most-specific first: an Owner has no agent, customer or investor
/// row, so a remembered businessId with none of those set is the Owner case.
/// Null on a genuinely first-ever login, where there is no prior role and no
/// profile to show yet.
///
/// Shared because two screens need the same answer for the same reason --
/// SettingsScreen's Profile row, and LR-012's header avatar, which sits above
/// role selection and so has no workspace to derive one from. A second copy
/// would be a second thing to keep in step.
String? manaLastUsedProfileRoute() {
  final session = ManaSession.instance;
  if (session.lastAgentId != null) return '/ag-009';
  if (session.lastCustomerId != null) return '/cw-006';
  if (session.lastInvestorId != null) return '/iw-005';
  if (session.lastBusinessId != null) return '/ow-016';
  return null;
}

class AuthFlowNotifier extends Notifier<AuthFlowState> {
  /// Starts from whatever the session already knows.
  ///
  /// state.personId was written by exactly two things — setLoginResult and
  /// setRegistrationResult — both of which happen while somebody is logging in
  /// or registering. On a cold start neither runs: main.dart hydrates
  /// ManaSession from secure storage and the app comes up signed in, while
  /// this state's personId stays null.
  ///
  /// Nine screens read it. An Investor who reopened the app and pressed Send
  /// Request hit `StateError('No logged-in person_id available')` inside
  /// submitRequest, which was caught, stored in state.error, and never shown —
  /// the button spun, stopped, and the sheet sat there. Same shape waiting in
  /// the customer discovery, loan request and withdrawal request paths.
  ///
  /// ManaSession is the durable copy and is hydrated before runApp, so it is
  /// the one to start from. The two are written together by setLoginResult
  /// and now agree on cold start too.
  @override
  AuthFlowState build() =>
      AuthFlowState(personId: ManaSession.instance.currentPersonId);

  void setLanguage(ManaLanguage lang) => state = state.copyWith(language: lang);

  void setRegistrationResult({
    required String personId,
    required String mlid,
    required String mlidType,
  }) {
    state = state.copyWith(personId: personId, mlid: mlid, mlidType: mlidType);
  }

  /// Set once a register()/passwordResetRequest()/pinResetRequest() call
  /// returns an otp_id from the server — LR-005 reads this to know which
  /// OTP it's verifying.
  void setPendingOtpId(String otpId) {
    state = state.copyWith(pendingOtpId: otpId);
  }

  void clearPendingOtpId() {
    state = state.copyWith(clearPendingOtpId: true);
  }

  void setPendingProfilePhoto(Uint8List bytes) {
    state = state.copyWith(pendingProfilePhotoBytes: bytes);
  }

  void clearPendingProfilePhoto() {
    state = state.copyWith(clearPendingProfilePhotoBytes: true);
  }

  /// Sets the auth result AND pushes the session into ManaSession so
  /// every subsequent Postgrest/RLS-scoped call (e.g. fetchMemberships())
  /// carries the right bearer token immediately — these two must not drift
  /// out of sync, so this is the one place both are touched together.
  Future<void> setLoginResult({
    required String personId,
    required String token,
    required bool pinExists,
    List<Membership> memberships = const [],
  }) async {
    state = state.copyWith(
      personId: personId,
      token: token,
      pinExists: pinExists,
      memberships: memberships,
    );
    await ManaSession.instance.setSession(accessToken: token, personId: personId);
    await _restorePreferredLanguage(personId);
  }

  /// Puts the person's saved language back on the session.
  ///
  /// Settings has always WRITTEN persons.preferred_language and nothing has
  /// ever read it, so the choice survived exactly as long as the app stayed
  /// open: pick Telugu, close the app, and it opened in English again with the
  /// setting still showing Telugu. Restoring here rather than at first paint
  /// because it needs the token, which is set on the line above.
  ///
  /// Non-fatal by design. A person who cannot be read still gets a working
  /// app in the default language, which is where they were before this
  /// existed; failing a login over a display preference would be far worse
  /// than showing English.
  Future<void> _restorePreferredLanguage(String personId) async {
    try {
      final row = await Supabase.instance.client
          .from('persons')
          .select('preferred_language')
          .eq('person_id', personId)
          .maybeSingle();
      final stored = row?['preferred_language'] as String?;
      if (stored == null) return;
      // firstWhere with an orElse, not byName: preferred_language_enum still
      // holds Hindi/Tamil/Kannada, and rows carrying those predate the app
      // being cut down to two languages. Those people get English rather than
      // an exception on the login path.
      final match = ManaLanguage.values
          .where((l) => l.enumValue == stored)
          .firstOrNull;
      if (match != null) state = state.copyWith(language: match);
    } catch (_) {
      // See above — a preference is not worth failing a login over.
    }
  }

  void setMemberships(List<Membership> memberships) {
    state = state.copyWith(memberships: memberships);
  }

  /// LR-012 selection (or its single-business auto-collapse).
  void selectBusiness(String businessId) {
    state = state.copyWith(selectedBusinessId: businessId);
    // Remembered here, where the choice is actually made.
    //
    // It used to be recorded only by router.dart's _resolveBusinessId, inside
    // the route BUILDER -- and GoRouter runs its redirect before any builder.
    // So picking a business and then a role went: LR-013 navigates to
    // /ow-001, the guard finds no business in the session, bounces to LR-012,
    // and the builder that would have recorded the business never runs. A
    // loop that only appeared on a session with nothing stored yet, which is
    // to say on a fresh install or the first login after a logout.
    //
    // rememberBusinessId sets the in-memory field synchronously and lets the
    // storage write trail behind it, so the very next navigation sees it.
    ManaSession.instance.rememberBusinessId(businessId);
  }

  /// LR-013 selection (or its single-role auto-collapse).
  void selectRole(String role) {
    state = state.copyWith(selectedRole: role);
  }

  /// Resolves and persists the role-specific entity id (agents.agent_id /
  /// customers.customer_id / investors.investor_id) and membership_id for
  /// whichever (business, role) is currently selected, then awaits the
  /// write to ManaSession — call this and await it BEFORE navigating to
  /// the destination workspace route, since router.dart reads these
  /// synchronously on the very first build. Before this method existed,
  /// nothing ever set these at all: AG-001/006/007/009 (and their CW/IW
  /// counterparts) always built with a hardcoded literal
  /// ('stub-agent-id' etc.), so every query keyed on that id came back
  /// empty on every single visit, not just after a reload.
  ///
  /// The membership_id itself needs no query — it's already on the
  /// Membership loaded by LR-012. Only the role-specific table needs one
  /// small lookup by membership_id. Owner has no separate entity table
  /// (ow-014's "currentOwnerPersonId" is just personId, already available
  /// via ManaSession.currentPersonId) so this is a no-op for that role.
  Future<void> resolveSelectedMembershipEntity() async {
    final businessId = state.selectedBusinessId;
    final role = state.selectedRole;
    if (businessId == null || role == null) return;

    Membership? membership;
    for (final m in state.memberships) {
      if (m.businessId == businessId && m.role == role) {
        membership = m;
        break;
      }
    }
    if (membership == null) return;
    final membershipId = membership.membershipId;

    String? agentId;
    String? customerId;
    String? investorId;
    try {
      final db = Supabase.instance.client;
      switch (role) {
        case 'Agent':
          final row = await db.from('agents').select('agent_id').eq('membership_id', membershipId).maybeSingle();
          agentId = row?['agent_id'] as String?;
        case 'Customer':
          final row = await db.from('customers').select('customer_id').eq('membership_id', membershipId).maybeSingle();
          customerId = row?['customer_id'] as String?;
        case 'Investor':
          final row = await db.from('investors').select('investor_id').eq('membership_id', membershipId).maybeSingle();
          investorId = row?['investor_id'] as String?;
        default:
          // Owner — no separate entity row; membershipId alone is enough.
          break;
      }
    } catch (_) {
      // Non-fatal — router.dart's stub fallback still applies if this
      // lookup fails, same as it did before this method existed.
    }

    // Switching INTO a role must not blank the ids of the others: this
    // used to pass all four every time, so choosing Agent wrote
    // customerId/investorId back as null. Only the id we actually
    // resolved is written; rememberResolvedIds ignores the nulls.
    //
    // If the role's own lookup failed, that id is deliberately NOT
    // written either — better to keep the last good value than to blank
    // it and have router.dart fall through to 'stub-agent-id', which is
    // what makes a workspace open against an agent that does not exist.
    await ManaSession.instance.rememberResolvedIds(
      membershipId: membershipId,
      agentId: agentId,
      customerId: customerId,
      investorId: investorId,
      // Which role this membership belongs to, so an Agent membership is
      // kept apart from an Owner one held by the same person.
      role: role,
    );

    // A role selected with no resolvable entity row is a real problem —
    // AG-001/CW-001/IW-001 will query a stub id and come back empty with
    // no explanation. Surface it rather than opening a dead workspace.
    if (role != 'Owner' && agentId == null && customerId == null && investorId == null) {
      throw StateError(
        'Could not open the $role workspace: no $role record exists for this '
        'membership. Ask the Owner to re-add you to this business.',
      );
    }
  }

  Future<void> reset() async {
    state = const AuthFlowState();
    await ManaSession.instance.clear();
  }
}

final authFlowProvider = NotifierProvider<AuthFlowNotifier, AuthFlowState>(
  AuthFlowNotifier.new,
);

/// ---------------------------------------------------------------------
/// ManaSession — holds the custom auth JWT (see main.dart's
/// Supabase.initialize(accessToken: ...) callback) and persists it via
/// flutter_secure_storage so LR-001 (System Startup) can hydrate a
/// returning session on cold start without a fresh login (Item E of this
/// session's briefing). Deliberately a separate small singleton rather than
/// folded into AuthFlowNotifier, because main.dart needs a synchronous
/// token getter BEFORE the ProviderScope/Riverpod container exists —
/// Supabase.initialize() runs before runApp(). Riverpod state can't be
/// read that early, but a plain static singleton can.
/// ---------------------------------------------------------------------
class ManaSession {
  ManaSession._();
  static final ManaSession instance = ManaSession._();

  static const _storage = FlutterSecureStorage();
  static const _kAccessToken = 'mana_session_access_token';
  static const _kPersonId = 'mana_session_person_id';
  static const _kLastBusinessId = 'mana_session_last_business_id';
  static const _kLastMembershipId = 'mana_session_last_membership_id';
  static const _kLastAgentMembershipId = 'mana_session_last_agent_membership_id';
  static const _kLastAgentId = 'mana_session_last_agent_id';
  static const _kLastCustomerId = 'mana_session_last_customer_id';
  static const _kLastInvestorId = 'mana_session_last_investor_id';

  String? _accessToken;
  String? _personId;
  String? _lastBusinessId;
  String? _lastMembershipId;

  /// The AGENT membership specifically, kept apart from [_lastMembershipId].
  ///
  /// One person can hold two memberships in the same business -- Owner and
  /// Agent -- and on this book somebody does. With a single slot, resolving
  /// the Owner role overwrote it, and every /ag- route then handed the
  /// Owner's membership to an Agent screen: AG-010 asked for "my agent
  /// ledger" and was given the Owner's, which is how the Agent's history came
  /// to show the Owner's. The role-specific ids beside this one
  /// (agentId/customerId/investorId) were already kept apart for exactly this
  /// reason; the membership was the one that was not.
  String? _lastAgentMembershipId;
  String? _lastAgentId;
  String? _lastCustomerId;
  String? _lastInvestorId;

  /// Read synchronously by supabase_flutter's accessToken callback on
  /// every outgoing request. Returning null before a session exists is
  /// expected and correct — it's what makes register/login themselves
  /// (which must run as `anon`, not `authenticated`) work at all.
  String? get currentAccessToken => _accessToken;
  String? get currentPersonId => _personId;
  bool get hasSession => _accessToken != null;

  /// Last business a workspace route (OW-001/AG-001/CW-001/IW-001 etc.)
  /// was actually reached with via `extra`. Read synchronously by
  /// router.dart as the fallback when `extra` is null — e.g. a browser
  /// refresh or a direct URL hit, both of which lose go_router's
  /// in-memory `extra` payload. Without this, those routes fell back to
  /// a hardcoded literal ('stub-business-id') that doesn't exist in the
  /// database, so every real dashboard query failed with "could not load
  /// dashboard" the moment a user refreshed the page.
  String? get lastBusinessId => _lastBusinessId;

  /// business_members.membership_id for whichever (business, role) LR-013
  /// most recently selected — resolved by
  /// AuthFlowNotifier.resolveSelectedMembershipEntity() right after
  /// selectRole(), from `memberships` already loaded by LR-012 (no extra
  /// query needed for this one). Read synchronously by router.dart for
  /// routes that take a membership id directly (AG-003/004/005 etc.).
  String? get lastMembershipId => _lastMembershipId;

  /// The Agent membership, for /ag- routes. Falls back to the generic slot
  /// only for a person who has never resolved an Agent role -- in which case
  /// they are not standing in an Agent workspace either.
  String? get lastAgentMembershipId =>
      _lastAgentMembershipId ?? _lastMembershipId;

  /// agents.agent_id / customers.customer_id / investors.investor_id for
  /// the same resolved membership — one lookup query each, done once in
  /// resolveSelectedMembershipEntity() and cached here. Before this,
  /// every AG-001/006/007/009 (and CW/IW equivalents) route used a
  /// hardcoded literal ('stub-agent-id' etc.) unconditionally — not just
  /// on reload, but on every single navigation, real or not — so every
  /// query keyed on that id (e.g. agent_dashboard_state.dart's
  /// `.eq('agent_id', agentId)`) returned nothing and the workspace
  /// never actually loaded real data.
  String? get lastAgentId => _lastAgentId;
  String? get lastCustomerId => _lastCustomerId;
  String? get lastInvestorId => _lastInvestorId;

  Future<void> setSession({required String accessToken, required String personId}) async {
    _accessToken = accessToken;
    _personId = personId;
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.write(key: _kPersonId, value: personId);
  }

  /// Admin login's counterpart to setSession — there is no personId for an
  /// admin session (admin_accounts is deliberately separate from persons),
  /// so this only ever sets the token. Reuses the same storage slot: a
  /// person session and an admin session are mutually exclusive on one
  /// device (the JWT itself carries exactly one of person_id/admin_id,
  /// never both), so there's nothing to keep distinct.
  Future<void> setAdminSession({required String accessToken}) async {
    _accessToken = accessToken;
    _personId = null;
    await _storage.write(key: _kAccessToken, value: accessToken);
    await _storage.delete(key: _kPersonId);
  }

  /// Fire-and-forget by design (called from route builders, which can't
  /// await) — the in-memory value is set synchronously so same-session
  /// navigation is never affected by storage latency; only a
  /// reload/direct-URL hit ever depends on the write having landed.
  void rememberBusinessId(String businessId) {
    if (_lastBusinessId == businessId) return;
    _lastBusinessId = businessId;
    unawaited(_storage.write(key: _kLastBusinessId, value: businessId));
  }

  /// Called (and awaited) once per role selection, before navigating —
  /// unlike rememberBusinessId, the caller needs these values to actually
  /// be in place for the very first navigation, not just reload survival,
  /// so this one persists synchronously into memory and is awaited by the
  /// caller for the storage write.
  Future<void> rememberResolvedIds({
    String? membershipId,
    String? agentId,
    String? customerId,
    String? investorId,

    /// The role this membership was resolved FOR. An Agent membership is
    /// remembered in its own slot as well, because a person can hold two in
    /// one business and the /ag- routes must never be handed the Owner's.
    String? role,
  }) async {
    // Only overwrite what was actually resolved. This used to assign all
    // four unconditionally, so a role switch blanked the other three in
    // memory even though the storage writes below have always been
    // null-guarded — memory and storage disagreed after every switch, and
    // router.dart reads memory. A blanked agentId is what makes /ag-001
    // build with 'stub-agent-id' and query an agent that does not exist.
    if (membershipId != null) _lastMembershipId = membershipId;
    if (membershipId != null && role == 'Agent') {
      _lastAgentMembershipId = membershipId;
    }
    if (agentId != null) _lastAgentId = agentId;
    if (customerId != null) _lastCustomerId = customerId;
    if (investorId != null) _lastInvestorId = investorId;
    await Future.wait([
      if (membershipId != null) _storage.write(key: _kLastMembershipId, value: membershipId),
      if (membershipId != null && role == 'Agent')
        _storage.write(key: _kLastAgentMembershipId, value: membershipId),
      if (agentId != null) _storage.write(key: _kLastAgentId, value: agentId),
      if (customerId != null) _storage.write(key: _kLastCustomerId, value: customerId),
      if (investorId != null) _storage.write(key: _kLastInvestorId, value: investorId),
    ]);
  }

  Future<void> clear() async {
    // A memoised link to somebody's face or identity document must not
    // outlive their session -- see ManaStoredFile.
    ManaStoredFile.clearCache();
    _accessToken = null;
    _personId = null;
    _lastBusinessId = null;
    _lastMembershipId = null;
    _lastAgentMembershipId = null;
    _lastAgentId = null;
    _lastCustomerId = null;
    _lastInvestorId = null;
    await _storage.delete(key: _kAccessToken);
    await _storage.delete(key: _kPersonId);
    await _storage.delete(key: _kLastBusinessId);
    await _storage.delete(key: _kLastMembershipId);
    await _storage.delete(key: _kLastAgentMembershipId);
    await _storage.delete(key: _kLastAgentId);
    await _storage.delete(key: _kLastCustomerId);
    await _storage.delete(key: _kLastInvestorId);
  }

  /// Called once from main(), before runApp(). Populates the in-memory
  /// token from secure storage so the very first authenticated Postgrest
  /// call after a warm/cold restart already carries the right bearer
  /// token.
  ///
  /// BUG FOUND (confirmed live): this previously restored whatever token
  /// was last saved with no expiry check at all — every subsequent
  /// request (data screens AND, critically, a fresh login/PIN attempt)
  /// carried a token the server had already rejected, which is worse than
  /// just "RLS silently returns zero rows": a request that includes an
  /// expired bearer gets a hard 401/PGRST303 "JWT expired" from
  /// PostgREST, and the exact same header was going out on auth-login
  /// too (see auth_api_service.dart's `_anonAuth` fix), so nobody could
  /// even log back in. Decoding (not verifying — no secret client-side,
  /// and none needed just to read a public claim) the token's own `exp`
  /// claim here means an already-dead token is simply never restored:
  /// the app comes up looking logged-out (correct) rather than logged-in
  /// with every screen silently failing.
  Future<void> hydrateFromSecureStorage() async {
    final token = await _storage.read(key: _kAccessToken);
    _accessToken = (token != null && !_isJwtExpired(token)) ? token : null;
    _personId = await _storage.read(key: _kPersonId);
    _lastBusinessId = await _storage.read(key: _kLastBusinessId);
    _lastMembershipId = await _storage.read(key: _kLastMembershipId);
    _lastAgentMembershipId = await _storage.read(key: _kLastAgentMembershipId);
    _lastAgentId = await _storage.read(key: _kLastAgentId);
    _lastCustomerId = await _storage.read(key: _kLastCustomerId);
    _lastInvestorId = await _storage.read(key: _kLastInvestorId);
  }

  /// True when there is a token but it has already expired.
  ///
  /// The token carries a 1-hour TTL and this app has NO refresh endpoint —
  /// `auth-login` mints, nothing renews. Expiry mid-session therefore
  /// turns every subsequent request into a hard PGRST303 "JWT expired",
  /// and any Retry button re-sends the same dead token forever. Callers
  /// use this to send the person back to PIN entry, which re-mints, rather
  /// than leaving them on an error screen that cannot recover.
  bool get isAccessTokenExpired {
    final token = _accessToken;
    return token != null && _isJwtExpired(token);
  }

  /// Drops an expired token so the app presents as logged-out rather than
  /// logged-in-and-silently-failing. Deliberately keeps personId and the
  /// last-business/role ids: those make the re-login land the person back
  /// where they were instead of starting from business selection.
  Future<void> clearExpiredAccessToken() async {
    _accessToken = null;
    await _storage.delete(key: _kAccessToken);
  }

  /// Reads the `exp` claim out of a JWT's payload segment without
  /// verifying its signature (there's no secret to verify with
  /// client-side, and none is needed just to read a public, unencrypted
  /// claim). Any decode failure is treated as "expired" — a token this
  /// app can't even parse is not one worth sending.
  bool _isJwtExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) return true;
      return DateTime.now().millisecondsSinceEpoch >= exp * 1000;
    } catch (_) {
      return true;
    }
  }
}
