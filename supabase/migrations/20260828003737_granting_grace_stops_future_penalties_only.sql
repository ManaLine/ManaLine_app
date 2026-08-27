-- Grace, granted on a loan that is already running.
--
-- loans.grace_period_days has always existed and nothing could change it
-- after the loan was created. An Owner who agreed to give somebody a few more
-- days had no way to record that, so the loan stayed penalty-eligible and the
-- agreement lived in somebody's head.
--
-- DEFAULT FALSE, unlike every other agent permission except delete. Extending
-- the time to pay suppresses penalty eligibility, which is money: it belongs
-- with the permissions an Owner grants deliberately rather than the ones that
-- arrive switched on.
alter table agent_permissions
  add column if not exists can_grant_grace_period boolean not null default false;

comment on column agent_permissions.can_grant_grace_period is
  'Off by default. Granting grace suppresses future penalty eligibility, so it '
  'is an Owner decision to hand out.';

-- Grace stops FUTURE penalties and never touches one already applied.
--
-- A penalty that has been applied is already in remaining_balance -- see
-- apply_loan_penalty -- so clearing it here would silently move what the
-- customer owes, days after the fact, on a screen about dates. If a penalty
-- should come off, that is Waive / Reduce Penalty, which says so and records
-- who did it.
create or replace function app.grant_grace_period(
  p_loan_id uuid,
  p_days integer,
  p_reason text
)
returns json
language plpgsql
security definer
set search_path = public, app
as $$
DECLARE
  v_business_id UUID;
  v_before INT;
  v_status loan_status_enum;
BEGIN
  SELECT l.business_id, l.grace_period_days, l.loan_status
    INTO v_business_id, v_before, v_status
  FROM loans l WHERE l.loan_id = p_loan_id AND l.deleted_at IS NULL;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'No such loan' USING ERRCODE = '23503';
  END IF;

  IF NOT (app.is_owner(v_business_id)
          OR (app.is_active_agent(v_business_id)
              AND app.agent_permission(v_business_id, 'can_grant_grace_period')))
  THEN
    RAISE EXCEPTION 'Not authorized to grant grace on this loan'
      USING ERRCODE = '42501';
  END IF;

  IF p_days IS NULL OR p_days < 0 THEN
    RAISE EXCEPTION 'Grace period cannot be negative' USING ERRCODE = '22023';
  END IF;

  -- A year of grace is not grace, it is a rewritten loan.
  IF p_days > 365 THEN
    RAISE EXCEPTION 'Grace period cannot exceed 365 days' USING ERRCODE = '22023';
  END IF;

  UPDATE loans SET grace_period_days = p_days WHERE loan_id = p_loan_id;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, old_value, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    'loan_grace_period', 0, p_loan_id,
    json_build_object('grace_period_days', v_before),
    json_build_object('grace_period_days', p_days, 'reason', p_reason),
    CURRENT_DATE
  );

  RETURN json_build_object(
    'status', 'granted',
    'loan_id', p_loan_id,
    'grace_period_days', p_days,
    -- Said back explicitly, because it is the thing somebody granting grace
    -- is most likely to assume otherwise.
    'penalties_already_applied_unchanged', true
  );
END;
$$;
