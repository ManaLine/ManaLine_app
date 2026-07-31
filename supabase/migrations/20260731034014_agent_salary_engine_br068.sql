-- CALC BR-068 (rewritten) — Payable Salary. Nothing computed salary
-- anywhere: no SQL, no Dart, and agent_salary_ledger sat unused.
--
--   Payable Salary = base + Other Owner-Approved Expenses
--                    - Advances
--                    - Shorts (ONLY if the Owner deducts this cycle)
--
-- BASE — CONFIRMED with the Owner 2026-07-31: the Owner chooses per agent
-- between a Fixed cycle amount and Daily Rate x Working Days. The spec
-- only described the daily form, but a fixed monthly wage is how many of
-- these agents are actually paid, so both are supported rather than one
-- being forced.
--
-- ADVANCES — CONFIRMED deducted. CALC BR-068's rewrite dropped them, but
-- it only ever called out Daily Allowance and Shorts as its two
-- corrections, and GLOBAL BR-047 ("Salary Advance: deducted from agent
-- salary account") was never superseded. salary_advances would otherwise
-- be a table nothing reads.
--
-- DAILY ALLOWANCE is deliberately absent. CALC BR-068 supersedes BR-046:
-- it is paid same-day in cash with zero relationship to salary, and is
-- tracked only for Owner visibility in OW-013.
--
-- EXCESS is deliberately absent too - never auto-credited to salary
-- (BR-070); it sits in the Excess Ledger for the Owner to place manually.
--
-- OTHER OWNER-APPROVED EXPENSES is a parameter, not a query: the expenses
-- table has no "approved for reimbursement" flag, and inventing one by
-- summing every expense an agent recorded would wrongly add business
-- spending to their wage. The Owner enters it at salary-run time, which
-- is what "Owner-Approved" means. FLAGGED for a future approval flag.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'salary_mode_enum') THEN
    CREATE TYPE salary_mode_enum AS ENUM ('Fixed', 'Daily Rate');
  END IF;
END $$;

ALTER TABLE public.agent_compensation_history
  ADD COLUMN IF NOT EXISTS salary_mode salary_mode_enum NOT NULL DEFAULT 'Fixed';
ALTER TABLE public.agent_compensation_history
  ADD COLUMN IF NOT EXISTS daily_rate numeric(14,0);

COMMENT ON COLUMN public.agent_compensation_history.salary_mode IS
  'CALC BR-068. Fixed = pay fixed_salary_amount per cycle. Daily Rate = daily_rate x working days counted from agent_access_days.';

CREATE OR REPLACE FUNCTION app.agent_payable_salary(
  p_agent_id uuid,
  p_period_start date,
  p_period_end date,
  p_deduct_shorts boolean DEFAULT false,
  p_other_approved_expenses numeric DEFAULT 0
)
RETURNS TABLE(
  salary_mode text,
  fixed_salary_amount numeric,
  daily_rate numeric,
  working_days integer,
  base_amount numeric,
  other_approved_expenses numeric,
  advances numeric,
  shorts_outstanding numeric,
  shorts_deducted numeric,
  payable_salary numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_membership_id UUID;
  v_business_id UUID;
  v_comp RECORD;
  v_days INT := 0;
  v_base DECIMAL(14,0) := 0;
  v_adv  DECIMAL(14,0) := 0;
  v_short DECIMAL(14,0) := 0;
  v_short_ded DECIMAL(14,0) := 0;
  v_other DECIMAL(14,0) := CEIL(COALESCE(p_other_approved_expenses, 0));
BEGIN
  SELECT a.membership_id INTO v_membership_id FROM agents a WHERE a.agent_id = p_agent_id;
  IF v_membership_id IS NULL THEN
    RAISE EXCEPTION 'Agent not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT bm.business_id INTO v_business_id FROM business_members bm WHERE bm.membership_id = v_membership_id;

  -- Salary is the Owner's business. An agent may read their own.
  IF NOT (app.is_owner(v_business_id)
          OR EXISTS (SELECT 1 FROM agents a WHERE a.agent_id = p_agent_id
                                              AND a.person_id = app.current_person_id())) THEN
    RAISE EXCEPTION 'Not authorized for this agent' USING ERRCODE = '42501';
  END IF;

  -- Compensation in force at the START of the cycle (BR-050/BR-057:
  -- changes are prospective, so a mid-cycle raise does not retro-apply).
  SELECT c.* INTO v_comp
  FROM agent_compensation_history c
  WHERE c.agent_id = p_agent_id
    AND c.effective_date <= p_period_start
  ORDER BY c.effective_date DESC
  LIMIT 1;

  IF v_comp IS NULL THEN
    RAISE EXCEPTION 'No compensation structure on record for this agent' USING ERRCODE = 'P0002';
  END IF;

  -- Working Days = days the agent was actually granted access. This is
  -- the only per-day record of an agent working that this schema keeps.
  SELECT COUNT(*) INTO v_days
  FROM agent_access_days d
  WHERE d.membership_id = v_membership_id
    AND d.business_date BETWEEN p_period_start AND p_period_end;

  IF v_comp.salary_mode = 'Daily Rate' THEN
    v_base := CEIL(COALESCE(v_comp.daily_rate, 0) * v_days);
  ELSE
    v_base := CEIL(COALESCE(v_comp.fixed_salary_amount, 0));
  END IF;

  SELECT COALESCE(SUM(sa.amount), 0) INTO v_adv
  FROM salary_advances sa
  WHERE sa.agent_id = p_agent_id
    AND sa.business_date BETWEEN p_period_start AND p_period_end;

  -- A Short is a negative difference on a settlement. It is ALWAYS
  -- recorded and always owed (BR-066); whether it comes off THIS cycle is
  -- the Owner's call each time (CALC BR-068 correction 2).
  SELECT COALESCE(SUM(ABS(s.difference)), 0) INTO v_short
  FROM account_settlements s
  JOIN account_periods ap ON ap.account_period_id = s.account_period_id
  WHERE s.agent_id = p_agent_id
    AND s.difference < 0
    AND ap.business_start_date::date BETWEEN p_period_start AND p_period_end;

  v_short_ded := CASE WHEN p_deduct_shorts THEN v_short ELSE 0 END;

  RETURN QUERY SELECT
    v_comp.salary_mode::text,
    v_comp.fixed_salary_amount,
    v_comp.daily_rate,
    v_days,
    v_base,
    v_other,
    v_adv,
    v_short,
    v_short_ded,
    v_base + v_other - v_adv - v_short_ded;
END;
$function$;

COMMENT ON FUNCTION app.agent_payable_salary(uuid, date, date, boolean, numeric) IS
  'CALC BR-068 rewritten. Daily Allowance excluded by design; Excess never credited; Shorts deducted only when the Owner chooses.';

GRANT EXECUTE ON FUNCTION app.agent_payable_salary(uuid, date, date, boolean, numeric) TO authenticated;
