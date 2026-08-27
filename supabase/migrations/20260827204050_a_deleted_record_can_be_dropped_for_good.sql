-- Superseded in the same session by 20260827204340, which added dependent
-- handling. Kept because the ledger stamped it: a later push must not
-- re-run a version the database already has.
--
-- What it introduced: app.purge_record(entity, record_id) -- a hard delete an
-- Owner can ask for from the Trash screen, guarded so it can only ever act on
-- something already in the bin.
select 1;
