-- Registration returned 500 to every single person who tried it.
--
--   auth-register insert failed {
--     code: "42501", message: "permission denied for schema app" }
--
-- The INSERT into persons fires trg_stamp_migrated_person, whose body calls
-- app.migration_import_active(). That trigger function is the only SECURITY
-- INVOKER one on the table -- trg_hash_person_aadhaar, trg_sync_person_name
-- and trg_clear_aadhaar_on_erasure are all DEFINER -- so it runs as whoever
-- did the INSERT. Edge Functions insert as service_role, and service_role has
-- no USAGE on schema app: anon and authenticated do, which is why every
-- in-app path worked and only the one that matters for a new person did not.
--
-- DEFINER rather than GRANT USAGE ON SCHEMA app TO service_role. The grant
-- would open all 200-odd app functions to the service key to fix one trigger
-- reading one session variable; matching the siblings fixes it exactly where
-- it broke. The function already pins its search_path, which is the half of
-- SECURITY DEFINER that makes it safe.
--
-- app.migration_import_active() reads current_setting('app.migration_import'),
-- which is session state -- SECURITY DEFINER changes the executing role, not
-- the session -- so a migration import still stamps is_migrated exactly as
-- before.
--
-- The body is unchanged.
CREATE OR REPLACE FUNCTION app.stamp_migrated_person()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF app.migration_import_active() THEN
    NEW.is_migrated := true;
  END IF;
  RETURN NEW;
END;
$function$;
