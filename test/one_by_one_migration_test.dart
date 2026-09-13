import 'package:flutter_test/flutter_test.dart';
import 'package:mana_line/features/owner_workspace/screens/ow_one_by_one_migration.dart';
import 'package:mana_line/features/owner_workspace/state/bulk_onboarding_service.dart';

/// Records what the screen hands the service, without a SupabaseClient.
///
/// `implements` plus noSuchMethod rather than `extends`: the real class takes a
/// client this test has no business constructing, and it has 33 async members
/// of which these tests care about two.
class _RecordingBulkService implements BulkOnboardingService {
  final List<List<Map<String, dynamic>>> investmentBatches = [];

  @override
  Future<ImportOutcome> submitInvestments({
    required String businessId,
    required List<Map<String, dynamic>> rows,
  }) async {
    investmentBatches.add(rows);
    return ImportOutcome(imported: rows.length, skipped: 0, errors: const []);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Entering a pre-existing book one person at a time.
///
/// The bulk wizard is seven pages of grids and a spreadsheet. That is right
/// for a book of two hundred customers and wrong for a book of three
/// investors -- and wrong for the one person the wizard missed, because
/// finishing that entry means walking all seven pages again.
///
/// The two doors are chosen PER STAGE, not per business. A real book brought
/// to this plan had 200 customers, 2 agents and 3 investors: the wizard is the
/// only sane way to do the customers, and one-by-one is plainly better than
/// building a spreadsheet for five people.
void main() {
  group('the spine', () {
    test('stages are ordered investors, agents, customers', () {
      // The Owner's order, and also the dependency order: a customer's loan is
      // the only stage that can fail because a person is not there yet.
      expect(ManaEntryStage.values.map((s) => s.name).toList(),
          ['investors', 'agents', 'customers']);
    });

    test('it opens on investors unless told otherwise', () {
      const screen = OneByOneMigrationScreen(businessId: 'b1');
      expect(screen.initialStage, ManaEntryStage.investors);
      expect(screen.onlyMlid, isNull);
    });

    test('a single-person entry names the stage it belongs to', () {
      // The missed-entry door: adding one person must not walk the other two
      // stages, which is the whole reason it exists.
      const screen = OneByOneMigrationScreen(
        businessId: 'b1',
        initialStage: ManaEntryStage.customers,
        onlyMlid: 'MLPI042496229',
      );
      expect(screen.initialStage, ManaEntryStage.customers);
      expect(screen.onlyMlid, 'MLPI042496229');
    });

    test('each stage knows the role it lists', () {
      // membersInRole takes the role as a string, and these are the values
      // business_member_role_enum actually holds -- read from it, not guessed.
      expect(ManaEntryStage.investors.role, 'Investor');
      expect(ManaEntryStage.agents.role, 'Agent');
      expect(ManaEntryStage.customers.role, 'Customer');
    });
  });

  group('investors', () {
    test('one investor is submitted as a one-row batch', () async {
      // The point of the whole design: the single-person path is the BULK path
      // with a list of one. app.bulk_import_investments is where the investor
      // money rules live, so calling it with one row means this door cannot
      // disagree with the wizard about what an investment is.
      final service = _RecordingBulkService();

      await saveInvestorRow(
        service: service,
        businessId: 'b1',
        row: const {'mlid': 'MLTI1', 'invested_amount': 50000},
      );

      expect(service.investmentBatches, hasLength(1));
      expect(service.investmentBatches.single, hasLength(1),
          reason: 'one person is one row, not a grid of one');
      expect(service.investmentBatches.single.single['mlid'], 'MLTI1');
    });

    test('an already-entered investment reports skipped, not failed', () async {
      // Re-entering somebody is the normal way to finish a partly-done import.
      // Reading skipped as a failure would send an Owner looking for a bug
      // that is actually the book already being correct.
      const outcome = ImportOutcome(imported: 0, skipped: 1, errors: []);
      expect(manaEntryFailed(outcome), isFalse);
      expect(manaEntryFailed(const ImportOutcome(
              imported: 0,
              skipped: 0,
              errors: [ImportRowError(row: 1, message: 'bad date')])),
          isTrue);
    });
  });
}
