-- =============================================================================
-- 0022 — Module 13: Business Session RPCs (AG-001 Area Selection)
-- =============================================================================
-- Closes the 5 RPC gaps flagged by the Agent Dashboard sub-chat. Previously
-- deferred in 0021 because "add/remove area from session" looked like it
-- didn't map onto account_periods (one operating_area_id per row, not a
-- list). Re-read against AG-001_Agent_Home_Dashboard.md directly, which
-- resolves this explicitly:
--   "A Business Session has no dedicated 'session' table in the schema — it
--    is the Agent-facing presentation of one or more account_periods rows —
--    one row per selected Operating Area... a multi-area session is
--    therefore N account_period rows created together, not one row
--    spanning N areas. No new table required."
-- So there is no mismatch — just no single "session" row to hang the RPCs
-- off of. The 5 functions below operate on account_periods directly.
--
-- Also per AG-001's own API BINDING section: "No POST /agent/session/*
-- endpoints exist or are needed... Collection Mode/route state re-derives
-- client-side on each launch." That statement is about REST endpoints, not
-- about whether a WRITE needs to happen — starting a session and adding an
-- area both genuinely insert account_periods rows (confirmed: Agent has
-- SELECT-only RLS on account_periods, 0013 — no INSERT/UPDATE policy for
-- Agent exists, so this cannot be a plain client insert regardless).
-- Removing an area, per the spec's own words ("does not delete or modify
-- its existing account_periods row"), needs NO account_periods write at
-- all — see 13.3 below, which is audit-log-only.

-- -----------------------------------------------------------------------------
-- 13.0 audit_action_type_enum has no value fitting "session start" or "area
-- change" (checked: Settings Change, Permission Change, Loan Correction,
-- Collection Correction, Membership Change, Day Reopen, PIN Approval,
-- Password Reset, Account Approval, Other Admin Event — none fit). Adding
-- two real values rather than overloading 'Other Admin Event', since
-- AG-001's Business Rules explicitly call out "Every session creates an
-- audit record" as a named requirement, not an incidental admin event.
-- NOTE: ALTER TYPE ... ADD VALUE cannot be used in the same transaction as
-- a statement that references the new value on PG <12. This migration
-- assumes PG12+ (Supabase's minimum has been 13+ for years); if this
-- migration fails on ADD VALUE + usage in one transaction, split this
-- block into its own migration file first.
-- -----------------------------------------------------------------------------
ALTER TYPE audit_action_type_enum ADD VALUE IF NOT EXISTS 'Session Start';
ALTER TYPE audit_action_type_enum ADD VALUE IF NOT EXISTS 'Area Change';

-- -----------------------------------------------------------------------------
-- 13.1 start_business_session — creates N account_periods rows (one per
-- selected area), all sharing business_start_date, per AG-001's own model.
-- Validates the 5 SYSTEM VALIDATION checks named in the spec: Business
-- Membership Active, Agent Status Active, Area Enabled, Business Active,
-- Area assigned to this Agent. ("Permission Available" is named in the
-- spec but no specific agent_permissions column is identified for
-- "starting a session" itself — not gated on a guessed column name.)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.start_business_session(p_membership_id UUID, p_area_ids UUID[])
RETURNS UUID[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_agent_id UUID;
  v_area_id UUID;
  v_period_id UUID;
  v_result UUID[] := ARRAY[]::UUID[];
  v_now TIMESTAMP := now();
BEGIN
  IF NOT app.membership_belongs_to_current_person(p_membership_id) THEN
    RAISE EXCEPTION 'Not your own membership' USING ERRCODE = '42501';
  END IF;
  IF array_length(p_area_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'At least one area must be selected' USING ERRCODE = '23514';
  END IF;

  SELECT bm.business_id, a.agent_id INTO v_business_id, v_agent_id
  FROM business_members bm
  JOIN agents a ON a.membership_id = bm.membership_id
  WHERE bm.membership_id = p_membership_id AND bm.membership_status = 'Active' AND a.current_status = 'Active';

  IF v_agent_id IS NULL THEN
    RAISE EXCEPTION 'Agent record not found or not Active' USING ERRCODE = 'P0002';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM businesses WHERE business_id = v_business_id AND business_status = 'Active') THEN
    RAISE EXCEPTION 'Business is not Active' USING ERRCODE = '23514';
  END IF;

  FOREACH v_area_id IN ARRAY p_area_ids LOOP
    IF NOT EXISTS (
      SELECT 1 FROM operating_areas oa
      JOIN agent_area_assignments aaa ON aaa.operating_area_id = oa.operating_area_id
      WHERE oa.operating_area_id = v_area_id AND oa.business_id = v_business_id AND oa.status = 'Active'
        AND aaa.agent_id = v_agent_id AND aaa.removed_at IS NULL
    ) THEN
      RAISE EXCEPTION 'Area % is not an enabled, assigned area for this agent', v_area_id USING ERRCODE = '23514';
    END IF;
    IF EXISTS (
      SELECT 1 FROM account_periods
      WHERE operating_area_id = v_area_id AND agent_membership_id = p_membership_id AND status = 'Running'
    ) THEN
      RAISE EXCEPTION 'Area % already has a Running session for this agent', v_area_id USING ERRCODE = '23514';
    END IF;

    INSERT INTO account_periods (
      business_id, operating_area_id, agent_membership_id, business_start_date,
      planned_business_end_date, status
    )
    SELECT v_business_id, v_area_id, p_membership_id, v_now,
           v_now + CASE oa.account_cycle_unit
             WHEN 'Days' THEN (oa.account_cycle_duration::TEXT || ' days')::INTERVAL
             WHEN 'Weeks' THEN (oa.account_cycle_duration::TEXT || ' weeks')::INTERVAL
             WHEN 'Months' THEN (oa.account_cycle_duration::TEXT || ' months')::INTERVAL
           END,
           'Running'
    FROM operating_areas oa WHERE oa.operating_area_id = v_area_id
    RETURNING account_period_id INTO v_period_id;

    v_result := array_append(v_result, v_period_id);

    INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type, entity_id, new_value, business_date)
    VALUES (v_business_id, app.current_person_id(), 'Session Start', 'account_period', 0,
            json_build_object('account_period_id', v_period_id, 'operating_area_id', v_area_id), v_now::DATE);
  END LOOP;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION app.start_business_session(UUID, UUID[]) IS
  'AG-001 Start Business Session. Creates one account_periods row per selected area (per the spec''s own "N rows, no session table" model). audit_log.entity_id is BIGINT (polymorphic, not a real FK per its own table comment) — set to 0 since account_period_id is a UUID with no BIGINT counterpart; the real reference lives in new_value JSON instead. Flagged, not a clean fit.';

GRANT EXECUTE ON FUNCTION app.start_business_session(UUID, UUID[]) TO authenticated;

-- -----------------------------------------------------------------------------
-- 13.2 add_area_to_session — one new account_periods row, business_start_date
-- = now (NOT backdated to the original session start, per spec). Blocked if
-- Pending Unsaved Transactions exist — same collection_drafts proxy already
-- used/flagged in DayClosureApiService.precheck (business_date is inferred
-- from created_at, not a real column on collection_drafts).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.add_area_to_session(p_membership_id UUID, p_area_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_agent_id UUID;
  v_period_id UUID;
  v_now TIMESTAMP := now();
BEGIN
  IF NOT app.membership_belongs_to_current_person(p_membership_id) THEN
    RAISE EXCEPTION 'Not your own membership' USING ERRCODE = '42501';
  END IF;

  SELECT bm.business_id, a.agent_id INTO v_business_id, v_agent_id
  FROM business_members bm JOIN agents a ON a.membership_id = bm.membership_id
  WHERE bm.membership_id = p_membership_id AND bm.membership_status = 'Active' AND a.current_status = 'Active';
  IF v_agent_id IS NULL THEN
    RAISE EXCEPTION 'Agent record not found or not Active' USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1 FROM collection_drafts WHERE created_by_membership_id = p_membership_id AND status = 'Draft'
  ) THEN
    RAISE EXCEPTION 'Pending Unsaved Transactions exist — resolve drafts before changing areas' USING ERRCODE = '23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM operating_areas oa
    JOIN agent_area_assignments aaa ON aaa.operating_area_id = oa.operating_area_id
    WHERE oa.operating_area_id = p_area_id AND oa.business_id = v_business_id AND oa.status = 'Active'
      AND aaa.agent_id = v_agent_id AND aaa.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Area is not an enabled, assigned area for this agent' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM account_periods
    WHERE operating_area_id = p_area_id AND agent_membership_id = p_membership_id AND status = 'Running'
  ) THEN
    RAISE EXCEPTION 'This area already has a Running session for this agent' USING ERRCODE = '23514';
  END IF;

  INSERT INTO account_periods (
    business_id, operating_area_id, agent_membership_id, business_start_date,
    planned_business_end_date, status
  )
  SELECT v_business_id, p_area_id, p_membership_id, v_now,
         v_now + CASE oa.account_cycle_unit
           WHEN 'Days' THEN (oa.account_cycle_duration::TEXT || ' days')::INTERVAL
           WHEN 'Weeks' THEN (oa.account_cycle_duration::TEXT || ' weeks')::INTERVAL
           WHEN 'Months' THEN (oa.account_cycle_duration::TEXT || ' months')::INTERVAL
         END,
         'Running'
  FROM operating_areas oa WHERE oa.operating_area_id = p_area_id
  RETURNING account_period_id INTO v_period_id;

  INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type, entity_id, new_value, business_date)
  VALUES (v_business_id, app.current_person_id(), 'Area Change', 'account_period', 0,
          json_build_object('action', 'add', 'account_period_id', v_period_id, 'operating_area_id', p_area_id), v_now::DATE);

  RETURN v_period_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.add_area_to_session(UUID, UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- 13.3 remove_area_from_session — per the spec's own words, does NOT touch
-- account_periods at all ("removing an area does not delete or modify its
-- existing account_periods row — that row continues to its own
-- planned_business_end_date and Submit/Approve cycle independently").
-- This function is therefore audit-log-only — the client is responsible for
-- no longer presenting this area as part of the active working set
-- (re-derived client-side per AG-001's own API BINDING note). Still blocked
-- on Pending Unsaved Transactions for this area's drafts, same as add.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.remove_area_from_session(p_membership_id UUID, p_area_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
BEGIN
  IF NOT app.membership_belongs_to_current_person(p_membership_id) THEN
    RAISE EXCEPTION 'Not your own membership' USING ERRCODE = '42501';
  END IF;

  SELECT business_id INTO v_business_id FROM business_members WHERE membership_id = p_membership_id;

  IF EXISTS (
    SELECT 1 FROM collection_drafts WHERE created_by_membership_id = p_membership_id AND status = 'Draft'
  ) THEN
    RAISE EXCEPTION 'Pending Unsaved Transactions exist — resolve drafts before changing areas' USING ERRCODE = '23514';
  END IF;

  INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type, entity_id, new_value, business_date)
  VALUES (v_business_id, app.current_person_id(), 'Area Change', 'account_period', 0,
          json_build_object('action', 'remove', 'operating_area_id', p_area_id, 'membership_id', p_membership_id), CURRENT_DATE);
END;
$$;

COMMENT ON FUNCTION app.remove_area_from_session(UUID, UUID) IS
  'AG-001 Remove Area. Deliberately does not touch account_periods — per spec, that row keeps running independently to its own end date. Client re-derives "active working set" itself; this call exists only to produce the required audit_log entry.';

GRANT EXECUTE ON FUNCTION app.remove_area_from_session(UUID, UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- 13.4 confirm_bf_assignment / request_bf_update — Opening BF Confirm/Update
-- gate (AG-001's "OPENING BF CONFIRM/UPDATE GATE" section).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.confirm_bf_assignment(p_membership_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.membership_belongs_to_current_person(p_membership_id) THEN
    RAISE EXCEPTION 'Not your own membership' USING ERRCODE = '42501';
  END IF;

  UPDATE agent_bf_assignments
  SET confirmed_by_agent = TRUE, update_requested = FALSE, updated_at = now()
  WHERE assignment_id = (
    SELECT assignment_id FROM agent_bf_assignments
    WHERE membership_id = p_membership_id
    ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
    LIMIT 1
  );

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No agent_bf_assignments row exists for this agent — access not yet granted' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION app.confirm_bf_assignment(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION app.request_bf_update(p_membership_id UUID, p_note TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.membership_belongs_to_current_person(p_membership_id) THEN
    RAISE EXCEPTION 'Not your own membership' USING ERRCODE = '42501';
  END IF;

  UPDATE agent_bf_assignments
  SET update_requested = TRUE, updated_at = now()
  WHERE assignment_id = (
    SELECT assignment_id FROM agent_bf_assignments
    WHERE membership_id = p_membership_id
    ORDER BY COALESCE(business_date::TIMESTAMP, created_at) DESC
    LIMIT 1
  );

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No agent_bf_assignments row exists for this agent — access not yet granted' USING ERRCODE = 'P0002';
  END IF;

  -- Owner notification: NOT done here. notifications (0018 RLS) has no
  -- client INSERT policy for any role — same established gap as every
  -- other "notify the Owner" flag in this codebase (BR-238, etc.). The
  -- Owner-side "direct re-entry form" AG-001 describes must poll/query
  -- agent_bf_assignments.update_requested = TRUE directly, not rely on a
  -- notification row this RPC cannot create.
END;
$$;

COMMENT ON FUNCTION app.request_bf_update(UUID, TEXT) IS
  'AG-001 Update BF gate. p_note has no column to land in on agent_bf_assignments (no remarks/note field exists there) — accepted but currently discarded; flagged rather than silently writing it somewhere unrelated. Owner notification not implemented, same class of gap as elsewhere (no client INSERT policy on notifications).';

GRANT EXECUTE ON FUNCTION app.request_bf_update(UUID, TEXT) TO authenticated;
