-- What a day's loans were made of, so the account sheet can show Karchu two
-- ways without either one lying.
--
-- THE OWNER'S RULE, from the paper sheet this app is modelled on (page 9 of
-- the 2024 design document) and settled on 2026-09-17: the loans row may be
-- drawn as the NET cash handed over, or as the FACE amount with the interest
-- and processing fee credited back beside it. Their own example: "only
-- karchu selected show 4900, if selected karchu+vaddi+processing fees -
-- 6000,1000,100."
--
-- Both forms net to the same cash, which is the whole point -- an Owner who
-- wants to see the income can, and the closing does not move. That holds
-- because loans.amount_given is a GENERATED column, repayment minus interest
-- minus processing fee. Checked on all 59 live loans before this was written:
-- zero rows where the three do not reconcile.
--
-- INTEREST IS WITHHELD, NOT COLLECTED AT ISSUE -- confirmed by the Owner the
-- same day. So neither form treats interest as fresh cash arriving. The face
-- form debits more and credits the difference straight back; the net form
-- never mentions it. CLAUDE.md's rule is intact either way: "BF is cash --
-- only money that actually moved."
--
-- NOT COLUMNS ON day_ledger, deliberately. This is a DECOMPOSITION of a
-- figure that table already holds (total_loan_distribution, the net), not a
-- new movement of money. Storing interest beside the cash figures would
-- invite the next reader to add it to something -- which is exactly the
-- double count CLAUDE.md pins a test against.
--
-- THE SAME PREDICATE app.recompute_day_ledger USES, copied rather than
-- rewritten: issue_business_date, deleted_at IS NULL, on loans. If this
-- selected a different set the sheet's two forms would net to two different
-- numbers, which is the one thing it must never do.
--
-- plpgsql, not sql, so the authorization can RAISE. As a WHERE clause it
-- would return zero rows to somebody unauthorized -- and a day that shows no
-- loan income looks exactly like a day that had none.

CREATE OR REPLACE FUNCTION app.day_loan_income(
  p_business_id uuid,
  p_from        date,
  p_to          date
) RETURNS TABLE(
  business_date date,
  face          numeric,
  interest      numeric,
  fee           numeric,
  net           numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to read this business''s loan income'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT l.issue_business_date,
         COALESCE(SUM(l.repayment_amount), 0),
         COALESCE(SUM(l.interest_amount), 0),
         COALESCE(SUM(l.processing_fee), 0),
         COALESCE(SUM(l.amount_given), 0)
    FROM loans l
   WHERE l.business_id = p_business_id
     AND l.issue_business_date BETWEEN p_from AND p_to
     AND l.deleted_at IS NULL
   GROUP BY l.issue_business_date;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.day_loan_income(uuid, date, date)
  TO anon, authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'day_loan_income';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'day_loan_income has % overloads', v_n;
  END IF;

  -- The invariant the two-form sheet rests on, asserted against the real
  -- books at the moment this ships rather than assumed from the column
  -- definition.
  SELECT count(*) INTO v_n
    FROM loans
   WHERE deleted_at IS NULL
     AND repayment_amount - interest_amount - processing_fee <> amount_given;
  IF v_n <> 0 THEN
    RAISE EXCEPTION
      '% loan(s) where repayment - interest - fee <> amount_given; the account '
      'sheet cannot draw Karchu two ways on these', v_n;
  END IF;
END $$;
