-- How much of a customer's profile is filled in, as a fraction, so the ring
-- around their photo can close as it fills.
--
-- The Owner: "can we make the active ring around photo showing in collection
-- to indicate this by showing circle completely closes when profile is 100%
-- complete." The ring is this app's signature motif and its COLOUR is already
-- spoken for -- identity verification on twenty-two screens, membership status
-- on the roster, with a comment in mana_text.dart warning against a third
-- meaning for the same circle. Completeness is therefore a SWEEP, not a
-- colour: how far round the arc goes, independent of what colour it is.
--
-- FIVE THINGS, and the list is the argument. A customer's record is complete
-- when the book can identify them, reach them, and prove who they are:
--
--   permanent ID   an MLPI rather than an MLTI -- an Aadhaar has been seen
--   mobile number  they can be reached
--   date of birth
--   live photo     a face, captured in person
--   village        where to go
--
-- Measured on the live book before shipping it: of 58 customers on sri
-- satyanarayana business, 57 sit at 2 of 5 and one at 4 of 5. Nobody is
-- complete. So this is not a metric that will read full everywhere and mean
-- nothing -- it starts at two fifths and the ring has somewhere to travel as
-- temporary IDs are converted.
--
-- ONE ROW PER CUSTOMER OF A BUSINESS, computed server-side, because the
-- alternative is five more columns on v_collection_due -- a view eight screens
-- read -- to answer a question one of them asks.
--
-- mlid_type rather than aadhaar_hash: the two agree, and the permanent ID is
-- the thing an Owner and an agent actually see on the row.

CREATE OR REPLACE FUNCTION app.profile_completeness(
  p_business_id uuid
) RETURNS TABLE(
  customer_id uuid,
  person_id   bigint,
  filled      integer,
  total       integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to read this business''s customers'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT c.customer_id,
         p.person_id,
         (
           (p.mlid_type = 'MLPI')::int
         + (COALESCE(p.mobile_number, '') <> '')::int
         + (p.dob IS NOT NULL)::int
         + (p.live_photo_url IS NOT NULL)::int
         + EXISTS (SELECT 1 FROM person_addresses pa
                    WHERE pa.person_id = p.person_id
                      AND pa.is_current)::int
         )::integer,
         5
    FROM customers c
    JOIN business_members bm ON bm.membership_id = c.membership_id
    JOIN persons p ON p.person_id = c.person_id
   WHERE bm.business_id = p_business_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.profile_completeness(uuid) TO anon, authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'profile_completeness';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'profile_completeness has % overloads', v_n;
  END IF;
END $$;
