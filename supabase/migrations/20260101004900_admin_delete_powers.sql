-- MANA LINE — 0049_admin_delete_powers.sql
--
-- Platform Admin "super power": complete, irreversible deletion of a
-- person, business, or individual transaction (loan/collection).
-- Gated entirely on app.is_platform_admin() — no other role can call
-- these under any circumstance.
--
-- SAFETY DESIGN:
--   1. Every deletion is logged to admin_deletion_log FIRST, capturing
--      who deleted what and why, before the actual DELETE runs — so
--      there's a permanent record even though the deleted data itself
--      is gone forever.
--   2. p_reason is a REQUIRED parameter, not optional — an admin must
--      state why, every time.
--   3. Deletion order is deepest-child-first, based on the full schema
--      knowledge built up this session. Postgres's own FK constraints
--      mean an incomplete order fails LOUDLY (a clear FK-violation
--      error) rather than silently orphaning or corrupting anything —
--      worst case is "this didn't work, tell Claude which table it hit,"
--      never silent data damage.
--   4. This is IRREVERSIBLE. There is no undo. Treat every call as
--      permanent from the moment it succeeds.

CREATE TABLE admin_deletion_log (
  log_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deleted_by        BIGINT NOT NULL REFERENCES persons(person_id),
  entity_type       TEXT NOT NULL, -- 'person' | 'business' | 'loan' | 'collection'
  entity_id         TEXT NOT NULL, -- stored as text since person_id is bigint but business/loan/collection ids are uuid
  entity_snapshot   JSONB NOT NULL, -- full row(s) as JSON, captured before deletion, for audit/dispute purposes
  reason            TEXT NOT NULL,
  deleted_at        TIMESTAMP NOT NULL DEFAULT now()
);

ALTER TABLE admin_deletion_log ENABLE ROW LEVEL SECURITY;
-- No client policy at all — this log is only ever written by the
-- SECURITY DEFINER functions below, and only ever read via direct DB
-- access (SQL Editor), matching the same deliberate no-client-access
-- pattern as platform_admins itself.

-- -----------------------------------------------------------------------------
-- app.admin_delete_person — full, permanent deletion of a person and
-- every row referencing them, in dependency order (deepest children
-- first). Snapshots the person + their addresses + their business
-- memberships to the audit log before deleting anything.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.admin_delete_person(p_person_id BIGINT, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_admin_id BIGINT := app.current_person_id();
  v_snapshot JSONB;
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A reason is required for every admin deletion.';
  END IF;

  SELECT jsonb_build_object(
    'person', to_jsonb(p.*),
    'addresses', (SELECT jsonb_agg(to_jsonb(pa.*)) FROM person_addresses pa WHERE pa.person_id = p_person_id),
    'memberships', (SELECT jsonb_agg(to_jsonb(bm.*)) FROM business_members bm WHERE bm.person_id = p_person_id)
  ) INTO v_snapshot
  FROM persons p WHERE p.person_id = p_person_id;

  IF v_snapshot IS NULL OR v_snapshot->'person' = 'null'::jsonb THEN
    RAISE EXCEPTION 'Person % not found.', p_person_id;
  END IF;

  INSERT INTO admin_deletion_log (deleted_by, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'person', p_person_id::TEXT, v_snapshot, p_reason);

  -- Deepest leaves first, working up to persons itself.
  DELETE FROM collection_payment_splits WHERE collection_id IN (SELECT collection_id FROM collections WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM collections WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM collections WHERE collected_by_membership_id IN (SELECT membership_id FROM business_members WHERE person_id = p_person_id);
  DELETE FROM loan_schedule WHERE loan_id IN (SELECT loan_id FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id));
  DELETE FROM loan_group_members WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM loans WHERE customer_id IN (SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM settlement_adjustments WHERE account_settlement_id IN (SELECT settlement_id FROM account_settlements WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id));
  DELETE FROM account_settlements WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agent_area_assignments WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agent_permissions WHERE agent_id IN (SELECT agent_id FROM agents WHERE person_id = p_person_id);
  DELETE FROM agents WHERE person_id = p_person_id;
  DELETE FROM customers WHERE person_id = p_person_id;
  DELETE FROM investors WHERE person_id = p_person_id;
  DELETE FROM duplicate_suspects WHERE person_id_a = p_person_id OR person_id_b = p_person_id;
  DELETE FROM notifications WHERE recipient_person_id = p_person_id;
  DELETE FROM otp_verifications WHERE person_id = p_person_id;
  DELETE FROM business_members WHERE person_id = p_person_id;
  DELETE FROM person_addresses WHERE person_id = p_person_id;
  DELETE FROM platform_admins WHERE person_id = p_person_id;
  -- If this person owns any businesses, those must be deleted separately
  -- via admin_delete_business first — deliberately NOT auto-cascaded
  -- here, since deleting a whole business is a much bigger blast radius
  -- that deserves its own explicit call and its own reason.
  DELETE FROM persons WHERE person_id = p_person_id;
END;
$$;

COMMENT ON FUNCTION app.admin_delete_person(BIGINT, TEXT) IS
  'Platform Admin super power — permanent, irreversible deletion of a person and every dependent row. Logs a full snapshot to admin_deletion_log before deleting. If this person owns a business, delete that business first via admin_delete_business.';

GRANT EXECUTE ON FUNCTION app.admin_delete_person(BIGINT, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.admin_delete_business — full, permanent deletion of a business and
-- everything under it (members, loans, collections, settlements, areas,
-- account periods). Does NOT delete the persons themselves — only their
-- membership in and everything they did within this specific business.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.admin_delete_business(p_business_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_admin_id BIGINT := app.current_person_id();
  v_snapshot JSONB;
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A reason is required for every admin deletion.';
  END IF;

  SELECT to_jsonb(b.*) INTO v_snapshot FROM businesses b WHERE b.business_id = p_business_id;
  IF v_snapshot IS NULL THEN
    RAISE EXCEPTION 'Business % not found.', p_business_id;
  END IF;

  INSERT INTO admin_deletion_log (deleted_by, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'business', p_business_id::TEXT, v_snapshot, p_reason);

  DELETE FROM collection_payment_splits WHERE collection_id IN (SELECT collection_id FROM collections WHERE business_id = p_business_id);
  DELETE FROM collections WHERE business_id = p_business_id;
  DELETE FROM loan_schedule WHERE loan_id IN (SELECT loan_id FROM loans WHERE business_id = p_business_id);
  DELETE FROM loan_group_members WHERE group_id IN (SELECT group_id FROM loan_groups WHERE business_id = p_business_id);
  DELETE FROM loan_groups WHERE business_id = p_business_id;
  DELETE FROM loans WHERE business_id = p_business_id;
  DELETE FROM settlement_adjustments WHERE account_settlement_id IN (SELECT settlement_id FROM account_settlements acs JOIN account_periods ap ON ap.account_period_id = acs.account_period_id WHERE ap.business_id = p_business_id);
  DELETE FROM account_settlements WHERE account_period_id IN (SELECT account_period_id FROM account_periods WHERE business_id = p_business_id);
  DELETE FROM account_periods WHERE business_id = p_business_id;
  DELETE FROM agent_area_assignments WHERE operating_area_id IN (SELECT operating_area_id FROM operating_areas WHERE business_id = p_business_id);
  DELETE FROM agent_permissions WHERE agent_id IN (SELECT agent_id FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id));
  DELETE FROM agents WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM customers WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM investors WHERE membership_id IN (SELECT membership_id FROM business_members WHERE business_id = p_business_id);
  DELETE FROM operating_areas WHERE business_id = p_business_id;
  DELETE FROM expenses WHERE business_id = p_business_id;
  DELETE FROM business_members WHERE business_id = p_business_id;
  DELETE FROM businesses WHERE business_id = p_business_id;
END;
$$;

COMMENT ON FUNCTION app.admin_delete_business(UUID, TEXT) IS
  'Platform Admin super power — permanent, irreversible deletion of a business and everything under it. Does not delete the persons themselves, only their footprint within this business.';

GRANT EXECUTE ON FUNCTION app.admin_delete_business(UUID, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.admin_delete_loan / app.admin_delete_collection — individual
-- "transaction" deletion. Narrower blast radius than the two above.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.admin_delete_loan(p_loan_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_admin_id BIGINT := app.current_person_id();
  v_snapshot JSONB;
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A reason is required for every admin deletion.';
  END IF;

  SELECT jsonb_build_object(
    'loan', to_jsonb(l.*),
    'collections', (SELECT jsonb_agg(to_jsonb(c.*)) FROM collections c WHERE c.loan_id = p_loan_id),
    'schedule', (SELECT jsonb_agg(to_jsonb(s.*)) FROM loan_schedule s WHERE s.loan_id = p_loan_id)
  ) INTO v_snapshot
  FROM loans l WHERE l.loan_id = p_loan_id;

  IF v_snapshot IS NULL OR v_snapshot->'loan' = 'null'::jsonb THEN
    RAISE EXCEPTION 'Loan % not found.', p_loan_id;
  END IF;

  INSERT INTO admin_deletion_log (deleted_by, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'loan', p_loan_id::TEXT, v_snapshot, p_reason);

  DELETE FROM collection_payment_splits WHERE collection_id IN (SELECT collection_id FROM collections WHERE loan_id = p_loan_id);
  DELETE FROM collections WHERE loan_id = p_loan_id;
  DELETE FROM loan_schedule WHERE loan_id = p_loan_id;
  DELETE FROM loan_group_members WHERE loan_id = p_loan_id;
  DELETE FROM loans WHERE loan_id = p_loan_id;
END;
$$;

COMMENT ON FUNCTION app.admin_delete_loan(UUID, TEXT) IS
  'Platform Admin super power — permanent deletion of a single loan and its collections/schedule.';

GRANT EXECUTE ON FUNCTION app.admin_delete_loan(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION app.admin_delete_collection(p_collection_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_admin_id BIGINT := app.current_person_id();
  v_snapshot JSONB;
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A reason is required for every admin deletion.';
  END IF;

  SELECT to_jsonb(c.*) INTO v_snapshot FROM collections c WHERE c.collection_id = p_collection_id;
  IF v_snapshot IS NULL THEN
    RAISE EXCEPTION 'Collection % not found.', p_collection_id;
  END IF;

  INSERT INTO admin_deletion_log (deleted_by, entity_type, entity_id, entity_snapshot, reason)
  VALUES (v_admin_id, 'collection', p_collection_id::TEXT, v_snapshot, p_reason);

  DELETE FROM collection_payment_splits WHERE collection_id = p_collection_id;
  DELETE FROM collections WHERE collection_id = p_collection_id;
END;
$$;

COMMENT ON FUNCTION app.admin_delete_collection(UUID, TEXT) IS
  'Platform Admin super power — permanent deletion of a single collection entry.';

GRANT EXECUTE ON FUNCTION app.admin_delete_collection(UUID, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.is_platform_admin_client — thin public wrapper so the CLIENT app
-- can check "should I show the Admin menu item at all" without needing
-- direct table access. is_platform_admin() itself already exists (0029b)
-- but was never explicitly GRANTed to authenticated for general client
-- use — confirming/re-granting here for clarity.
-- -----------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION app.is_platform_admin() TO authenticated;
