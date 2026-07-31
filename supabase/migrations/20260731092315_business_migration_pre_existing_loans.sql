-- Pre-existing business migration. Confirmed with the Owner 2026-07-31.
--
-- BF for a migrated business is CASH IN HAND:
--   BF = sum(investment principal)
--        - sum(amount given out on existing loans)
--        + sum(already collected on those loans)
-- and the money still out on the line is tracked separately as the Line
-- Balance (sum of remaining_balance), NOT inside BF. This matches what BF
-- means everywhere else in the app: a figure you can physically count.
--
-- Per loan the Owner enters Amount Given, Repayment Amount and Remaining
-- Balance. Collected and interest are derived, so BR-004/BR-011 stays
-- intact (Amount Given = Repayment - Interest - Fee).
--
-- The repayment schedule is generated FORWARD FROM TODAY ONLY, sized to
-- the remaining balance. No past installments are fabricated: GLOBAL
-- BR-212 scores on-time behaviour from completed_at vs due_date, and
-- inventing a clean history would hand every migrated customer a Line
-- Score they had not earned.
--
-- NOTE ON THIS FILE: app.migrate_loan's first version is deliberately NOT
-- reproduced here. It was replaced three times within minutes (see the
-- three files that follow) and never executed successfully — plpgsql does
-- not type-check bodies at CREATE time, so each fault only surfaced on
-- call. The definitive body lives in
-- 20260731092702_migrate_loan_live_photo_sentinel.sql, which is a full
-- CREATE OR REPLACE, so replaying this directory in order yields the
-- correct final function.

-- --------------------------------------------------------------------
-- 1. A permission distinct from issuing loans. Entering pre-existing
--    records restates the opening cash position, which is a heavier
--    power than lending today.
-- --------------------------------------------------------------------
ALTER TABLE public.agent_permissions
  ADD COLUMN IF NOT EXISTS can_migrate_records boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.agent_permissions.can_migrate_records IS
  'May enter pre-existing loans during migration. Moves owner_bf_balance, so deliberately separate from can_issue_loans.';

-- --------------------------------------------------------------------
-- 2. Reopen / lock the migration window (BR-159).
--    BR-159 locks migration permanently at Business Started. Reopening is
--    allowed but never silent: Owner only, typed reason, audit row.
--    Mirrors the Reopen Closed Day pattern (GLOBAL BR-221/BR-222).
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.reopen_migration(
  p_business_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may reopen migration' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR btrim(p_reason) = '' THEN
    RAISE EXCEPTION 'A reason is required to reopen migration' USING ERRCODE = '23514';
  END IF;

  UPDATE businesses SET migration_locked = false WHERE business_id = p_business_id;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    p_business_id, app.current_person_id(), 'Other Admin Event', 'migration_reopened', 0,
    p_business_id, json_build_object('reason', p_reason), CURRENT_DATE
  );
END;
$function$;

CREATE OR REPLACE FUNCTION app.lock_migration(p_business_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may lock migration' USING ERRCODE = '42501';
  END IF;

  UPDATE businesses
  SET migration_locked = true,
      business_status = 'Active',
      business_started_at = COALESCE(business_started_at, now())
  WHERE business_id = p_business_id;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    p_business_id, app.current_person_id(), 'Other Admin Event', 'migration_locked', 0,
    p_business_id, json_build_object('locked', true), CURRENT_DATE
  );
END;
$function$;

-- --------------------------------------------------------------------
-- 3. Migration totals for the screen.
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.migration_summary(p_business_id uuid)
RETURNS TABLE(
  migration_locked boolean,
  business_started_at timestamp,
  investment_principal numeric,
  migrated_loan_count integer,
  total_given numeric,
  total_collected numeric,
  line_balance numeric,
  bf numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_owner(p_business_id) AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    b.migration_locked,
    b.business_started_at,
    COALESCE((SELECT SUM(i.original_principal_amount) FROM investments i
              WHERE i.business_id = p_business_id AND i.status = 'Active'), 0),
    COALESCE((SELECT COUNT(*)::int FROM loans l
              WHERE l.business_id = p_business_id AND l.loan_number LIKE 'LN-MIG-%'), 0),
    COALESCE((SELECT SUM(l.amount_given) FROM loans l
              WHERE l.business_id = p_business_id AND l.loan_number LIKE 'LN-MIG-%'), 0),
    COALESCE((SELECT SUM(l.repayment_amount - l.remaining_balance) FROM loans l
              WHERE l.business_id = p_business_id AND l.loan_number LIKE 'LN-MIG-%'), 0),
    COALESCE((SELECT SUM(l.remaining_balance) FROM loans l
              WHERE l.business_id = p_business_id
                AND l.loan_status NOT IN ('Closed', 'Cancelled', 'Draft')), 0),
    b.owner_bf_balance
  FROM businesses b WHERE b.business_id = p_business_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.reopen_migration(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION app.lock_migration(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION app.migration_summary(uuid) TO authenticated;
