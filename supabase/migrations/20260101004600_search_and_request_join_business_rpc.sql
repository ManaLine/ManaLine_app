-- MANA LINE — 0046_search_and_request_join_business_rpc.sql
--
-- Closes a real gap: the only way to join a business was for the OWNER
-- to search and request a person (Batch 4's owner_search_person_by_mlid
-- + respond_to_membership_request). There was no reverse path — a
-- person finding a business themselves (by its public MLBI code) and
-- requesting to join it as Agent/Investor/Customer. businesses RLS
-- (businesses_owner_all, businesses_member_select) only lets someone see
-- a business they already own or belong to — by definition useless for
-- "find a business I'm not part of yet."

-- -----------------------------------------------------------------------------
-- app.search_business_by_mlbi — any authenticated person may look up a
-- business by its exact MLBI, regardless of whether they're already a
-- member. Returns minimal public-facing fields only (name, MLBI, logo) —
-- not financial data, membership lists, or anything else businesses_owner
-- can see.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.search_business_by_mlbi(p_mlbi VARCHAR)
RETURNS TABLE (business_id UUID, business_name VARCHAR, mlbi VARCHAR, logo_url TEXT, business_status business_status_enum)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT b.business_id, b.business_name, b.mlbi, b.logo_url, b.business_status
  FROM businesses b
  WHERE b.mlbi = p_mlbi
  LIMIT 1;
$$;

COMMENT ON FUNCTION app.search_business_by_mlbi(VARCHAR) IS
  'Self-service business lookup by exact MLBI — any authenticated person, regardless of existing membership. Returns only public-facing fields (name, MLBI, logo, status), never financial or membership data.';

GRANT EXECUTE ON FUNCTION app.search_business_by_mlbi(VARCHAR) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.request_join_business — the calling person requests to join a
-- business (found via search_business_by_mlbi) with a chosen role. Same
-- 'Pending Invitation' status as the Owner-initiated direction (0035's
-- request flow / OW-014), so both directions land in the identical
-- state and are handled by the same Accept/Decline UI already built for
-- the recipient side (LR-012, Batch 4) — this just lets the OTHER party
-- (the business's Owner) be the one who needs to accept it, via their
-- existing OW-002/003/004 Pending Invitation lists.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.request_join_business(
  p_business_id UUID,
  p_role VARCHAR -- 'Agent' | 'Investor' | 'Customer'
)
RETURNS UUID -- returns the new membership_id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_person_id BIGINT := app.current_person_id();
  v_membership_id UUID;
BEGIN
  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'No authenticated person_id in JWT claims';
  END IF;

  IF p_role NOT IN ('Agent', 'Investor', 'Customer') THEN
    RAISE EXCEPTION 'Invalid role — must be Agent, Investor, or Customer';
  END IF;

  IF EXISTS (
    SELECT 1 FROM business_members
    WHERE person_id = v_person_id AND business_id = p_business_id AND role = p_role
      AND membership_status NOT IN ('Removed')
  ) THEN
    RAISE EXCEPTION 'You already have a request or membership for this role at this business.' USING ERRCODE = '23505';
  END IF;

  INSERT INTO business_members (
    person_id, business_id, role, membership_status, verification_status, onboarding_method
  ) VALUES (
    v_person_id, p_business_id, p_role, 'Pending Invitation',
    CASE WHEN p_role = 'Customer' THEN 'Not Required' ELSE 'Pending Verification' END,
    'ID Lookup'
  ) RETURNING membership_id INTO v_membership_id;

  -- Role-specific child row, same pattern as register_new_agent/customer —
  -- required so the Owner's own list queries (agents!inner/customers
  -- joins) actually surface this pending request instead of silently
  -- dropping it.
  IF p_role = 'Agent' THEN
    INSERT INTO agents (membership_id, person_id, joined_date) VALUES (v_membership_id, v_person_id, CURRENT_DATE);
    INSERT INTO agent_permissions (agent_id) SELECT agent_id FROM agents WHERE membership_id = v_membership_id;
  ELSIF p_role = 'Customer' THEN
    INSERT INTO customers (membership_id, person_id, occupation, occupation_other_text, customer_since)
    VALUES (v_membership_id, v_person_id, 'Other-Custom', 'Not specified at request time', CURRENT_DATE);
  ELSIF p_role = 'Investor' THEN
    INSERT INTO investors (membership_id, person_id) VALUES (v_membership_id, v_person_id);
  END IF;

  RETURN v_membership_id;
END;
$$;

COMMENT ON FUNCTION app.request_join_business(UUID, VARCHAR) IS
  'Self-service reverse-direction join request. Creates business_members + the role-specific child row (agents/customers/investors), same Pending Invitation status as the Owner-initiated direction — the business Owner accepts/declines via their existing Pending Invitation lists.';

GRANT EXECUTE ON FUNCTION app.request_join_business(UUID, VARCHAR) TO authenticated;
