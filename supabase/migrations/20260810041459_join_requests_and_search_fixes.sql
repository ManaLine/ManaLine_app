-- Applied via MCP as 20260810041459. Filename carries that exact stamp so a
-- later `supabase db push` does not re-run it.
--
-- 1. request_join_business — never worked, and wrote to the wrong table.
--
-- Two defects. First it threw 42883 on EVERY call: p_role is character
-- varying, business_members.role is business_member_role_enum, and Postgres
-- has no implicit operator between them, so the duplicate-check IF EXISTS
-- aborted before anything ran. Not type-checked at CREATE time, so it
-- applied cleanly and failed only when invoked.
--
-- Second, and the reason a plain cast is not enough: it inserted straight
-- into business_members as 'Pending Invitation'. OW-003's Approve/Reject
-- queue reads membership_requests, so a request made this way was visible
-- to the Owner but had no control to action it — the person sat in the list
-- permanently. Fixing only the cast would have started manufacturing
-- exactly those stuck rows.
--
-- It now writes a membership_requests row, the same shape IW-002 already
-- writes, so every join request in the app converges on the one queue that
-- exists and works. Role child rows (agents/customers/investors) are NOT
-- created here any more either — approval creates them, which is what makes
-- approval mean something.
CREATE OR REPLACE FUNCTION app.request_join_business(
  p_business_id UUID,
  p_role VARCHAR
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_person_id BIGINT := app.current_person_id();
  v_role business_member_role_enum;
  v_request_id UUID;
  v_cooldown TIMESTAMP;
BEGIN
  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'No authenticated person_id in JWT claims' USING ERRCODE = '42501';
  END IF;

  IF p_role NOT IN ('Agent', 'Investor', 'Customer') THEN
    RAISE EXCEPTION 'Invalid role — must be Agent, Investor, or Customer' USING ERRCODE = '22023';
  END IF;
  v_role := p_role::business_member_role_enum;

  -- Already a member in this role (Removed does not count — leaving and
  -- rejoining is legitimate).
  IF EXISTS (
    SELECT 1 FROM business_members
    WHERE person_id = v_person_id
      AND business_id = p_business_id
      AND role = v_role
      AND membership_status <> 'Removed'
  ) THEN
    RAISE EXCEPTION 'You are already a % at this business.', p_role
      USING ERRCODE = '23505';
  END IF;

  -- Already waiting on a decision.
  IF EXISTS (
    SELECT 1 FROM membership_requests
    WHERE person_id = v_person_id
      AND business_id = p_business_id
      AND requested_role = p_role::membership_request_role_enum
      AND status = 'Pending'
  ) THEN
    RAISE EXCEPTION 'You already have a request pending for this role at this business.'
      USING ERRCODE = '23505';
  END IF;

  -- 24-hour cooldown after a rejection (BR pattern, API spec §2.6).
  SELECT cooldown_until INTO v_cooldown
  FROM membership_requests
  WHERE person_id = v_person_id
    AND business_id = p_business_id
    AND requested_role = p_role::membership_request_role_enum
    AND status = 'Rejected'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_cooldown IS NOT NULL AND v_cooldown > (now() AT TIME ZONE 'Asia/Kolkata') THEN
    RAISE EXCEPTION 'You may reapply to this business after %.', v_cooldown
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO membership_requests (person_id, business_id, requested_role, status)
  VALUES (v_person_id, p_business_id, p_role::membership_request_role_enum, 'Pending')
  RETURNING request_id INTO v_request_id;

  RETURN v_request_id;
END;
$$;

-- 2. owner_search_person — LIMIT 1 on the NAME branch meant a search for
-- "sai" could only ever return one of several people called Sai. The
-- unique-identifier branches keep LIMIT 1 because MLID, Aadhaar and mobile
-- are unique by constraint; a name is not, and never was.
CREATE OR REPLACE FUNCTION app.owner_search_person(
  p_mlid TEXT DEFAULT NULL,
  p_mobile_number TEXT DEFAULT NULL,
  p_aadhaar_number TEXT DEFAULT NULL,
  p_full_name TEXT DEFAULT NULL
) RETURNS TABLE (
  person_id BIGINT,
  full_name VARCHAR,
  father_husband_name VARCHAR,
  mobile_number VARCHAR,
  mlid VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM businesses WHERE owner_person_id = app.current_person_id()
  ) THEN
    RAISE EXCEPTION 'Not authorized — Owner only' USING ERRCODE = '42501';
  END IF;

  IF p_mlid IS NOT NULL AND p_mlid <> '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.mlid = p_mlid LIMIT 1;
  ELSIF p_aadhaar_number IS NOT NULL AND p_aadhaar_number <> '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.aadhaar_number = p_aadhaar_number LIMIT 1;
  ELSIF p_mobile_number IS NOT NULL AND p_mobile_number <> '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.mobile_number = p_mobile_number LIMIT 1;
  ELSIF p_full_name IS NOT NULL AND p_full_name <> '' THEN
    -- Many rows, shortest first so an exact-ish match leads. Capped at 25:
    -- this feeds a bottom sheet, not a report.
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p
      WHERE p.full_name ILIKE '%' || p_full_name || '%'
      ORDER BY length(p.full_name), p.full_name
      LIMIT 25;
  END IF;
END;
$$;

-- 3. removed_at was never stamped, so a Removed membership carried no record
-- of WHEN it closed — BR-203 says history is preserved, and a timestamp is
-- most of that history. Backfills the existing rows from updated_at, then
-- keeps it true going forward.
UPDATE business_members
   SET removed_at = COALESCE(removed_at, updated_at, created_at)
 WHERE membership_status = 'Removed' AND removed_at IS NULL;

CREATE OR REPLACE FUNCTION app.stamp_membership_removed_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.membership_status = 'Removed' AND OLD.membership_status <> 'Removed' THEN
    NEW.removed_at := COALESCE(NEW.removed_at, now() AT TIME ZONE 'Asia/Kolkata');
  ELSIF NEW.membership_status <> 'Removed' THEN
    -- Rejoining clears it, so removed_at always describes the CURRENT state.
    NEW.removed_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stamp_membership_removed_at ON business_members;
CREATE TRIGGER trg_stamp_membership_removed_at
  BEFORE UPDATE ON business_members
  FOR EACH ROW EXECUTE FUNCTION app.stamp_membership_removed_at();
