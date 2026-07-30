-- MANA LINE — 0043_respond_to_membership_request_rpc.sql
--
-- Closes the recipient-side gap in the Global Workflow (OW-014) request
-- flow: an Owner can request someone as Agent/Investor/Customer
-- (business_members row inserted with status 'Pending Invitation'), but
-- the RECIPIENT had no way to see or act on that request — no self
-- UPDATE policy exists on business_members at all (only
-- business_members_owner_all and business_members_self_select). This RPC
-- is the bootstrap path, same pattern as everything else this session.

CREATE OR REPLACE FUNCTION app.respond_to_membership_request(
  p_membership_id UUID,
  p_accept BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_person_id BIGINT := app.current_person_id();
  v_current_status membership_status_enum;
  v_owner_id BIGINT;
BEGIN
  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'No authenticated person_id in JWT claims';
  END IF;

  -- Verify the caller actually IS the target of this specific request —
  -- never let one person accept/decline on behalf of another.
  SELECT bm.membership_status, b.owner_person_id INTO v_current_status, v_owner_id
  FROM business_members bm
  JOIN businesses b ON b.business_id = bm.business_id
  WHERE bm.membership_id = p_membership_id AND bm.person_id = v_person_id;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'No matching pending request found for this person' USING ERRCODE = '42501';
  END IF;

  IF v_current_status != 'Pending Invitation' THEN
    RAISE EXCEPTION 'This request is no longer pending (current status: %)', v_current_status;
  END IF;

  IF p_accept THEN
    UPDATE business_members SET membership_status = 'Active' WHERE membership_id = p_membership_id;
  ELSE
    UPDATE business_members SET membership_status = 'Removed' WHERE membership_id = p_membership_id;
  END IF;

  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION app.respond_to_membership_request(UUID, BOOLEAN) IS
  'Lets a person accept or decline their own pending business membership request (business_members.membership_status Pending Invitation -> Active/Removed). Verifies caller is the actual target person_id — cannot act on someone else''s request.';

GRANT EXECUTE ON FUNCTION app.respond_to_membership_request(UUID, BOOLEAN) TO authenticated;
