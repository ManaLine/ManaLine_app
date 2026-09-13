-- A short declared at migration has to reach the one place shorts are counted.
--
-- Recorded and invisible is not recorded. app.agent_payable_salary is the only
-- function in this schema that knows what a short is, so an opening short that
-- does not appear here is a number sitting in a column that nothing reads.
--
-- DROP then CREATE, not CREATE OR REPLACE: the RETURNS TABLE list gains a
-- column. Postgres treats a changed return type as a different function and
-- PostgREST then answers HTTP 300 (PGRST203) because it cannot choose between
-- the two. The parameter list is unchanged, so the single Dart caller
-- (owner_api_service.fetchPayableSalary) keeps working -- it reads named
-- fields and simply gains one.
--
-- Two deliberate choices about HOW it is counted:
--
-- 1. It is reported on its own line as well as inside shorts_outstanding. An
--    Owner looking at a deduction is entitled to know which part of it comes
--    from this pay cycle's settlements and which part is a debt carried in
--    from before the app existed. Rolling them into one figure is how a
--    deduction becomes an argument with the agent.
--
-- 2. It keeps appearing every cycle until app.clear_agent_opening_short is
--    called. That is not a bug to be smoothed over: the money is owed until
--    somebody records that it came back. A per-cycle settlement short belongs
--    to its cycle and falls out of the window on its own; an opening short
--    belongs to no cycle and must be closed by hand.
DROP FUNCTION IF EXISTS app.agent_payable_salary(UUID, DATE, DATE, BOOLEAN, NUMERIC);

CREATE FUNCTION app.agent_payable_salary(
    p_agent_id UUID,
    p_period_start DATE,
    p_period_end DATE,
    p_deduct_shorts BOOLEAN DEFAULT false,
    p_other_approved_expenses NUMERIC DEFAULT 0
) RETURNS TABLE(
    salary_mode TEXT,
    fixed_salary_amount NUMERIC,
    daily_rate NUMERIC,
    working_days INTEGER,
    base_amount NUMERIC,
    other_approved_expenses NUMERIC,
    advances NUMERIC,
    shorts_outstanding NUMERIC,
    opening_short_outstanding NUMERIC,
    shorts_deducted NUMERIC,
    payable_salary NUMERIC
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
  v_opening_short DECIMAL(14,0) := 0;
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

  -- The short carried in from the old book, while it is still uncleared.
  -- No date filter, because it belongs to no pay cycle: it is what the agent
  -- owed on the day the book changed hands.
  SELECT COALESCE(a.opening_short_declared_amount, 0) INTO v_opening_short
  FROM agents a
  WHERE a.agent_id = p_agent_id
    AND a.opening_short_cleared_on IS NULL;
  v_opening_short := COALESCE(v_opening_short, 0);

  v_short := v_short + v_opening_short;
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
    v_opening_short,
    v_short_ded,
    v_base + v_other - v_adv - v_short_ded;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.agent_payable_salary(UUID, DATE, DATE, BOOLEAN, NUMERIC) TO authenticated;
