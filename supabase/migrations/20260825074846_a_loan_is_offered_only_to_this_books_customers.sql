-- Searching for a customer to lend to searches THIS book's customers.
--
-- New Loan step 1 used owner_search_person, which is a national identity
-- lookup: it searches every person in the database by name, and it is right
-- to, because an MLID is not owned by one business and adding a person who
-- already exists elsewhere must find them.
--
-- Lending is not that question. The screen says so itself -- "Only existing
-- customers may receive a remotely-issued loan" -- and yet the search happily
-- offered Kovvuri Sai Ramakrishna Reddy, who is an AGENT of a different
-- business and is not a customer of anywhere. He has no customers row, so his
-- customer_id was empty, and the wizard carried that empty string through six
-- steps until Postgres refused it: invalid input syntax for type uuid: "".
--
-- The Owner saw only "Something went wrong". They had picked a person the app
-- should never have shown them.
--
-- Returns customer_id, which is the thing a loan actually needs. A person
-- without one cannot appear here at all, so the wizard can no longer be
-- started against someone who cannot receive a loan.
--
-- Every match is returned rather than one. Two people really can share a name
-- -- this book has two -- and the screen must show them side by side with
-- their village and MLID so the Owner picks the right one. Refusing to list
-- them and asking for an MLID instead, which is what it did, asks the Owner
-- for the one thing they are least likely to know by heart.
--
-- SUPERSEDED the same day by owner_search_loan_candidate, which makes the
-- existing-customers-only rule the Owner's setting rather than the app's
-- assumption. Kept because the version is in the ledger and a rebuild has to
-- follow the same path this database took.
CREATE OR REPLACE FUNCTION app.owner_search_customer(
  p_business_id uuid,
  p_query text
) RETURNS TABLE(
  customer_id uuid,
  person_id bigint,
  full_name varchar,
  father_husband_name varchar,
  mlid varchar,
  mobile_number varchar,
  village varchar,
  active_loans integer
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_q text := btrim(COALESCE(p_query, ''));
BEGIN
  IF NOT (app.is_owner(p_business_id) OR app.is_active_agent(p_business_id)) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  IF v_q = '' THEN RETURN; END IF;

  RETURN QUERY
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
             AND l.loan_status IN ('Active','Grace Period','Penalty'))
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
   -- Shortest name first, so an exact-ish match leads. Capped: this feeds a
   -- list a person reads, not a report.
   ORDER BY length(p.full_name), p.full_name
   LIMIT 40;
END;
$$;

GRANT EXECUTE ON FUNCTION app.owner_search_customer(uuid, text)
  TO authenticated, service_role;
