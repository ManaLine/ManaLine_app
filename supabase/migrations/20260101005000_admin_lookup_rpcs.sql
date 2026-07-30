-- MANA LINE — 0050_admin_lookup_rpcs.sql
--
-- Fixes the confirmed real bug in the Admin Panel: the delete fields
-- asked for raw person_id (BIGINT) / business_id (UUID), which nobody
-- actually knows or has memorized — every other part of this app
-- searches by MLID/MLBI, the human-facing codes. These lookup RPCs let
-- the Admin Panel search by MLID/MLBI (or loan/collection UUID, which
-- have no better human code), show full details, and only THEN enable
-- deletion — confirming the right thing before it's gone forever.

CREATE OR REPLACE FUNCTION app.admin_lookup_person(p_mlid VARCHAR)
RETURNS TABLE (
  person_id BIGINT, full_name VARCHAR, mlid VARCHAR, mobile_number VARCHAR,
  aadhaar_number VARCHAR, gender_digit CHAR(1), verification_ring VARCHAR,
  business_count BIGINT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT p.person_id, p.full_name, p.mlid, p.mobile_number, p.aadhaar_number,
         p.gender_digit, p.verification_ring::VARCHAR,
         (SELECT count(*) FROM business_members bm WHERE bm.person_id = p.person_id)
  FROM persons p WHERE p.mlid = p_mlid LIMIT 1;
END;
$$;

COMMENT ON FUNCTION app.admin_lookup_person(VARCHAR) IS
  'Admin Panel search-before-delete — full person details by MLID, Platform Admin only.';

GRANT EXECUTE ON FUNCTION app.admin_lookup_person(VARCHAR) TO authenticated;

CREATE OR REPLACE FUNCTION app.admin_lookup_business(p_mlbi VARCHAR)
RETURNS TABLE (
  business_id UUID, business_name VARCHAR, mlbi VARCHAR, business_status business_status_enum,
  owner_name VARCHAR, owner_mlid VARCHAR, agent_count BIGINT, customer_count BIGINT, investor_count BIGINT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT b.business_id, b.business_name, b.mlbi, b.business_status,
         p.full_name, p.mlid,
         (SELECT count(*) FROM business_members bm WHERE bm.business_id = b.business_id AND bm.role = 'Agent'),
         (SELECT count(*) FROM business_members bm WHERE bm.business_id = b.business_id AND bm.role = 'Customer'),
         (SELECT count(*) FROM business_members bm WHERE bm.business_id = b.business_id AND bm.role = 'Investor')
  FROM businesses b
  JOIN persons p ON p.person_id = b.owner_person_id
  WHERE b.mlbi = p_mlbi LIMIT 1;
END;
$$;

COMMENT ON FUNCTION app.admin_lookup_business(VARCHAR) IS
  'Admin Panel search-before-delete — full business details by MLBI, Platform Admin only.';

GRANT EXECUTE ON FUNCTION app.admin_lookup_business(VARCHAR) TO authenticated;

CREATE OR REPLACE FUNCTION app.admin_lookup_loan(p_loan_id UUID)
RETURNS TABLE (
  loan_id UUID, loan_number VARCHAR, customer_name VARCHAR, customer_mlid VARCHAR,
  amount_given DECIMAL, remaining_balance DECIMAL, loan_status VARCHAR
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT l.loan_id, l.loan_number, p.full_name, p.mlid, l.amount_given, l.remaining_balance, l.loan_status::VARCHAR
  FROM loans l
  JOIN customers c ON c.customer_id = l.customer_id
  JOIN persons p ON p.person_id = c.person_id
  WHERE l.loan_id = p_loan_id LIMIT 1;
END;
$$;

COMMENT ON FUNCTION app.admin_lookup_loan(UUID) IS
  'Admin Panel search-before-delete — full loan details, Platform Admin only.';

GRANT EXECUTE ON FUNCTION app.admin_lookup_loan(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION app.admin_lookup_collection(p_collection_id UUID)
RETURNS TABLE (
  collection_id UUID, collected_amount DECIMAL, entry_timestamp TIMESTAMP,
  customer_name VARCHAR, customer_mlid VARCHAR, loan_number VARCHAR
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT co.collection_id, co.collected_amount, co.entry_timestamp, p.full_name, p.mlid, l.loan_number
  FROM collections co
  JOIN customers c ON c.customer_id = co.customer_id
  JOIN persons p ON p.person_id = c.person_id
  LEFT JOIN loans l ON l.loan_id = co.loan_id
  WHERE co.collection_id = p_collection_id LIMIT 1;
END;
$$;

COMMENT ON FUNCTION app.admin_lookup_collection(UUID) IS
  'Admin Panel search-before-delete — full collection details, Platform Admin only.';

GRANT EXECUTE ON FUNCTION app.admin_lookup_collection(UUID) TO authenticated;
