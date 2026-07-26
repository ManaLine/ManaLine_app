-- MANA LINE — 0034_create_business_with_owner_rpc.sql
--
-- WHY THIS EXISTS: OW-000's createBusiness() was doing a plain client-side
-- `.insert()` into `businesses` only. That succeeds (businesses' own RLS
-- is presumably satisfiable directly), but it never created a matching
-- `business_members` row for the creator — and it structurally CAN'T:
-- business_members' only insert policy is
--   WITH CHECK (app.is_owner(business_id))
-- which checks for an EXISTING Active Owner membership row on that
-- business. At the exact moment of creating a brand-new business, no such
-- row exists yet — a genuine chicken-and-egg RLS gap, not something any
-- client-side insert could ever satisfy. This is precisely the kind of
-- case this project's own standing architecture already has a pattern
-- for: bypass via a narrow SECURITY DEFINER RPC that does both inserts
-- atomically, rather than loosening the RLS policy itself.
--
-- SYMPTOM THIS FIXES: newly created businesses never appeared on
-- LR-012 (Business Selector) or on re-login, because fetchMemberships()
-- was correctly querying business_members via RLS and correctly finding
-- nothing — the membership row genuinely never existed, this was never a
-- caching/refresh issue.

CREATE OR REPLACE FUNCTION app.create_business_with_owner(
  p_mlbi                     VARCHAR(20),
  p_business_name            VARCHAR(150),
  p_registered_finance_name  VARCHAR(150),
  p_logo_url                 TEXT DEFAULT NULL,
  p_business_type            VARCHAR(100) DEFAULT NULL,
  p_business_address         TEXT DEFAULT NULL,
  p_business_phone           VARCHAR(15) DEFAULT NULL,
  p_business_email           VARCHAR(150) DEFAULT NULL
)
RETURNS TABLE (business_id UUID, mlbi VARCHAR(20))
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_person_id   BIGINT := app.current_person_id();
  v_business_id UUID;
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

  -- The creator is always the Owner, always Active immediately — no
  -- invitation/acceptance step applies to self-registration (BR-185:
  -- exactly one Owner per business).
  INSERT INTO business_members (
    person_id, business_id, role, membership_status,
    verification_status, onboarding_method, joined_at
  ) VALUES (
    v_person_id, v_business_id, 'Owner', 'Active',
    'Not Required', 'Direct Registration', now()
  );

  RETURN QUERY SELECT v_business_id, p_mlbi;
END;
$$;

GRANT EXECUTE ON FUNCTION app.create_business_with_owner TO authenticated;

COMMENT ON FUNCTION app.create_business_with_owner IS
  'Atomically creates a business and its founding Owner business_members row. Required because business_members insert RLS (app.is_owner) cannot be satisfied by a brand-new business''s creator — no Owner row exists yet to check against. Added 0034 after OW-000''s plain client insert was found to silently never create the membership row (real businesses existed with no linked business_members, so fetchMemberships() correctly returned empty).';
