-- Who may be lent to is the Owner's rule, not the app's.
--
-- The customer search built earlier today could only ever return customers of
-- this book. That fixed a real defect -- the wizard was offering people from
-- another business, and a loan against one of them failed six steps later --
-- but it also decided something that is not the app's to decide: that a loan
-- may only go to somebody already on the books.
--
-- Most lending here does not work that way. A new borrower walks up, and the
-- loan and the customer record are created in the same conversation. Refusing
-- until they have been added through a separate screen turns one act into two
-- and sends the Owner away mid-loan.
--
-- So it becomes a per-business setting, and the permissive reading is the
-- default: anyone found by the global identity search may be lent to, and the
-- wizard adds them to this book as it goes. An Owner who wants the stricter
-- rule -- some do, for books where every borrower is vetted first -- turns it
-- on.
--
-- DEFAULT false is deliberate: it is the behaviour every existing book already
-- has, so no live business changes the day this ships.
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS loans_require_existing_customer boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN businesses.loans_require_existing_customer IS
  'When true, a loan may only be issued to somebody already a customer of '
  'this business. Default false: the wizard finds anyone by global identity '
  'search and adds them to the book as part of issuing the loan.';

-- The search the loan wizard uses.
--
-- Replaces owner_search_customer, which had no way to express "and also these
-- people who are not customers here yet". Same columns plus is_customer, so
-- the screen can tell a name it may simply select from one it must add first.
--
-- The policy is read from the business, NOT taken as a parameter. A client
-- that forgot to pass the flag would otherwise silently get the permissive
-- behaviour, which is the wrong way round for a rule the Owner set.
--
-- NOTE: the body below carries an `ORDER BY 9 DESC, length(3::text)` on a
-- UNION, which is not legal SQL -- the next migration corrects it. Kept as it
-- was applied, because a plpgsql body is not checked until it runs: this
-- created cleanly and failed on its first call, which is the trap CLAUDE.md
-- warns about, and rewriting history here would hide that it happened.
DROP FUNCTION IF EXISTS app.owner_search_customer(uuid, text);

CREATE OR REPLACE FUNCTION app.owner_search_loan_candidate(
  p_business_id uuid,
  p_query text
) RETURNS TABLE(customer_id uuid, person_id bigint, full_name character varying,
                father_husband_name character varying, mlid character varying,
                mobile_number character varying, village character varying,
                active_loans integer, is_customer boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $function$
DECLARE
  v_q          text := btrim(COALESCE(p_query, ''));
  v_strict     boolean;
BEGIN
  IF NOT (app.is_owner(p_business_id) OR app.is_active_agent(p_business_id)) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  IF v_q = '' THEN RETURN; END IF;

  SELECT b.loans_require_existing_customer INTO v_strict
    FROM businesses b WHERE b.business_id = p_business_id;

  RETURN QUERY
  -- This book's own customers, always, and always first.
  SELECT c.customer_id,
         p.person_id,
         p.full_name,
         p.father_husband_name,
         p.mlid,
         p.mobile_number,
         COALESCE(loc.village_town_name, ''::varchar),
         (SELECT count(*)::int FROM loans l
           WHERE l.customer_id = c.customer_id
             AND l.deleted_at IS NULL
             AND l.loan_status IN ('Active','Grace Period','Penalty')),
         true
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

  -- Everyone else, when the Owner allows it. customer_id is NULL here and the
  -- screen must add them before a loan can be written -- which is exactly what
  -- is_customer = false is telling it.
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
     -- Not already above. Without this, an existing customer appears twice --
     -- once as themselves and once as a stranger to add.
     AND NOT EXISTS (
       SELECT 1 FROM customers c2
        JOIN business_members bm2 ON bm2.membership_id = c2.membership_id
       WHERE bm2.person_id = p.person_id
         AND bm2.business_id = p_business_id
         AND bm2.membership_status <> 'Removed')

  -- Existing customers lead, then shortest name so an exact-ish match is near
  -- the top. Capped: this feeds a list a person reads, not a report.
  ORDER BY 9 DESC, length(3::text), 3
   LIMIT 40;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.owner_search_loan_candidate(uuid, text)
  TO authenticated, service_role;
