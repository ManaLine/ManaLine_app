-- Global search that ANDs its parameters instead of picking one.
--
-- app.owner_search_person is an ELSIF chain: pass an MLID and a name and the
-- name is silently ignored; pass a village and a name and the village is
-- ignored, because it was not even a parameter. That is only useful when you
-- already know the one field that identifies someone - which is exactly the
-- case where you did not need a search.
--
-- Here every supplied filter narrows the result. Village and PIN reach the
-- person through their CURRENT address, which is what makes "the Lakshmi in
-- Renigunta" a query at all.
--
-- Deliberately NOT scoped to one business: this is the global directory the
-- Owner uses to find someone before they belong anywhere. It returns identity
-- and address only - no balances, no business list - so it cannot become a
-- way to read another business's book.
CREATE OR REPLACE FUNCTION app.global_person_search(
  p_query text DEFAULT NULL,
  p_mlid text DEFAULT NULL,
  p_mobile_number text DEFAULT NULL,
  p_aadhaar_number text DEFAULT NULL,
  p_full_name text DEFAULT NULL,
  p_pin_code text DEFAULT NULL,
  p_village text DEFAULT NULL,
  p_limit integer DEFAULT 25
) RETURNS TABLE(
  person_id bigint,
  full_name character varying,
  father_husband_name character varying,
  mobile_number character varying,
  mlid character varying,
  village character varying,
  pin_code character varying,
  district character varying,
  match_rank integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_query    text := NULLIF(btrim(COALESCE(p_query, '')), '');
  v_mlid     text := NULLIF(btrim(COALESCE(p_mlid, '')), '');
  v_mobile   text := NULLIF(btrim(COALESCE(p_mobile_number, '')), '');
  v_aadhaar  text := NULLIF(btrim(COALESCE(p_aadhaar_number, '')), '');
  v_name     text := NULLIF(btrim(COALESCE(p_full_name, '')), '');
  v_pin      text := NULLIF(regexp_replace(COALESCE(p_pin_code, ''), '[^0-9]', '', 'g'), '');
  v_village  text := NULLIF(btrim(COALESCE(p_village, '')), '');
  v_hash     text;
  v_limit    int  := LEAST(GREATEST(COALESCE(p_limit, 25), 1), 100);
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM businesses b WHERE b.owner_person_id = app.current_person_id()
  ) AND NOT EXISTS (
    SELECT 1 FROM business_members bm
     WHERE bm.person_id = app.current_person_id()
       AND bm.role IN ('Owner', 'Agent')
       AND bm.membership_status = 'Active'
  ) THEN
    RAISE EXCEPTION 'Not authorized to search people' USING ERRCODE = '42501';
  END IF;

  -- One free-text box can carry any of these. Digits that look like a phone
  -- or a PIN are treated as such; anything starting MLPI/MLTI is an MLID;
  -- everything else is a name. Explicit parameters always win over the guess.
  IF v_query IS NOT NULL THEN
    IF upper(v_query) LIKE 'ML%' AND v_mlid IS NULL THEN
      v_mlid := upper(v_query);
    ELSIF v_query ~ '^[0-9]{10}$' AND v_mobile IS NULL THEN
      v_mobile := v_query;
    ELSIF v_query ~ '^[0-9]{6}$' AND v_pin IS NULL THEN
      v_pin := v_query;
    ELSIF v_query ~ '^[0-9]{12}$' AND v_aadhaar IS NULL THEN
      v_aadhaar := v_query;
    ELSIF v_name IS NULL THEN
      v_name := v_query;
    END IF;
  END IF;

  IF v_mlid IS NULL AND v_mobile IS NULL AND v_aadhaar IS NULL
     AND v_name IS NULL AND v_pin IS NULL AND v_village IS NULL THEN
    RETURN;  -- nothing asked, nothing answered
  END IF;

  v_hash := CASE WHEN v_aadhaar IS NULL THEN NULL ELSE app.aadhaar_hash(v_aadhaar) END;

  RETURN QUERY
  SELECT p.person_id,
         p.full_name,
         p.father_husband_name,
         p.mobile_number,
         p.mlid,
         l.village_town_name,
         a.pin_code,
         a.district,
         -- An identifier match is exact and comes first; then a name that
         -- starts with what was typed; then one that merely contains it.
         (CASE
            WHEN v_mlid IS NOT NULL AND p.mlid = v_mlid THEN 0
            WHEN v_hash IS NOT NULL AND p.aadhaar_hash = v_hash THEN 0
            WHEN v_mobile IS NOT NULL AND p.mobile_number = v_mobile THEN 0
            WHEN v_name IS NOT NULL AND p.full_name ILIKE v_name || '%' THEN 1
            ELSE 2
          END)::int AS match_rank
    FROM persons p
    LEFT JOIN person_addresses a
           ON a.person_id = p.person_id AND a.is_current
    LEFT JOIN locations l
           ON l.location_id = a.village_id
   WHERE p.account_status <> 'Deleted'
     -- Every supplied filter narrows. This is the whole point.
     AND (v_mlid    IS NULL OR p.mlid = v_mlid)
     AND (v_hash    IS NULL OR p.aadhaar_hash = v_hash)
     AND (v_mobile  IS NULL OR p.mobile_number = v_mobile)
     AND (v_name    IS NULL OR p.full_name ILIKE '%' || v_name || '%')
     AND (v_pin     IS NULL OR a.pin_code = v_pin)
     AND (v_village IS NULL OR l.village_town_name ILIKE '%' || v_village || '%')
   ORDER BY match_rank, length(p.full_name), p.full_name
   LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION app.global_person_search(text, text, text, text, text, text, text, integer)
  TO authenticated, service_role;
