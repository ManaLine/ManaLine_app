import 'package:flutter/material.dart';

import '../design/tokens/icons.dart';

/// The things this app can do, as a list you can search.
///
/// The Owner, 2026-09-18: "Global search - enable to search options that app
/// offers like add a customer, add an agent, etc.. upon entering 3 show
/// matches and on tap lead to that screen or flow."
///
/// WHY A CURATED LIST AND NOT THE ROUTE TABLE. There are 88 routes and most of
/// them are not things anybody would go looking for -- `/lr-009` is a PIN
/// prompt the app pushes at you, `/ow-007` needs a loan id it cannot invent,
/// `/business-suspended` is a wall. A search that offers all 88 is a search
/// that buries the six an Owner actually types. So this is written by hand,
/// and `app_actions_guard_test.dart` fails if any route here is not declared
/// in the router or any label here has no translation.
///
/// MATCHED ON WORDS PEOPLE USE, not on screen titles. An Owner looking for the
/// collection round types "vasool"; looking to lend, they type "loan" long
/// before they would type "New Loan Workflow". Every action carries the plain
/// words for the same thing, in both languages, and they are matched as well
/// as the label. Without them this is a search that only finds what you could
/// already see.
@immutable
class ManaAppAction {
  /// The translation key for what this is called.
  final String labelKey;

  /// Where it goes. Must be a route the router declares.
  final String route;

  /// Appended to the route, for an action that opens a screen on a particular
  /// tab or in a particular mode. Starts with '?'.
  final String query;

  final IconData icon;

  /// Other words that should find it, lowercase, in English and Telugu.
  ///
  /// These are matched in addition to the translated label, so the same action
  /// is reachable from either language regardless of which one the app is set
  /// to -- an Owner who thinks in Telugu and types in English still lands on
  /// it.
  final List<String> keywords;

  const ManaAppAction({
    required this.labelKey,
    required this.route,
    required this.icon,
    this.query = '',
    this.keywords = const [],
  });

  String get path => '$route$query';
}

/// What an Owner can go and do.
///
/// Ordered as a person would think of their day -- people, then money, then
/// the book, then the business -- because ties in the match score are broken
/// by this order and the earlier one is the likelier one.
const manaOwnerActions = <ManaAppAction>[
  // ---- people ----
  ManaAppAction(
    labelKey: 'add_a_customer',
    route: '/customer-new',
    icon: Icons.person_add_outlined,
    keywords: ['customer', 'borrower', 'new customer', 'add', 'కస్టమర్', 'కొత్త'],
  ),
  ManaAppAction(
    labelKey: 'customer_management',
    route: '/ow-004',
    icon: Icons.people_outline,
    keywords: ['customers', 'borrowers', 'list', 'కస్టమర్లు'],
  ),
  ManaAppAction(
    labelKey: 'add_an_agent',
    route: '/ow-search',
    query: '?role=agent',
    icon: Icons.badge_outlined,
    keywords: ['agent', 'collector', 'staff', 'ఏజెంట్'],
  ),
  ManaAppAction(
    labelKey: 'agents',
    route: '/ow-002',
    icon: Icons.groups_outlined,
    keywords: ['agents', 'workforce', 'staff', 'ఏజెంట్లు'],
  ),
  ManaAppAction(
    labelKey: 'add_investor',
    route: '/ow-search',
    query: '?role=investor',
    // ManaIcons, not a raw glyph. I reached for savings_outlined for BOTH the
    // investor and the cheeti here -- the same collision the token file was
    // written to end, and the guard caught it on the first run.
    icon: ManaIcons.investor,
    keywords: ['investor', 'partner', 'పెట్టుబడి'],
  ),
  ManaAppAction(
    labelKey: 'investor_management',
    route: '/ow-003',
    icon: Icons.account_balance_outlined,
    keywords: ['investors', 'investment', 'పెట్టుబడిదారులు'],
  ),

  // ---- money ----
  ManaAppAction(
    labelKey: 'new_loan',
    route: '/ow-005',
    icon: Icons.request_quote_outlined,
    keywords: ['loan', 'lend', 'give loan', 'issue', 'రుణం', 'అప్పు'],
  ),
  ManaAppAction(
    labelKey: 'collection_mode',
    route: '/ow-006',
    icon: Icons.route_outlined,
    keywords: ['collection', 'round', 'vasool', 'collect', 'వసూలు'],
  ),
  ManaAppAction(
    labelKey: 'group_loans',
    route: '/ow-015',
    icon: Icons.group_work_outlined,
    keywords: ['group', 'joint loan', 'గ్రూప్'],
  ),
  ManaAppAction(
    labelKey: 'cheti',
    route: '/ow-019',
    icon: ManaIcons.cheti,
    keywords: ['cheeti', 'cheti', 'chit', 'చీటీ'],
  ),
  ManaAppAction(
    labelKey: 'loan_requests',
    route: '/ow-loan-requests',
    icon: Icons.inbox_outlined,
    keywords: ['requests', 'pending loans', 'అభ్యర్థనలు'],
  ),
  ManaAppAction(
    labelKey: 'withdrawal_requests',
    route: '/ow-withdrawal-requests',
    icon: Icons.outbox_outlined,
    keywords: ['withdrawal', 'payout', 'ఉపసంహరణ'],
  ),

  // ---- the book ----
  ManaAppAction(
    labelKey: 'daily_record_book',
    route: '/ow-009',
    icon: Icons.menu_book_outlined,
    keywords: ['record book', 'ledger', 'day book', 'పుస్తకం'],
  ),
  ManaAppAction(
    labelKey: 'day_closure',
    route: '/ow-011',
    icon: Icons.event_available_outlined,
    keywords: ['close day', 'closing', 'day end', 'ముగింపు'],
  ),
  ManaAppAction(
    labelKey: 'account_review',
    route: '/ow-013',
    icon: Icons.fact_check_outlined,
    keywords: ['account', 'review', 'settlement', 'ఖాతా'],
  ),
  ManaAppAction(
    labelKey: 'transaction_history',
    route: '/ow-017',
    icon: Icons.receipt_long_outlined,
    keywords: ['history', 'transactions', 'చరిత్ర'],
  ),
  ManaAppAction(
    labelKey: 'reports',
    route: '/ow-010',
    icon: Icons.assessment_outlined,
    keywords: ['report', 'summary', 'నివేదిక'],
  ),

  // ---- the business ----
  ManaAppAction(
    labelKey: 'operating_areas',
    route: '/ow-012',
    query: '?tab=areas',
    icon: Icons.map_outlined,
    keywords: ['area', 'areas', 'village', 'villages', 'route', 'ప్రాంతం', 'గ్రామం'],
  ),
  ManaAppAction(
    labelKey: 'merge_villages',
    route: '/village-merge',
    icon: Icons.merge_type,
    keywords: ['merge', 'duplicate village', 'విలీనం'],
  ),
  ManaAppAction(
    labelKey: 'business_management',
    route: '/ow-012',
    icon: Icons.storefront_outlined,
    keywords: ['business', 'settings', 'వ్యాపారం'],
  ),
  ManaAppAction(
    labelKey: 'bulk_onboarding',
    route: '/ow-bulk-onboarding-menu',
    icon: Icons.upload_file_outlined,
    keywords: ['migrate', 'migration', 'bulk', 'import', 'existing book'],
  ),
  ManaAppAction(
    labelKey: 'my_profile',
    route: '/ow-016',
    icon: Icons.account_circle_outlined,
    keywords: ['profile', 'me', 'my details', 'ప్రొఫైల్'],
  ),
  ManaAppAction(
    labelKey: 'notifications',
    route: '/notifications',
    icon: Icons.notifications_outlined,
    keywords: ['alerts', 'bell', 'inbox', 'నోటిఫికేషన్'],
  ),
  ManaAppAction(
    labelKey: 'trash',
    route: '/ow-trash',
    icon: Icons.delete_outline,
    keywords: ['deleted', 'bin', 'restore', 'తొలగించిన'],
  ),
  ManaAppAction(
    labelKey: 'settings',
    route: '/ow-settings',
    icon: Icons.settings_outlined,
    keywords: ['settings', 'preferences', 'సెట్టింగ్‌లు'],
  ),
];

/// The shortest query that searches actions at all.
///
/// The Owner's number, and a good one: at one or two letters every action
/// matches something, and a list of twenty-five is not an answer.
const manaActionSearchMinimum = 3;

/// Actions matching [query], best first, or empty below the minimum length.
///
/// [label] resolves an action's translation key, so the caller decides which
/// language is being searched -- this function has no opinion about it and no
/// dependency on the translation cache.
///
/// SCORING, in the order a person would expect:
///   3  the label starts with what was typed
///   2  a keyword starts with it
///   1  it appears anywhere in either
/// Ties keep catalogue order, which is roughly how often a thing is wanted.
List<ManaAppAction> manaSearchActions(
  String query,
  String Function(String key) label, {
  List<ManaAppAction> catalogue = manaOwnerActions,
}) {
  final q = query.trim().toLowerCase();
  if (q.length < manaActionSearchMinimum) return const [];

  final scored = <({ManaAppAction action, int score, int order})>[];
  for (var i = 0; i < catalogue.length; i++) {
    final a = catalogue[i];
    final labelText = label(a.labelKey).toLowerCase();
    int score = 0;
    if (labelText.startsWith(q)) {
      score = 3;
    } else if (a.keywords.any((k) => k.startsWith(q))) {
      score = 2;
    } else if (labelText.contains(q) || a.keywords.any((k) => k.contains(q))) {
      score = 1;
    }
    if (score > 0) scored.add((action: a, score: score, order: i));
  }

  scored.sort((x, y) =>
      x.score != y.score ? y.score - x.score : x.order - y.order);
  return [for (final s in scored) s.action];
}
