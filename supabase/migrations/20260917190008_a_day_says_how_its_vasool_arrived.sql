-- How a day's collections arrived, per mode, so the account sheet can show
-- the © / ℗ split the design document's slip carries.
--
-- The Owner approved this on 2026-09-17 ("1. approved") against page 4, where
-- every payment on the Credits Received Slip is written with its mode and the
-- day is totalled by mode underneath.
--
-- A DECOMPOSITION OF VASOOL, NOT A NEW FIGURE -- the same shape, and the same
-- reasoning, as app.day_loan_income two migrations back. The modes sum to the
-- day's collections; they are not money in addition to it. Nothing may add
-- these to total_collections, which is why they live in their own function
-- rather than as columns beside the cash figures on day_ledger.
--
-- THE SUM IS ASSERTED BELOW against the live book rather than assumed from
-- the schema. If splits and collections ever disagree, a sheet showing Cash
-- and Online under Vasool would display a Vasool that does not add up -- and
-- somebody would believe the smaller number.
--
-- collections carries no business_id; it reaches the book through loan_id,
-- the same path app.active_account_dates takes. deleted_at IS NULL on the
-- collection, matching app.recompute_day_ledger: a reversed payment is not a
-- payment, and its mode is not a mode the day received money in.
--
-- plpgsql so the authorization can RAISE rather than returning zero rows. A
-- day showing no modes and a day the reader may not see look identical.

CREATE OR REPLACE FUNCTION app.day_payment_modes(
  p_business_id uuid,
  p_from        date,
  p_to          date
) RETURNS TABLE(
  business_date date,
  payment_mode  text,
  amount        numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to read this business''s payment modes'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT c.business_date,
         s.payment_mode::text,
         COALESCE(SUM(s.amount), 0)
    FROM collection_payment_splits s
    JOIN collections c ON c.collection_id = s.collection_id
   WHERE c.deleted_at IS NULL
     AND c.business_date BETWEEN p_from AND p_to
     AND c.loan_id IN (SELECT l.loan_id FROM loans l
                        WHERE l.business_id = p_business_id)
   GROUP BY c.business_date, s.payment_mode
   ORDER BY c.business_date DESC, s.payment_mode::text;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.day_payment_modes(uuid, date, date)
  TO anon, authenticated;

DO $$
DECLARE v_n INT; v_bad INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'day_payment_modes';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'day_payment_modes has % overloads', v_n;
  END IF;

  -- Every live collection's splits must add up to what was collected.
  SELECT count(*) INTO v_bad
    FROM collections c
    LEFT JOIN (SELECT collection_id, SUM(amount) tot
                 FROM collection_payment_splits GROUP BY 1) s
      ON s.collection_id = c.collection_id
   WHERE c.deleted_at IS NULL
     AND COALESCE(s.tot, 0) <> c.collected_amount;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION
      '% collection(s) whose payment splits do not sum to collected_amount; '
      'a mode breakdown under Vasool would not add up', v_bad;
  END IF;
END $$;
