-- Store every naive timestamp in IST, one convention, database-wide.
--
-- THE BUG: `public` has 85 `timestamp without time zone` columns and ZERO
-- `timestamptz` columns. 57 of them default to `now()`, which under the old
-- session TimeZone of UTC stored a UTC wall clock. But the Flutter client
-- writes the other ~30 with `DateTime.now().toIso8601String()`, which on an
-- Indian phone emits a naive IST wall clock with no offset suffix. So one
-- column could hold both conventions and nothing ever errored.
--
-- Observed live: agent_permissions.updated_at read 2026-08-01 04:51:38 while
-- the database clock read 2026-07-31 23:29 UTC — an audit row stamped 5h21m
-- in the FUTURE. Same pattern reaches removed_at, superseded_at, resolved_at,
-- reopened_at, business_started_at and loan_requests.cooldown_until (a 24h
-- lending guard that actually ran ~29.5h).
--
-- WHY IST AND NOT UTC: the entire user base is rural Andhra Pradesh. India is
-- a single timezone with no daylight saving, which is the one case where a
-- naive local wall clock is unambiguous and round-trips safely. It also
-- already matches `business_date`, which is derived from the LOCAL date and
-- is correct that way — a collection taken at 00:30 IST belongs to the Indian
-- business day, not to the previous UTC day. Converting the dates to UTC to
-- "match" the timestamps would have moved money into the wrong business day.
--
-- WHY A DATABASE SETTING AND NOT 57 ALTER COLUMN DEFAULTS: assigning the
-- timestamptz returned by `now()` into a naive column converts it using the
-- session TimeZone. Setting that once fixes all 57 defaults AND every plpgsql
-- function that writes `now()` into a naive column, with no per-column DDL and
-- nothing to keep in sync later. Safe because `public` has no timestamptz
-- column whose stored meaning could shift; Supabase's internal auth/storage
-- schemas do use timestamptz, but those store absolute instants and are
-- unaffected by a display timezone.
--
-- NOT BACKFILLED, deliberately. Rows written before this point are a mix:
-- server-default rows are UTC, client-written rows are already IST, and the
-- two are indistinguishable per row, so a blanket shift would corrupt the
-- half that was already right. The money tables (loans, collections) are
-- still EMPTY, so nothing financial predates this change.
--
-- The client side is fixed to match in lib/shared/mana_time.dart — it now
-- sends an explicit IST wall clock rather than whatever the handset's
-- timezone happens to be.
do $$
begin
  execute format('alter database %I set timezone to %L', current_database(), 'Asia/Kolkata');
end
$$;
