import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/mana_time.dart';

/// Cheti — the Owner's own chit fund, held as an ASSET.
///
/// Reverses BR-061 ("recorded as business expense only"), which cannot
/// describe the instrument: instalments paid in come back as a lumpsum, so
/// the money is recoverable. Booking it as an expense would sink line profit
/// every period the cheti runs and then show one enormous phantom gain in the
/// period of availing.
///
/// See migration 20260801192125_add_chetis.sql for the schema reasoning.
enum ChetiType {
  /// Lucky draw. The instalment never varies and there is no dividend.
  fixed('Fixed'),

  /// Monthly bidding. Each instalment carries a dividend that reduces what is
  /// actually handed over.
  auction('Auction');

  const ChetiType(this.dbValue);
  final String dbValue;
  static ChetiType fromDb(String v) =>
      values.firstWhere((e) => e.dbValue == v, orElse: () => ChetiType.fixed);
}

enum ChetiFrequency {
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly');

  const ChetiFrequency(this.dbValue);
  final String dbValue;
  static ChetiFrequency fromDb(String v) => values
      .firstWhere((e) => e.dbValue == v, orElse: () => ChetiFrequency.monthly);
}

class Cheti {
  final String chetiId;
  final String name;
  final ChetiType type;
  final ChetiFrequency frequency;
  final int faceValue;
  final int totalInstalments;
  final int instalmentAmount;
  final DateTime startDate;

  /// Position carried in from before this app existed. Never replayed through
  /// BF -- that cash left the till already and is inside the declared opening
  /// balance.
  final int openingInstalmentsPaid;
  final int openingAmountPaid;

  final DateTime? availedDate;
  final int? availedAmount;
  final bool availedPreMigration;
  final String status;

  /// Instalments recorded since migration.
  final int recordedInstalments;
  final int recordedAmountPaid;

  /// Dividends earned since migration. Pre-migration dividends are last
  /// period's profit and are deliberately not counted here.
  final int recordedDividend;

  const Cheti({
    required this.chetiId,
    required this.name,
    required this.type,
    required this.frequency,
    required this.faceValue,
    required this.totalInstalments,
    required this.instalmentAmount,
    required this.startDate,
    required this.openingInstalmentsPaid,
    required this.openingAmountPaid,
    required this.availedDate,
    required this.availedAmount,
    required this.availedPreMigration,
    required this.status,
    required this.recordedInstalments,
    required this.recordedAmountPaid,
    required this.recordedDividend,
  });

  bool get isAvailed => availedDate != null;

  int get instalmentsPaid => openingInstalmentsPaid + recordedInstalments;
  int get instalmentsRemaining => totalInstalments - instalmentsPaid;

  /// Every rupee that has gone into this cheti, before and after migration.
  int get totalPaid => openingAmountPaid + recordedAmountPaid;

  int get totalReceived => availedAmount ?? 0;

  /// What the cheti is worth to the business right now.
  ///
  /// Positive: money in that has not come back yet -- an asset, and what the
  /// daily account shows alongside LB. Negative: more has been availed than
  /// paid in, so the remaining instalments are a liability.
  int get netPosition => totalPaid - totalReceived;

  /// Only meaningful once the term is finished, since instalments continue
  /// after availing.
  int? get finalProfit =>
      instalmentsRemaining <= 0 ? totalReceived - totalPaid : null;
}

class ChetiListState {
  final List<Cheti> chetis;
  final bool loading;
  const ChetiListState({this.chetis = const [], this.loading = false});

  /// The single figure the daily account puts next to LB.
  int get totalNetPosition =>
      chetis.fold(0, (sum, c) => sum + c.netPosition);
}

class ChetiApiService {
  final SupabaseClient _db;
  ChetiApiService(this._db);

  Future<List<Cheti>> fetchChetis({required String businessId}) async {
    final rows = await _db
        .from('chetis')
        .select('cheti_id, name, cheti_type, frequency, face_value, '
            'total_instalments, instalment_amount, start_date, '
            'opening_instalments_paid, opening_amount_paid, availed_date, '
            'availed_amount, availed_pre_migration, status, '
            'cheti_payments(gross_instalment, dividend, net_paid)')
        .eq('business_id', businessId)
        .order('start_date', ascending: false);

    return (rows as List).map((r) {
      // Aggregated client-side rather than by a view: the payment rows are
      // needed for the detail screen anyway, so a second round trip to have
      // Postgres sum them would buy nothing.
      final payments = (r['cheti_payments'] as List? ?? const []);
      var paidSum = 0;
      var dividendSum = 0;
      for (final p in payments) {
        paidSum += _num(p['net_paid']);
        dividendSum += _num(p['dividend']);
      }
      return Cheti(
        chetiId: r['cheti_id'] as String,
        name: r['name'] as String,
        type: ChetiType.fromDb(r['cheti_type'] as String),
        frequency: ChetiFrequency.fromDb(r['frequency'] as String),
        faceValue: _num(r['face_value']),
        totalInstalments: r['total_instalments'] as int,
        instalmentAmount: _num(r['instalment_amount']),
        startDate: DateTime.parse(r['start_date'] as String),
        openingInstalmentsPaid: r['opening_instalments_paid'] as int,
        openingAmountPaid: _num(r['opening_amount_paid']),
        availedDate: r['availed_date'] == null
            ? null
            : DateTime.parse(r['availed_date'] as String),
        availedAmount:
            r['availed_amount'] == null ? null : _num(r['availed_amount']),
        availedPreMigration: r['availed_pre_migration'] as bool? ?? false,
        status: r['status'] as String,
        recordedInstalments: payments.length,
        recordedAmountPaid: paidSum,
        recordedDividend: dividendSum,
      );
    }).toList();
  }

  /// Creates a cheti. A brand-new one leaves the opening figures at zero; a
  /// part-way one carries its standing position in without replaying history.
  Future<String> createCheti({
    required String businessId,
    required String name,
    required ChetiType type,
    required ChetiFrequency frequency,
    required int faceValue, // whole rupees (M8)
    required int totalInstalments,
    required int instalmentAmount,
    required DateTime startDate,
    int openingInstalmentsPaid = 0,
    int openingAmountPaid = 0,
    DateTime? availedDate,
    int? availedAmount,
    bool availedPreMigration = false,
    String? remarks,
  }) async {
    final row = await _db
        .from('chetis')
        .insert({
          'business_id': businessId,
          'name': name,
          'cheti_type': type.dbValue,
          'frequency': frequency.dbValue,
          'face_value': faceValue,
          'total_instalments': totalInstalments,
          'instalment_amount': instalmentAmount,
          'start_date': manaDateOf(startDate),
          'opening_instalments_paid': openingInstalmentsPaid,
          'opening_amount_paid': openingAmountPaid,
          if (availedDate != null) 'availed_date': manaDateOf(availedDate),
          if (availedAmount != null) 'availed_amount': availedAmount,
          'availed_pre_migration': availedPreMigration,
          if (remarks != null && remarks.isNotEmpty) 'remarks': remarks,
        })
        .select('cheti_id')
        .single();
    return row['cheti_id'] as String;
  }

  /// The signed-in Owner's membership in this business.
  ///
  /// Resolved here rather than passed in by every screen: cheti_payments
  /// requires it NOT NULL, and a caller guessing at it is how a row ends up
  /// attributed to the wrong member.
  /// Records one instalment. The RPC deducts it from the payer's own cash
  /// (Owner BF, or an Owner-permitted agent's float) and fills in the
  /// business date / recorded-by itself — the phone never picks the bucket.
  Future<void> recordPayment({
    required String chetiId,
    required int grossInstalment, // whole rupees (M8)
    int dividend = 0,
    String? remarks,
  }) async {
    await _db.schema('app').rpc('record_cheti_payment', params: {
      'p_cheti_id': chetiId,
      'p_gross_instalment': grossInstalment,
      'p_dividend': dividend,
      if (remarks != null && remarks.isNotEmpty) 'p_remarks': remarks,
    });
  }

  /// Records the lumpsum. The RPC adds it to the Owner's balance and refuses
  /// to avail the same cheti twice. Instalments continue afterwards until the
  /// term ends, so this does NOT close the cheti.
  Future<void> recordAvailing({
    required String chetiId,
    required int amount, // whole rupees (M8)
  }) async {
    await _db.schema('app').rpc('avail_cheti', params: {
      'p_cheti_id': chetiId,
      'p_amount': amount,
    });
  }

  static int _num(dynamic v) =>
      v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
}

final chetiApiServiceProvider = Provider<ChetiApiService>(
    (ref) => ChetiApiService(Supabase.instance.client));

class ChetiListNotifier extends StateNotifier<ChetiListState> {
  final Ref _ref;
  ChetiListNotifier(this._ref) : super(const ChetiListState());

  Future<void> load(String businessId) async {
    state = ChetiListState(chetis: state.chetis, loading: true);
    final rows =
        await _ref.read(chetiApiServiceProvider).fetchChetis(businessId: businessId);
    if (!mounted) return;
    state = ChetiListState(chetis: rows);
  }
}

final chetiListProvider =
    StateNotifierProvider<ChetiListNotifier, ChetiListState>(
        (ref) => ChetiListNotifier(ref));
