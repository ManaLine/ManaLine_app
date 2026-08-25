-- `ORDER BY 9 DESC, length(3::text)` on a UNION is not legal SQL: after a
-- UNION only result column NAMES may be ordered on, never expressions. The
-- function created cleanly and failed on its first call, exactly as a plpgsql
-- body always does -- it is not type-checked, or in this case even parsed for
-- this, until it runs.
--
-- The UNION moves into a FROM clause and the ordering happens outside it,
-- where expressions are allowed again.
CREATE OR REPLACE FUNCTION app.owner_search_loan_candidate(
  p_business_id uuid,
  p_query text
) RETURNS TABLE(customer_id uuid, person_id bigint, full_name character varying,
                father_husband_name character varying, mlid character varying,
                mobile_number character varying, village character varying,
                active_loans integer, is_customer boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $function$
DECLARE
  v_q      text := btrim(COALESCE(p_query, ''));
  v_strict boolean;
BEGIN
  IF NOT (app.is_owner(p_business_id) OR app.is_active_agent(p_business_id)) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  IF v_q = '' THEN RETURN; END IF;

  SELECT b.loans_require_existing_customer INTO v_strict
    FROM businesses b WHERE b.business_id = p_business_id;

  RETURN QUERY
  SELECT m.customer_id, m.person_id, m.full_name, m.father_husband_name,
         m.mlid, m.mobile_number, m.village, m.active_loans, m.is_customer
  FROM (
    -- This book's own customers, always.
    SELECT c.customer_id,
           p.person_id,
           p.full_name,
           p.father_husband_name,
           p.mlid,
           p.mobile_number,
           COALESCE(loc.village_town_name, ''::varchar) AS village,
           (SELECT count(*)::int FROM loans l
             WHERE l.customer_id = c.customer_id
               AND l.deleted_at IS NULL
               AND l.loan_status IN ('Active','Grace Period','Penalty')) AS active_loans,
           true AS is_customer
      FROM customers c
      JOIN business_members bm ON bm.membership_id = c.membership_id
      JOIN persons p ON p.person_id = bm.person_id
      LEFT JOIN LATERAL (
        SELECT l2.village_town_name
          FROM person_addresses pa
          JOIN locations l2 ON l2.location_id = pa.village_id
         WHERE pa.person_id = p.person_id AND pa.is_current = true
         LIMIT 1) loc ON true
     WHERE bm.business_id = p_business_id
       AND bm.membership_status <> 'Removed'
       AND (
         p.mlid = v_q
         OR p.mobile_number = v_q
         OR p.full_name ILIKE '%' || v_q || '%'
         OR COALESCE(loc.village_town_name, '') ILIKE '%' || v_q || '%'
       )

    UNION ALL

    -- Everyone else, when the Owner allows it. customer_id is NULL here and
    -- the screen must add them before a loan can be written -- which is
    -- exactly what is_customer = false is telling it.
    SELECT NULL::uuid,
           p.person_id,
           p.full_name,
           p.father_husband_name,
           p.mlid,
           p.mobile_number,
           COALESCE(loc.village_town_name, ''::varchar),
           0,
           false
      FROM persons p
      LEFT JOIN LATERAL (
        SELECT l2.village_town_name
          FROM person_addresses pa
          JOIN locations l2 ON l2.location_id = pa.village_id
         WHERE pa.person_id = p.person_id AND pa.is_current = true
         LIMIT 1) loc ON true
     WHERE NOT COALESCE(v_strict, false)
       AND (
         p.mlid = v_q
         OR p.mobile_number = v_q
         OR p.aadhaar_number = v_q
         OR p.full_name ILIKE '%' || v_q || '%'
       )
       -- Not already above. Without this an existing customer appears twice --
       -- once as themselves and once as a stranger to add.
       AND NOT EXISTS (
         SELECT 1 FROM customers c2
          JOIN business_members bm2 ON bm2.membership_id = c2.membership_id
         WHERE bm2.person_id = p.person_id
           AND bm2.business_id = p_business_id
           AND bm2.membership_status <> 'Removed')
  ) m
  -- Existing customers lead, then shortest name so an exact-ish match is near
  -- the top. Capped: this feeds a list a person reads, not a report.
  ORDER BY m.is_customer DESC, length(m.full_name), m.full_name
  LIMIT 40;
END;
$function$;
