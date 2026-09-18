/// Where the public website actually is.
///
/// THE PROBLEM THIS SOLVES. Two screens hardcoded `https://manaline.in/` —
/// the handset signpost that sends an Owner to the web for bulk onboarding,
/// and the "About MANA LINE" link on the sign-in page. That domain is NOT
/// REGISTERED: it resolves to nothing, checked against two independent
/// resolvers. Both links were shipped, one of them inside the APK on a real
/// phone, and both led nowhere.
///
/// It was an easy mistake to make and an impossible one to see: the name is
/// in every plan and every document, the deploy guide is called "Deploying
/// manaline.in", and nobody had cause to type it into a browser.
///
/// ONE CONSTANT, OVERRIDABLE AT BUILD TIME. The day the domain is registered
/// and attached, the switch is a `--dart-define`, not a code change:
///
/// ```bash
/// flutter build web -t lib/main_web.dart --base-href /app/ \
///   --dart-define=MANA_SITE_URL=https://manaline.in
/// ```
///
/// The default is the origin that is actually serving today. A link that
/// works and is not yet the final address is strictly better than a link to
/// an address that does not exist.
///
/// NO TRAILING SLASH on the constant — [manaSiteAppUrl] and callers add their
/// own path, and `https://host//app/` is the kind of thing that works in four
/// browsers and not the fifth.
const String manaSiteUrl = String.fromEnvironment(
  'MANA_SITE_URL',
  defaultValue: 'https://manaline.pages.dev',
);

/// The signed-in web app, which is served under `/app/` on the same origin.
///
/// Deliberately derived rather than a second define: the two are one
/// deployment (see docs/DEPLOY.md — both halves upload together, and
/// `_headers` applies to the whole project), so letting them be configured
/// apart would allow a combination that has never existed.
String get manaSiteAppUrl => '$manaSiteUrl/app/';
