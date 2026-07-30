-- =============================================================================
-- 0019 — Module 10: Discovery RPC, Investment Statement RPC, Phone History
-- =============================================================================
-- Closes three gaps flagged during Investor/Customer Workspace state-layer
-- wiring (IW-002/CW-002 discovery, IW-003 statement download, IW-005/CW-006
-- BR-238 phone history). All three follow existing conventions in this repo
-- (SECURITY DEFINER RPC pattern from 0012, person_addresses-style history
-- table pattern from 0001).

-- -----------------------------------------------------------------------------
-- 10.1 discover_businesses — CW-002/IW-002 discovery search.
-- businesses RLS (0013) only grants SELECT to the Owner or an Active member,
-- so unaffiliated Investors/Customers cannot see businesses to request
-- membership at. This RPC exposes only the minimal public fields needed for
-- discovery, plus the caller's own existing request/membership status (so
-- the client can drive DiscoveryPhase.requestPending/approved/rejected)
-- without ever returning another person's data.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.discover_businesses(p_search TEXT, p_role TEXT)
RETURNS TABLE (
  business_id UUID,
  business_name VARCHAR(150),
  mlbi VARCHAR(20),
  business_type VARCHAR(100),
  logo_url TEXT,
  accepting_new_investors BOOLEAN,
  accepting_new_customers BOOLEAN,
  caller_membership_status membership_status_enum,
  caller_request_status membership_request_status_enum,
  caller_request_cooldown_until TIMESTAMP
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT
    b.business_id,
    b.business_name,
    b.mlbi,
    b.business_type,
    b.logo_url,
    b.accepting_new_investors,
    b.accepting_new_customers,
    bm.membership_status,
    mr.status,
    mr.cooldown_until
  FROM businesses b
  LEFT JOIN business_members bm
    ON bm.business_id = b.business_id
   AND bm.person_id = app.current_person_id()
   AND bm.role = p_role::business_member_role_enum
  LEFT JOIN LATERAL (
    SELECT status, cooldown_until
    FROM membership_requests
    WHERE membership_requests.business_id = b.business_id
      AND membership_requests.person_id = app.current_person_id()
      AND membership_requests.requested_role = p_role::membership_request_role_enum
    ORDER BY created_at DESC
    LIMIT 1
  ) mr ON TRUE
  WHERE b.business_status = 'Active'
    AND (p_role <> 'Investor' OR b.accepting_new_investors)
    AND (p_role <> 'Customer' OR b.accepting_new_customers)
    AND (p_search IS NULL OR p_search = '' OR b.business_name ILIKE '%' || p_search || '%' OR b.mlbi ILIKE '%' || p_search || '%')
  ORDER BY b.business_name;
$$;

COMMENT ON FUNCTION app.discover_businesses(TEXT, TEXT) IS
  'IW-002/CW-002 discovery search. SECURITY DEFINER because businesses RLS (0013) does not grant SELECT to non-members; this function returns only the public fields (name/mlbi/type) plus the CALLING person''s own membership/request status, never another person''s data. p_role must be ''Investor'' or ''Customer''.';

GRANT EXECUTE ON FUNCTION app.discover_businesses(TEXT, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- 10.2 get_investment_statement — IW-003 "Download Statement".
-- No dedicated statement table/RPC existed. Rather than generate a PDF
-- server-side (out of scope for this migration) or reimplement the live
-- Calculation Engine client-side (explicitly disallowed per prior flags),
-- this returns the raw ledger/distribution/withdrawal rows for the caller's
-- own investment as structured JSON — the client formats/exports it.
-- Ownership is enforced inside the function body (not just RLS) since it
-- aggregates across three tables in one call.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.get_investment_statement(p_investment_id UUID)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_owns BOOLEAN;
  v_result JSON;
BEGIN
  SELECT app.is_own_investment_row(p_investment_id) INTO v_owns;
  IF NOT v_owns THEN
    RAISE EXCEPTION 'Not authorized for this investment' USING ERRCODE = '42501';
  END IF;

  SELECT json_build_object(
    'investment', (
      SELECT json_build_object(
        'investment_id', i.investment_id,
        'principal_amount', i.principal_amount,
        'original_principal_amount', i.original_principal_amount,
        'roi_rate', i.roi_rate,
        'interest_type', i.interest_type,
        'effective_date', i.effective_date,
        'status', i.status
      )
      FROM investments i WHERE i.investment_id = p_investment_id
    ),
    'interest_ledger', (
      SELECT COALESCE(json_agg(json_build_object(
        'entry_type', l.entry_type,
        'amount', l.amount,
        'business_date', l.business_date,
        'owner_verified', l.owner_verified,
        'remarks', l.remarks
      ) ORDER BY l.business_date), '[]'::json)
      FROM investment_interest_ledger l WHERE l.investment_id = p_investment_id
    ),
    'distributions', (
      SELECT COALESCE(json_agg(json_build_object(
        'declaration_id', d.declaration_id,
        'declared_amount', d.declared_amount,
        'business_date', d.business_date,
        'status', d.status,
        'paid_amount', dp.paid_amount,
        'interest_amount', dp.interest_amount,
        'paid_business_date', dp.business_date
      ) ORDER BY d.business_date), '[]'::json)
      FROM distribution_declarations d
      LEFT JOIN distribution_payments dp ON dp.declaration_id = d.declaration_id
      WHERE d.investment_id = p_investment_id
    ),
    'withdrawal_requests', (
      SELECT COALESCE(json_agg(json_build_object(
        'request_id', w.request_id,
        'withdrawal_type', w.withdrawal_type,
        'requested_amount', w.requested_amount,
        'status', w.status,
        'created_at', w.created_at,
        'resolved_at', w.resolved_at
      ) ORDER BY w.created_at), '[]'::json)
      FROM investment_withdrawal_requests w WHERE w.investment_id = p_investment_id
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION app.get_investment_statement(UUID) IS
  'IW-003 Download Statement. Returns raw ledger/distribution/withdrawal rows as JSON for client-side formatting/export — does not reimplement Calculation Engine derived figures. Ownership enforced in-body via app.is_own_investment_row since this aggregates three tables in one SECURITY DEFINER call.';

GRANT EXECUTE ON FUNCTION app.get_investment_statement(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- 10.3 person_phone_history — BR-238 phone edit history.
-- Mirrors person_addresses' existing history pattern exactly (close old
-- current row, insert new current row) so profile state files can write it
-- the same way they already write address history, no RPC needed.
-- -----------------------------------------------------------------------------
CREATE TABLE person_phone_history (
    phone_history_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    person_id         BIGINT NOT NULL REFERENCES persons(person_id),
    phone_number      VARCHAR(15) NOT NULL,
    from_date         DATE NOT NULL,
    to_date           DATE NULL,                 -- NULL = current
    reason            VARCHAR(255) NULL,
    is_current        BOOLEAN NOT NULL DEFAULT TRUE
);
COMMENT ON TABLE person_phone_history IS
  'BR-238 phone edit history, added 0019 to close the gap flagged during IW-005/CW-006 wiring (no phone-history table existed previously; edits were plain persons.mobile_number updates with no trail). Same is_current/to_date invariant as person_addresses: exactly one is_current=TRUE row per person, enforced app-side.';

ALTER TABLE person_phone_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY person_phone_history_self_all ON person_phone_history
  FOR ALL
  USING (person_id = app.current_person_id())
  WITH CHECK (person_id = app.current_person_id());

CREATE POLICY person_phone_history_business_partner_select ON person_phone_history
  FOR SELECT
  USING (app.shares_active_business(person_phone_history.person_id));

CREATE INDEX idx_person_phone_history_person ON person_phone_history(person_id);
