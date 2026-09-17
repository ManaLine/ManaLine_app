-- Deleting an entry inside a closed day or an approved settlement rewrote it.
--
-- Raised from a handset as a question rather than a bug report: "if a user's
-- collection from 6 months back is deleted now then the complete account from
-- 6 months need to change?" It did. app.soft_delete_record checked the delete
-- PERMISSION and nothing else -- not the day's status, not the account period
-- -- and then called app.recompute_ledger_chain for the whole business, which
-- rewrites every closing balance from that day forward.
--
-- Nothing downstream protected anything either. Of recompute_ledger_chain,
-- recompute_day_ledger, recompute_day_ledger_onward and recompute_business_bf,
-- only recompute_day_ledger guards anything at all, and only the migrated
-- span. A day_ledger row with status 'Closed' was recomputed exactly like an
-- open one, while its day_closures row kept the counted cash and the
-- signed-off zero difference it was closed on -- so the two would disagree and
-- nothing would say so.
--
-- WHERE IT STOOD WHEN THIS WAS WRITTEN, because the two halves differ:
--   * Day closures are LATENT. All 82 day_ledger rows are 'Open' and
--     day_closures is empty -- nobody has closed a day yet, so nothing has
--     been corrupted. There is also no reopen path: close_business_day reads
--     reopened_at, and nothing in the schema ever sets it.
--   * Settlements are LIVE. One account_settlements row is already 'Approved',
--     covering 18-29 Aug 2026, and that span holds real collections.
--     Deleting one would have silently rewritten what an agent settled and an
--     Owner signed.
--
-- THE OWNER CHOSE REFUSAL over reversing into the current day: a signed-off
-- figure simply may not move. That also matches what this schema already does
-- elsewhere -- app.refresh_day_ledger refuses with "This business day is
-- closed. Reopen it before recalculating."
--
-- THE DEAD END IS REAL AND IS NOT FIXED HERE. With no reopen for a business
-- day, a closed day becomes genuinely uneditable rather than
-- editable-after-a-deliberate-step. That is a feature on top of a fix and is
-- named rather than quietly built. It costs nothing today, since no day has
-- ever been closed; a settlement CAN be returned (app.return_settlement), so
-- that half already has its escape.
--
-- RESTORE IS GUARDED TOO, in the migration that follows. Restoring a deleted
-- record moves the same money in the other direction and calls the same
-- recompute, so guarding only the delete would leave the identical hole facing
-- the other way.

CREATE OR REPLACE FUNCTION app.deletable_business_date(
  p_entity    text,
  p_record_id uuid
) RETURNS date
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_date date;
BEGIN
  -- The day each kind of record BELONGS to, which is the day whose figures it
  -- moves -- not when somebody pressed delete.
  CASE p_entity
    WHEN 'collection' THEN
      SELECT business_date INTO v_date FROM collections WHERE collection_id = p_record_id;
    WHEN 'loan' THEN
      SELECT issue_business_date INTO v_date FROM loans WHERE loan_id = p_record_id;
    WHEN 'expense' THEN
      SELECT business_date INTO v_date FROM expenses WHERE expense_id = p_record_id;
    WHEN 'cheti_payment' THEN
      SELECT business_date INTO v_date FROM cheti_payments WHERE cheti_payment_id = p_record_id;
    WHEN 'cheti' THEN
      SELECT availed_date INTO v_date FROM chetis WHERE cheti_id = p_record_id;
    WHEN 'investment' THEN
      SELECT effective_date INTO v_date FROM investments WHERE investment_id = p_record_id;
    WHEN 'investment_withdrawal' THEN
      SELECT business_date INTO v_date FROM investment_withdrawals WHERE withdrawal_id = p_record_id;
    WHEN 'settlement_adjustment' THEN
      SELECT business_date INTO v_date FROM settlement_adjustments WHERE adjustment_id = p_record_id;
    WHEN 'cash_transfer' THEN
      SELECT business_date INTO v_date FROM cash_transfers WHERE transfer_id = p_record_id;
    ELSE
      -- customer_remark and customer_document carry no money and land on no
      -- day. NULL means "nothing to lock", not "unknown".
      v_date := NULL;
  END CASE;
  RETURN v_date;
END;
$function$;

CREATE OR REPLACE FUNCTION app.locked_period_reason(
  p_business_id uuid,
  p_date        date
) RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_agent text; v_from date; v_to date;
BEGIN
  IF p_date IS NULL THEN
    RETURN NULL;
  END IF;

  IF EXISTS (SELECT 1 FROM day_ledger d
              WHERE d.business_id = p_business_id
                AND d.business_date = p_date
                AND d.status = 'Closed') THEN
    RETURN format('%s has been closed. Reopen the day before changing it.',
                  to_char(p_date, 'DD Mon YYYY'));
  END IF;

  -- A period an agent has handed in and an Owner may already have signed.
  -- 'Running' and 'Overdue' are still open and are not locked.
  SELECT p.full_name, ap.business_start_date,
         COALESCE(ap.actual_end_date, ap.planned_business_end_date)
    INTO v_agent, v_from, v_to
    FROM account_periods ap
    JOIN business_members bm ON bm.membership_id = ap.agent_membership_id
    JOIN persons p ON p.person_id = bm.person_id
   WHERE ap.business_id = p_business_id
     AND ap.status IN ('Submitted', 'Approved', 'Locked')
     AND p_date >= ap.business_start_date
     AND p_date <= COALESCE(ap.actual_end_date, ap.planned_business_end_date,
                            p_date)
   LIMIT 1;

  IF v_agent IS NOT NULL THEN
    RETURN format(
      '%s is part of a settled account (%s, %s to %s). Return that settlement first.',
      to_char(p_date, 'DD Mon YYYY'), v_agent,
      to_char(v_from, 'DD Mon'), to_char(v_to, 'DD Mon'));
  END IF;

  RETURN NULL;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.deletable_business_date(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION app.locked_period_reason(uuid, date) TO anon, authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  FOR v_n IN
    SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='app'
       AND p.proname IN ('deletable_business_date','locked_period_reason')
     GROUP BY p.proname
  LOOP
    IF v_n <> 1 THEN
      RAISE EXCEPTION 'a new guard function gained an overload (%)', v_n;
    END IF;
  END LOOP;
END $$;
