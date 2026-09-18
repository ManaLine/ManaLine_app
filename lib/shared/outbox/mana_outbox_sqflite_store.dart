import 'package:sqflite/sqflite.dart';

import 'mana_outbox.dart';

/// The outbox on disk.
///
/// WHY DISK AND NOT MEMORY. An agent records four collections in a village
/// with no signal, then the phone runs flat or Android kills the app to
/// reclaim memory. Those four must still be there. Losing them silently is the
/// one outcome this whole feature exists to prevent, and it is the outcome an
/// in-memory queue produces.
///
/// DELIBERATELY DUMB. Every decision about what an entry may do lives in
/// ManaOutboxEntry and ManaOutbox, which are pure Dart and testable without a
/// device. This file holds no rules -- it reads and writes rows. Anything that
/// looks like a rule appearing here means it has been duplicated, and two
/// copies of a money rule is how they come to disagree.
class ManaOutboxSqfliteStore implements ManaOutboxStore {
  Database? _db;

  /// The table version. A change here needs a migration in [_migrate], not a
  /// drop -- the rows are unsent collections, which is to say somebody's money.
  static const int _version = 1;

  static const String _table = 'mana_outbox';

  Future<void> open({String? path}) async {
    _db = await openDatabase(
      path ?? 'mana_outbox.db',
      version: _version,
      onCreate: (db, _) => _migrate(db, 0, _version),
      onUpgrade: (db, from, to) => _migrate(db, from, to),
    );
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 1) {
      // No FOREIGN KEY to anything: the loan and customer this points at live
      // on the server, and a local constraint could not check them anyway. The
      // server does that, sixteen ways, in app.record_collection.
      await db.execute('''
        CREATE TABLE $_table (
          id                   TEXT PRIMARY KEY,
          idempotency_key      TEXT NOT NULL,
          state                TEXT NOT NULL,
          business_id          TEXT NOT NULL,
          loan_id              TEXT NOT NULL,
          customer_id          TEXT NOT NULL,
          customer_name        TEXT NOT NULL,
          collected_amount     INTEGER NOT NULL,
          business_date        TEXT NOT NULL,
          payload              TEXT NOT NULL,
          attempts             INTEGER NOT NULL DEFAULT 0,
          last_error           TEXT,
          created_at           TEXT NOT NULL,
          server_collection_id TEXT
        )
      ''');
      // The queue is read by state on every flush and drawn in order on every
      // open. Both on a cheap handset, so both are indexed.
      await db.execute(
          'CREATE INDEX ${_table}_state_idx ON $_table (state, created_at)');
    }
  }

  /// Whether [open] has succeeded.
  ///
  /// EXISTS BECAUSE "CLOSED" IS A NORMAL STATE, not a fault. `manaOpenOutbox`
  /// deliberately declines on the web -- sqflite has no web implementation --
  /// and it also swallows a genuine open failure on a handset rather than
  /// refusing to start the app. Both leave a store that is fine and empty,
  /// and a reader that treats that as an exception turns a designed fallback
  /// into a crash.
  bool get isOpen => _db != null;

  Database get _open {
    final db = _db;
    if (db == null) {
      throw StateError('The outbox database is not open. Call open() first.');
    }
    return db;
  }

  @override
  Future<List<ManaOutboxEntry>> all() async {
    // Nothing is queued if there is nowhere to queue it. Returning empty
    // rather than throwing is what makes a closed outbox a quiet no-op
    // instead of an uncaught error on every flush.
    if (!isOpen) return const [];
    // Oldest first: the order the agent recorded them is the order they should
    // be sent and the order the queue should read. A village round is
    // chronological, and so is the paper book beside it.
    final rows = await _open.query(_table, orderBy: 'created_at ASC, id ASC');
    return rows.map(ManaOutboxEntry.fromRow).toList();
  }

  @override
  Future<void> put(ManaOutboxEntry entry) async {
    // REPLACE, not insert: the sender writes an entry more than once in a
    // single pass -- sending, then the outcome -- and three rows for one
    // collection would show the agent a queue of phantoms.
    await _open.insert(_table, entry.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> remove(String id) async {
    await _open.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
