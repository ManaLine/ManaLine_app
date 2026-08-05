-- P4 Security: temporary disable, and a 90-day deletion request.
--
-- persons had no account state at all. The only thing resembling one was
-- is_deceased, which auth-login checks -- so "disable my account" had nowhere
-- to be recorded.
--
-- WHAT THIS MIGRATION DOES NOT DO: purge. The 90-day permanent deletion is
-- deliberately not implemented here, because the only existing deletion path,
-- app.admin_delete_person, HARD DELETES the person's loans, collections and
-- investments. For a Customer that is not their data alone -- those rows are
-- the Owner's book. Deleting them would make app.recompute_day_ledger rebuild
-- every affected day without those collections, and both BF pots would move.
-- A person leaving must not silently rewrite someone else's money. What the
-- purge should actually do is a decision, not an implementation detail, and it
-- is recorded as an open one rather than guessed at.
--
-- So this migration ships the reversible half: the state, the request, and the
-- ability to change your mind. purge_after is stored now so the clock is
-- honest from the moment the request is made.
--
-- ENFORCEMENT lives in the auth-login Edge Function, which is the only place
-- it can: every other entry point already holds a minted token. See
-- supabase/functions/auth-login/index.ts.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'account_status_enum') THEN
    CREATE TYPE account_status_enum AS ENUM (
      'Active',
      'Temporarily Disabled',
      'Pending Deletion'
    );
  END IF;
END $$;

ALTER TABLE persons
  ADD COLUMN IF NOT EXISTS account_status account_status_enum NOT NULL DEFAULT 'Active',
  ADD COLUMN IF NOT EXISTS account_disabled_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS deletion_requested_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS purge_after DATE;

-- Partial index: the purge job will scan for due rows, and in a healthy system
-- almost every row is 'Active'.
CREATE INDEX IF NOT EXISTS idx_persons_pending_deletion
  ON persons (purge_after)
  WHERE account_status = 'Pending Deletion';

-- ---------------------------------------------------------------------------
-- Disable: keeps everything, blocks login.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.disable_own_account()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_person BIGINT := app.current_person_id();
BEGIN
  IF v_person IS NULL THEN
    RAISE EXCEPTION 'Not signed in' USING ERRCODE = '42501';
  END IF;

  UPDATE persons
     SET account_status = 'Temporarily Disabled',
         account_disabled_at = now(),
         -- A disable is not a deletion. Clearing these means someone who asked
         -- to delete and then only disabled does not keep a running purge
         -- clock they can no longer see.
         deletion_requested_at = NULL,
         purge_after = NULL
   WHERE person_id = v_person;

  INSERT INTO audit_log (actor_person_id, action_type, entity_type, entity_id,
                         new_value, business_date)
  VALUES (v_person, 'Other Admin Event', 'account_disabled', 0,
          json_build_object('at', now()), CURRENT_DATE);

  RETURN json_build_object('status', 'Temporarily Disabled');
END;
$function$;

-- ---------------------------------------------------------------------------
-- Request deletion: starts the 90-day clock. Reversible for all 90 days.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.request_account_deletion()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_person BIGINT := app.current_person_id();
  v_purge  DATE := (CURRENT_DATE + INTERVAL '90 days')::date;
  v_owned  INT;
BEGIN
  IF v_person IS NULL THEN
    RAISE EXCEPTION 'Not signed in' USING ERRCODE = '42501';
  END IF;

  -- An Owner with a live business cannot simply leave: the business, its
  -- agents and its customers would be orphaned with no one able to administer
  -- them. Business Transfer is the route for that, and it is a separate
  -- feature. Refused with a message that says so rather than a generic error.
  SELECT count(*) INTO v_owned
    FROM businesses b
   WHERE b.owner_person_id = v_person
     AND b.business_status <> 'Suspended';
  IF v_owned > 0 THEN
    RAISE EXCEPTION 'You still own % business(es). Transfer or close them before deleting your account.', v_owned
      USING ERRCODE = '23514';
  END IF;

  UPDATE persons
     SET account_status = 'Pending Deletion',
         deletion_requested_at = now(),
         purge_after = v_purge,
         account_disabled_at = COALESCE(account_disabled_at, now())
   WHERE person_id = v_person;

  INSERT INTO audit_log (actor_person_id, action_type, entity_type, entity_id,
                         new_value, business_date)
  VALUES (v_person, 'Other Admin Event', 'account_deletion_requested', 0,
          json_build_object('purge_after', v_purge), CURRENT_DATE);

  RETURN json_build_object('status', 'Pending Deletion', 'purge_after', v_purge);
END;
$function$;

-- ---------------------------------------------------------------------------
-- Reactivate: undoes either state.
--
-- SECURITY DEFINER and callable by the person themselves, because the only way
-- to reach it is with a valid JWT, and the only way to get one is to present
-- the right credential. auth-login mints that token only after a successful
-- bcrypt compare, so "prove it is you" has already happened.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.reactivate_own_account()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_person BIGINT := app.current_person_id();
BEGIN
  IF v_person IS NULL THEN
    RAISE EXCEPTION 'Not signed in' USING ERRCODE = '42501';
  END IF;

  UPDATE persons
     SET account_status = 'Active',
         account_disabled_at = NULL,
         deletion_requested_at = NULL,
         purge_after = NULL
   WHERE person_id = v_person;

  INSERT INTO audit_log (actor_person_id, action_type, entity_type, entity_id,
                         new_value, business_date)
  VALUES (v_person, 'Other Admin Event', 'account_reactivated', 0,
          json_build_object('at', now()), CURRENT_DATE);

  RETURN json_build_object('status', 'Active');
END;
$function$;

-- Reads its own row's state, for the Security screen.
CREATE OR REPLACE FUNCTION app.own_account_status()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_person BIGINT := app.current_person_id();
  r RECORD;
BEGIN
  IF v_person IS NULL THEN
    RAISE EXCEPTION 'Not signed in' USING ERRCODE = '42501';
  END IF;

  SELECT account_status, account_disabled_at, deletion_requested_at, purge_after
    INTO r FROM persons WHERE person_id = v_person;

  RETURN json_build_object(
    'account_status', r.account_status,
    'account_disabled_at', r.account_disabled_at,
    'deletion_requested_at', r.deletion_requested_at,
    'purge_after', r.purge_after,
    'days_remaining',
      CASE WHEN r.purge_after IS NULL THEN NULL
           ELSE GREATEST((r.purge_after - CURRENT_DATE), 0) END
  );
END;
$function$;

REVOKE ALL ON FUNCTION app.disable_own_account() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.request_account_deletion() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.reactivate_own_account() FROM PUBLIC;
REVOKE ALL ON FUNCTION app.own_account_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.disable_own_account() TO authenticated;
GRANT EXECUTE ON FUNCTION app.request_account_deletion() TO authenticated;
GRANT EXECUTE ON FUNCTION app.reactivate_own_account() TO authenticated;
GRANT EXECUTE ON FUNCTION app.own_account_status() TO authenticated;
