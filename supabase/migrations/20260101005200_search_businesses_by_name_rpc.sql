-- MANA LINE — 0051_search_businesses_by_name_rpc.sql
-- Already applied directly to the live database via the Supabase connector.
-- This file is a record for your supabase/migrations/ folder — no action
-- needed against the live DB, just keep it in the folder for history.
--
-- Adds partial/typo-tolerant business search by name (or MLBI prefix) for
-- LR-012's "Request to Join a Business" flow — the existing
-- search_business_by_mlbi (0046) only supports an exact MLBI match, which
-- is unusable for someone who only knows the business by name. Returns
-- owner_name and business_address in addition to the public fields 0046
-- already exposed, so the client can show a full confirm card (MLBI, name,
-- owner, registered address) before the person sends a join request —
-- same "public-facing fields only" boundary as 0046, just a larger set of
-- fields that are still not financial/membership data.

CREATE OR REPLACE FUNCTION app.search_businesses_by_name(p_query VARCHAR)
RETURNS TABLE (
  business_id UUID,
  business_name VARCHAR,
  mlbi VARCHAR,
  logo_url TEXT,
  business_status business_status_enum,
  owner_name VARCHAR,
  business_address TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  -- Guard against 1-character queries scanning/returning too broadly —
  -- mirrors the client's own debounce/minLength, enforced server-side too
  -- since this RPC is reachable directly by any authenticated caller.
  IF p_query IS NULL OR length(trim(p_query)) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT b.business_id, b.business_name, b.mlbi, b.logo_url, b.business_status,
         p.full_name, b.business_address
  FROM businesses b
  LEFT JOIN persons p ON p.person_id = b.owner_person_id
  WHERE b.business_name ILIKE '%' || trim(p_query) || '%'
     OR b.mlbi ILIKE trim(p_query) || '%'
  ORDER BY b.business_name
  LIMIT 10;
END;
$$;

COMMENT ON FUNCTION app.search_businesses_by_name(VARCHAR) IS
  'Self-service partial-match business search by name or MLBI-prefix, for LR-012 Request-to-Join. Returns public fields only (name, MLBI, logo, status, owner name, registered address) — never financial or membership data. Companion to search_business_by_mlbi (0046, exact-match only).';

GRANT EXECUTE ON FUNCTION app.search_businesses_by_name(VARCHAR) TO authenticated;
