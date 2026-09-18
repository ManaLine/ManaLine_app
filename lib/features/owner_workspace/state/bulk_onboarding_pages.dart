import 'bulk_onboarding_service.dart';

/// The steps of a pre-existing-book migration, in the order the book itself
/// is organised.
///
/// LIFTED OUT OF THE WIZARD on 2026-09-18, when the website menu
/// (`ow_bulk_onboarding_menu.dart`) needed the same list. The menu's "Open"
/// buttons write a step pointer that the wizard then restores, so the two
/// have to agree on what step 3 *is* — and the list is not fixed: it depends
/// on what the Owner said their book contains.
///
/// A second copy would have drifted the first time a page was added. It has
/// already drifted once inside the wizard alone: every page used to hardcode
/// the index it jumped to, which is how Next came to skip a page when
/// Areas & Villages was removed.
enum ManaBulkPage {
  plan('What Your Book Has', 'bulk_step_plan'),
  identities('Identities', 'bulk_step_identities'),
  // Four of these reuse keys `ui_translations` already carries, in Telugu as
  // well as English. Minting `bulk_step_investors` beside an `investors` that
  // says the same word in both languages would be a second string to keep in
  // step with the first, for nothing.
  investors('Investors', 'investors'),
  customers('Customers', 'customers'),
  agents('Agents', 'agents'),
  snapshot('Opening Snapshot', 'bulk_step_snapshot'),
  weekly('Weekly Account', 'bulk_step_weekly'),
  finish('Finish', 'finish');

  const ManaBulkPage(this.title, this.titleKey);

  /// The English heading the wizard has always drawn. Kept as a literal
  /// because the wizard's body copy is English throughout — translating the
  /// heading alone would produce a Telugu title over English prose, which
  /// reads worse than either.
  final String title;

  /// The `ui_translations` key the MENU uses. The menu is new and is
  /// translated properly, so it does not inherit the wizard's English.
  final String titleKey;
}

/// The pages this book needs, given what the Owner said it has.
///
/// Shareholders share the Investors page, so that page shows if either was
/// ticked. Instalment history is part of the Customers sheet rather than a
/// page of its own; it changes what that page says, not whether it appears.
///
/// AREAS & VILLAGES USED TO SIT SECOND. It derived the village list from the
/// identity sheet and then asked the Owner to place each one — AFTER the
/// identities that needed those villages had already been imported.
/// bulk_import_identities said as much, refusing a customer with "add it on
/// the Areas & Villages step first" about a step that came later. Villages and
/// areas are now set up before the wizard is opened, the identity sheet offers
/// them as a dropdown, and a village typed in fresh is created by the import.
///
/// A null plan yields the chooser alone — an Owner who has not said what
/// their book contains has nothing else to be shown yet.
List<ManaBulkPage> manaBulkPagesFor(MigrationPlan? plan) {
  if (plan == null) return const [ManaBulkPage.plan];
  return [
    ManaBulkPage.plan,
    ManaBulkPage.identities,
    if (plan.investors || plan.shareholders) ManaBulkPage.investors,
    if (plan.customers) ManaBulkPage.customers,
    if (plan.attendance) ManaBulkPage.agents,
    ManaBulkPage.snapshot,
    if (plan.weekly) ManaBulkPage.weekly,
    ManaBulkPage.finish,
  ];
}
