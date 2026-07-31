-- GLOBAL BR-210 to BR-218 — Line Score. Nothing implemented it: zero
-- references anywhere in the codebase or the database.
--
--   Line Score = min(OnTime + Completion + PenaltyFreq + RecoveryBonus, 93)
--
-- BR-210: derived, NEVER stored - recalculated on every read. So this is
-- a STABLE function and there is deliberately no line_score column.
-- BR-211: no loan history at all = flat 35.
-- BR-216B: hard cap 93. No customer reaches 100 in V1.
--
-- "Most recent loan weighted 1.5x" (BR-212/BR-214) is implemented as a
-- weighted mean: the newest loan by effective_date carries weight 1.5,
-- every other loan weight 1.0.
CREATE OR REPLACE FUNCTION app.customer_line_score(p_customer_id uuid)
RETURNS TABLE(
  line_score numeric,
  on_time_component numeric,
  completion_component numeric,
  penalty_component numeric,
  recovery_bonus numeric,
  total_loans integer,
  clean_closures integer,
  penalty_loans integer,
  on_time_percent numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_business_id UUID;
  v_total INT := 0;
  v_newest UUID;
  v_on_time_pct NUMERIC := 0;
  v_on_time NUMERIC := 0;
  v_completion NUMERIC := 0;
  v_penalty NUMERIC := 20;
  v_recovery NUMERIC := 0;
  v_clean INT := 0;
  v_penalty_loans INT := 0;
  v_has_default BOOLEAN := FALSE;
  v_weight_sum NUMERIC := 0;
  v_weighted NUMERIC := 0;
  v_penalty_deduct NUMERIC := 0;
  r RECORD;
BEGIN
  SELECT bm.business_id INTO v_business_id
  FROM customers c JOIN business_members bm ON bm.membership_id = c.membership_id
  WHERE c.customer_id = p_customer_id;
  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Customer not found' USING ERRCODE = 'P0002';
  END IF;

  -- Line Score is business-private (Addendum v3 cross-business privacy
  -- principle): only this business's Owner or an active agent of it.
  IF NOT (app.is_owner(v_business_id) OR app.is_active_agent(v_business_id)) THEN
    RAISE EXCEPTION 'Not authorized for this customer' USING ERRCODE = '42501';
  END IF;

  SELECT COUNT(*) INTO v_total FROM loans l
  WHERE l.customer_id = p_customer_id AND l.loan_status <> 'Cancelled' AND l.loan_status <> 'Draft';

  IF v_total = 0 THEN
    -- BR-211 baseline.
    RETURN QUERY SELECT 35::numeric, 0::numeric, 0::numeric, 0::numeric, 0::numeric,
                        0, 0, 0, 0::numeric;
    RETURN;
  END IF;

  SELECT l.loan_id INTO v_newest FROM loans l
  WHERE l.customer_id = p_customer_id AND l.loan_status NOT IN ('Cancelled', 'Draft')
  ORDER BY l.effective_date DESC, l.created_at DESC LIMIT 1;

  FOR r IN
    SELECT l.loan_id, l.loan_status,
           (SELECT COUNT(*) FROM loan_schedule s WHERE s.loan_id = l.loan_id) AS installments,
           (SELECT COUNT(*) FROM loan_schedule s
             WHERE s.loan_id = l.loan_id AND s.status = 'Completed'
               AND s.completed_at IS NOT NULL
               AND s.completed_at::date <= s.due_date) AS on_time,
           EXISTS (SELECT 1 FROM penalty_entries pe WHERE pe.loan_id = l.loan_id) AS had_penalty,
           EXISTS (SELECT 1 FROM penalty_entries pe
                    WHERE pe.loan_id = l.loan_id AND pe.is_waived_or_reduced = TRUE) AS penalty_waived
    FROM loans l
    WHERE l.customer_id = p_customer_id AND l.loan_status NOT IN ('Cancelled', 'Draft')
  LOOP
    DECLARE
      v_w NUMERIC := CASE WHEN r.loan_id = v_newest THEN 1.5 ELSE 1.0 END;
    BEGIN
      -- BR-212 weighted on-time ratio.
      IF r.installments > 0 THEN
        v_weighted := v_weighted + (r.on_time::numeric / r.installments) * v_w;
        v_weight_sum := v_weight_sum + v_w;
      END IF;

      -- BR-213 completion.
      IF r.loan_status = 'Defaulted' THEN
        v_has_default := TRUE;
      ELSIF r.loan_status = 'Closed' AND NOT r.had_penalty THEN
        v_clean := v_clean + 1;
      END IF;

      -- BR-214 penalty frequency, most recent weighted 1.5x.
      IF r.had_penalty THEN
        v_penalty_loans := v_penalty_loans + 1;
        v_penalty_deduct := v_penalty_deduct + (5 * v_w);

        -- BR-215 recovery bonus: closed AND the penalty was actually paid,
        -- not waived or reduced.
        IF r.loan_status = 'Closed' AND NOT r.penalty_waived THEN
          v_recovery := v_recovery + 3;
        END IF;
      END IF;
    END;
  END LOOP;

  v_on_time_pct := CASE WHEN v_weight_sum > 0 THEN v_weighted / v_weight_sum ELSE 0 END;
  v_on_time := v_on_time_pct * 40;

  v_completion := CASE WHEN v_has_default THEN 0
                       ELSE LEAST(v_clean * 12.5, 25) END;

  v_penalty := GREATEST(20 - v_penalty_deduct, 0);

  RETURN QUERY SELECT
    LEAST(ROUND(v_on_time + v_completion + v_penalty + v_recovery), 93)::numeric,
    ROUND(v_on_time, 1),
    v_completion,
    v_penalty,
    v_recovery,
    v_total,
    v_clean,
    v_penalty_loans,
    ROUND(v_on_time_pct * 100, 1);
END;
$function$;

COMMENT ON FUNCTION app.customer_line_score(uuid) IS
  'GLOBAL BR-210 to BR-218. Derived, never stored. Hard cap 93 (BR-216B). Business-private per the Addendum v3 cross-business privacy principle.';

GRANT EXECUTE ON FUNCTION app.customer_line_score(uuid) TO authenticated;
