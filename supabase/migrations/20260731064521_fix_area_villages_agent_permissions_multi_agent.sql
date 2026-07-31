-- Fixes for four reported faults, three of which trace to my own earlier
-- migrations.
--
-- (A) DEACTIVATED AREAS KEPT THEIR VILLAGES. removeOperatingArea set the
--     area to Inactive but left operating_area_locations rows live, so
--     uq_oal_business_location still held the slot. Adding one of those
--     villages to another area failed with "already covered by one of your
--     operating areas" — pointing at an area the Owner had already removed.
--     Village rows now retire with their area.
--
-- (B) NO agent_permissions ROW FOR THE OWNER-AS-AGENT. owner_is_first_agent
--     created business_members + agents but not agent_permissions.
--     updateAgentPermissions is an UPDATE ... WHERE agent_id = ?, which
--     matched zero rows: PostgREST returns 200, nothing saves, no error.
--     That is why Save Permissions did nothing. Backfilled, and business
--     creation now writes all three rows.
--
-- (C) MULTIPLE AGENTS PER AREA. GLOBAL BR-065 is explicit — "Shared route
--     but individual transaction accountability" — so a route may carry
--     several agents. Nothing in the schema forbade it; the Dart layer was
--     superseding the previous assignment on every assign. Enforced here
--     only to the extent of preventing the SAME agent being assigned twice
--     to one area.

-- --------------------------------------------------------------------
-- A. Village rows retire with their area, and backfill the two that did not.
-- --------------------------------------------------------------------
UPDATE operating_area_locations l
SET removed_at = now()
FROM operating_areas oa
WHERE oa.operating_area_id = l.operating_area_id
  AND oa.status = 'Inactive'
  AND l.removed_at IS NULL;

CREATE OR REPLACE FUNCTION app.deactivate_operating_area(p_operating_area_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_business_id UUID;
BEGIN
  SELECT business_id INTO v_business_id FROM operating_areas
  WHERE operating_area_id = p_operating_area_id;
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Operating area not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may remove an operating area' USING ERRCODE = '42501';
  END IF;

  UPDATE operating_areas SET status = 'Inactive'
  WHERE operating_area_id = p_operating_area_id;

  -- Free the villages so they can join another round.
  UPDATE operating_area_locations SET removed_at = now()
  WHERE operating_area_id = p_operating_area_id AND removed_at IS NULL;

  -- And release the agents, so a removed area stops appearing in their
  -- assignment list.
  UPDATE agent_area_assignments SET removed_at = now()
  WHERE operating_area_id = p_operating_area_id AND removed_at IS NULL;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.deactivate_operating_area(uuid) TO authenticated;

-- --------------------------------------------------------------------
-- B. agent_permissions for every agent that lacks one.
-- --------------------------------------------------------------------
INSERT INTO agent_permissions (agent_id)
SELECT a.agent_id FROM agents a
LEFT JOIN agent_permissions ap ON ap.agent_id = a.agent_id
WHERE ap.permission_profile_id IS NULL;

-- Business creation writes all three rows from now on.
CREATE OR REPLACE FUNCTION app.create_business_with_owner(
  p_mlbi character varying,
  p_business_name character varying,
  p_registered_finance_name character varying,
  p_logo_url text DEFAULT NULL::text,
  p_business_type character varying DEFAULT NULL::character varying,
  p_business_address text DEFAULT NULL::text,
  p_business_phone character varying DEFAULT NULL::character varying,
  p_business_email character varying DEFAULT NULL::character varying
)
RETURNS TABLE(business_id uuid, mlbi character varying)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_person_id     BIGINT := app.current_person_id();
  v_business_id   UUID;
  v_agent_member  UUID;
  v_agent_id      UUID;
BEGIN
  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'No authenticated person_id in JWT claims';
  END IF;

  INSERT INTO businesses (
    mlbi, owner_person_id, business_name, registered_finance_name,
    logo_url, business_type, business_address, business_phone, business_email
  ) VALUES (
    p_mlbi, v_person_id, p_business_name, p_registered_finance_name,
    p_logo_url, p_business_type, p_business_address, p_business_phone, p_business_email
  )
  RETURNING businesses.business_id INTO v_business_id;

  INSERT INTO business_members (
    person_id, business_id, role, membership_status,
    verification_status, onboarding_method, joined_at
  ) VALUES (
    v_person_id, v_business_id, 'Owner', 'Active',
    'Not Required', 'Direct Registration', now()
  );

  INSERT INTO business_members (
    person_id, business_id, role, membership_status,
    verification_status, onboarding_method, joined_at
  ) VALUES (
    v_person_id, v_business_id, 'Agent', 'Active',
    'Not Required', 'Direct Registration', now()
  )
  RETURNING membership_id INTO v_agent_member;

  INSERT INTO agents (membership_id, person_id, joined_date)
  VALUES (v_agent_member, v_person_id, CURRENT_DATE)
  RETURNING agent_id INTO v_agent_id;

  -- Without this row, Save Permissions is a silent no-op forever.
  INSERT INTO agent_permissions (agent_id) VALUES (v_agent_id);

  RETURN QUERY SELECT v_business_id, p_mlbi;
END;
$function$;

-- --------------------------------------------------------------------
-- C. One agent may not be assigned to the same area twice; several
--    different agents on one area is allowed (BR-065).
-- --------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_area_assignment_live
  ON public.agent_area_assignments (operating_area_id, agent_id)
  WHERE removed_at IS NULL;
