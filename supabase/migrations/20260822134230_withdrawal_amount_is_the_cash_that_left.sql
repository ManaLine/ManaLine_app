-- Money an investor took back out, before the app existed.
--
-- Page 3 imports what investors put IN and there was no way to record what
-- came back OUT. The live withdrawal screen stamps CURRENT_DATE, so it cannot
-- record something that happened in February either. On sri satyanarayana that
-- left Rs 11,10,000 of withdrawals nowhere in the database and the Owner's
-- payable overstated by exactly that: the screen read Rs 36,02,332 against a
-- book saying Rs 24,85,582.
--
-- available_balance is principal + accrued interest, so a withdrawal has to
-- reduce investments.principal_amount to be seen at all. Recording the row
-- alone would change nothing the Owner can see.
--
-- AMOUNT IS THE CASH THAT LEFT. investment_withdrawals enforces
-- amount = principal_portion + interest_portion, so the interest column says
-- how much OF THAT CASH was interest rather than principal.
--
-- That reading matters here, because this book invites the other one. Its
-- withdrawal rows carry an interest figure beside the cash (Rs 6,000 against
-- Rs 4,00,000, Rs 1,750 against Rs 5,00,000) but the weekly accounts balance
-- on the cash alone -- that interest never left the till, it was settled
-- against what the investor had accrued. It is already carried by the weekly
-- sheet's Investor Out - Interest column, which is what
-- migration_profit_summary reads for profit. Entering it here as well would
-- count it twice AND take too little off principal: the book leaves Karri
-- Bhaskara Reddy Rs 1,00,000, which only holds if the whole Rs 9,00,000 came
-- off principal. So the interest column is for a withdrawal whose cash really
-- did include interest, and stays blank for a book like this one.
--
-- Idempotent on (investment, business_date, amount): re-uploading the sheet
-- skips what is already there rather than withdrawing it twice, and returns
-- the count so a repeat upload does not read as a failure.
--
-- This file supersedes 20260822133849, 20260822134031 and 20260822134123,
-- which are the same function on its way here. Each of them created cleanly
-- and failed on first call: a plpgsql body is not type-checked at CREATE, so
-- the wrong join, the invented enum value and the split-sum constraint all
-- surfaced only when it was invoked.
CREATE OR REPLACE FUNCTION app.import_migrated_withdrawals(
  p_business_id uuid,
  p_rows json,
  p_idempotency_key text DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_row       json;
  v_index     INT := 0;
  v_ok        INT := 0;
  v_skipped   INT := 0;
  v_errors    json[] := '{}';
  v_msg       TEXT;
  v_mlid      TEXT;
  v_date      DATE;
  v_started   DATE;
  v_amount    NUMERIC(14,0);
  v_interest  NUMERIC(14,0);
  v_principal NUMERIC(14,0);
  v_type      withdrawal_type_enum;
  v_inv       RECORD;
  v_count     INT;
  v_person    BIGINT := app.current_person_id();
  v_replay    json;
  v_result    json;
BEGIN
  v_replay := app.idempotent_replay(p_idempotency_key, 'import_migrated_withdrawals');
  IF v_replay IS NOT NULL THEN RETURN v_replay; END IF;

  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  PERFORM app.migration_assert_open(p_business_id);

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;
    BEGIN
      v_mlid     := btrim(v_row ->> 'mlid');
      v_date     := (v_row ->> 'business_date')::DATE;
      v_amount   := CEIL((v_row ->> 'amount')::NUMERIC);
      v_interest := CEIL(COALESCE((v_row ->> 'interest_portion')::NUMERIC, 0));
      v_started  := NULLIF(btrim(COALESCE(v_row ->> 'invested_date', '')), '')::DATE;

      IF v_amount <= 0 THEN
        RAISE EXCEPTION 'Withdrawal amount must be greater than zero.';
      END IF;
      IF v_interest < 0 OR v_interest > v_amount THEN
        RAISE EXCEPTION 'The interest part (%) cannot be more than the amount withdrawn (%).',
          v_interest, v_amount;
      END IF;
      v_principal := v_amount - v_interest;

      SELECT COUNT(*) INTO v_count
        FROM investments i
        JOIN investors iv ON iv.investor_id = i.investor_id
        JOIN business_members bm ON bm.membership_id = iv.membership_id
        JOIN persons p ON p.person_id = bm.person_id
       WHERE i.business_id = p_business_id AND i.deleted_at IS NULL
         AND p.mlid = v_mlid
         AND (v_started IS NULL OR i.effective_date = v_started);

      IF v_count = 0 THEN
        RAISE EXCEPTION 'No investment found for MLID %.', v_mlid;
      ELSIF v_count > 1 THEN
        -- Taking money off the wrong investment is invisible while the totals
        -- still add up, so it is refused rather than guessed.
        RAISE EXCEPTION 'MLID % holds % investments. Fill the Invested Date column so this row can say which one.',
          v_mlid, v_count;
      END IF;

      SELECT i.* INTO v_inv
        FROM investments i
        JOIN investors iv ON iv.investor_id = i.investor_id
        JOIN business_members bm ON bm.membership_id = iv.membership_id
        JOIN persons p ON p.person_id = bm.person_id
       WHERE i.business_id = p_business_id AND i.deleted_at IS NULL
         AND p.mlid = v_mlid
         AND (v_started IS NULL OR i.effective_date = v_started);

      IF v_date < v_inv.effective_date THEN
        RAISE EXCEPTION 'Withdrawn on % but the investment starts on %.',
          v_date, v_inv.effective_date;
      END IF;

      IF EXISTS (
        SELECT 1 FROM investment_withdrawals w
         WHERE w.investment_id = v_inv.investment_id
           AND w.business_date = v_date
           AND w.amount = v_amount
           AND w.deleted_at IS NULL
      ) THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;

      IF v_principal > v_inv.principal_amount THEN
        RAISE EXCEPTION 'Taking % off principal leaves the investment short: only % remains.',
          v_principal, v_inv.principal_amount;
      END IF;

      v_type := CASE
                  WHEN v_principal = 0 THEN 'Interest Only'
                  WHEN v_principal = v_inv.principal_amount THEN 'Principal Full'
                  WHEN v_interest > 0 THEN 'Principal + Interest'
                  ELSE 'Principal Partial'
                END;

      INSERT INTO investment_withdrawals (
        investment_id, withdrawal_type, amount, principal_portion,
        interest_portion, business_date, approved_by_person_id
      ) VALUES (
        v_inv.investment_id, v_type, v_amount, v_principal,
        v_interest, v_date, v_person
      );

      -- The whole point: available_balance reads principal_amount.
      UPDATE investments
         SET principal_amount = principal_amount - v_principal,
             status = CASE WHEN principal_amount - v_principal <= 0
                           THEN 'Closed'::investment_status_enum
                           ELSE status END
       WHERE investment_id = v_inv.investment_id;

      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_errors := v_errors || json_build_object(
        'row', v_index, 'mlid', v_row ->> 'mlid', 'error', v_msg);
    END;
  END LOOP;

  IF array_length(v_errors, 1) > 0 THEN
    RAISE EXCEPTION 'IMPORT_REJECTED %', json_build_object(
      'imported', 0, 'failed', array_length(v_errors, 1),
      'total', v_index, 'errors', array_to_json(v_errors))::text
    USING ERRCODE = '23514';
  END IF;

  v_result := json_build_object(
    'imported', v_ok, 'skipped', v_skipped, 'failed', 0, 'total', v_index);
  PERFORM app.idempotent_store(
    p_idempotency_key, 'import_migrated_withdrawals', v_result, p_business_id);
  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION app.import_migrated_withdrawals(uuid, json, text)
  TO authenticated, service_role;
