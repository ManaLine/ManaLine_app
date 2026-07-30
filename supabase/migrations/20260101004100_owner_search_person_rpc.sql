-- MANA LINE — 0041_owner_search_person_rpc.sql
--
-- app.owner_search_person — broader sibling of owner_search_person_by_mlid
-- (0035), for OW-004's "Add Customer" identity search (mlid/phone/
-- aadhaar/name), which was found doing a raw `persons` query and hitting
-- the exact same gap already fixed for Agent/Investor search:
-- persons_business_partner_select requires the target to already share a
-- business with the caller — impossible for a genuinely new candidate,
-- the whole point of this search.

CREATE OR REPLACE FUNCTION app.owner_search_person(
  p_mlid VARCHAR DEFAULT NULL,
  p_mobile_number VARCHAR DEFAULT NULL,
  p_aadhaar_number VARCHAR DEFAULT NULL,
  p_full_name VARCHAR DEFAULT NULL
)
RETURNS TABLE (
  person_id BIGINT,
  full_name VARCHAR,
  father_husband_name VARCHAR,
  mobile_number VARCHAR,
  mlid VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM businesses WHERE owner_person_id = app.current_person_id()
  ) THEN
    RAISE EXCEPTION 'Not authorized — Owner only' USING ERRCODE = '42501';
  END IF;

  IF p_mlid IS NOT NULL AND p_mlid != '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.mlid = p_mlid LIMIT 1;
  ELSIF p_aadhaar_number IS NOT NULL AND p_aadhaar_number != '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.aadhaar_number = p_aadhaar_number LIMIT 1;
  ELSIF p_mobile_number IS NOT NULL AND p_mobile_number != '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.mobile_number = p_mobile_number LIMIT 1;
  ELSIF p_full_name IS NOT NULL AND p_full_name != '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name, p.mobile_number, p.mlid
      FROM persons p WHERE p.full_name ILIKE '%' || p_full_name || '%' LIMIT 1;
  END IF;
END;
$$;

COMMENT ON FUNCTION app.owner_search_person(VARCHAR, VARCHAR, VARCHAR, VARCHAR) IS
  'Broader sibling of owner_search_person_by_mlid for OW-004''s multi-criteria identity search. Same gating: caller must be SOME business''s Owner, target need not already share a business.';

GRANT EXECUTE ON FUNCTION app.owner_search_person(VARCHAR, VARCHAR, VARCHAR, VARCHAR) TO authenticated;
