-- Where the bulk onboarding wizard had got to, on the server.
--
-- It was a flutter_secure_storage key, which meant the Owner's place was tied
-- to one handset: reinstall the app, or pick up the other phone, and eight
-- pages of a half-migrated book started again at page 1. Migrating a book is
-- not a one-sitting, one-device job.
--
-- On `businesses` rather than a table of its own because it is exactly one
-- number per business, and it belongs beside migration_locked and
-- migrated_through_date, which describe the same piece of work.
--
-- NOT derived from what is already imported. This business had four operating
-- areas before the wizard was ever run, so "areas exist" would have marked
-- page 2 done when it was not. A pointer the wizard writes itself cannot lie
-- about its own progress.
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS migration_wizard_step smallint;

COMMENT ON COLUMN businesses.migration_wizard_step IS
  'Bulk onboarding wizard page the Owner last reached (0-based). NULL means they have not started, or have not moved past page 1.';

-- Read. Owner-only, like everything else that touches a migration.
CREATE OR REPLACE FUNCTION app.migration_wizard_step(p_business_id uuid)
RETURNS smallint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_step smallint;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  SELECT migration_wizard_step INTO v_step
    FROM businesses WHERE business_id = p_business_id;

  RETURN v_step;
END;
$$;

-- Write.
--
-- Takes the step as given rather than only ever moving forward: going back a
-- page is a real thing an Owner does, and a pointer that only advanced would
-- drag them forward again on the next visit to a page they had deliberately
-- stepped away from.
CREATE OR REPLACE FUNCTION app.set_migration_wizard_step(
  p_business_id uuid,
  p_step smallint
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  IF p_step IS NULL OR p_step < 0 THEN
    RAISE EXCEPTION 'A wizard page cannot be negative.' USING ERRCODE = '23514';
  END IF;

  UPDATE businesses
     SET migration_wizard_step = p_step
   WHERE business_id = p_business_id;

  -- PostgREST reports 200 for an UPDATE that matched nothing, so a business
  -- that does not exist would look like a save that worked.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
END;
$$;
