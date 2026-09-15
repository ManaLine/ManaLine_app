ALTER TABLE agent_permissions
  ADD COLUMN IF NOT EXISTS can_record_cheti BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION app.record_cheti_payment(
  p_cheti_id UUID,
  p_gross_instalment DECIMAL(14,0),
  p_dividend DECIMAL(14,0) DEFAULT 0,
  p_remarks TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
  v_cheti_type cheti_type_enum;
  v_instalment_amount DECIMAL(14,0);
  v_total_instalments INT;
  v_opening_paid INT;
  v_status cheti_status_enum;
  v_paid_count INT;
  v_membership_id UUID;
  v_role business_member_role_enum;
  v_owner_bf DECIMAL(14,0);
  v_assignment_id UUID;
  v_agent_bf DECIMAL(14,0);
  v_net_paid DECIMAL(14,0);
  v_payment_id UUID;
BEGIN
  SELECT business_id, cheti_type, instalment_amount, total_instalments,
         opening_instalments_paid, status
    INTO v_business_id, v_cheti_type, v_instalment_amount, v_total_instalments,
         v_opening_paid, v_status
  FROM chetis
  WHERE cheti_id = p_cheti_id
  FOR UPDATE;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'Cheti not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'Running' THEN
    RAISE EXCEPTION 'This cheti is not running' USING ERRCODE = '23514';
  END IF;

  SELECT membership_id, role INTO v_membership_id, v_role
  FROM business_members
  WHERE business_id = v_business_id
    AND person_id = app.current_person_id()
    AND membership_status = 'Active'
  LIMIT 1;
  IF v_membership_id IS NULL THEN
    RAISE EXCEPTION 'Not a member of this cheti''s business' USING ERRCODE = '42501';
  END IF;
  IF v_role <> 'Owner'
     AND NOT app.own_active_agent_membership_permits(v_membership_id, 'can_record_cheti', v_business_id) THEN
    RAISE EXCEPTION 'Not authorized to record cheti payments in this business' USING ERRCODE = '42501';
  END IF;

  IF p_gross_instalment <= 0 THEN
    RAISE EXCEPTION 'Instalment amount must be positive' USING ERRCODE = '23514';
  END IF;
  IF p_dividend < 0 OR p_dividend > p_gross_instalment THEN
    RAISE EXCEPTION 'Dividend cannot be negative or larger than the instalment' USING ERRCODE = '23514';
  END IF;
  IF v_cheti_type = 'Fixed' AND p_gross_instalment <> v_instalment_amount THEN
    RAISE EXCEPTION 'This fixed cheti instalment must be %', v_instalment_amount USING ERRCODE = '23514';
  END IF;

  SELECT COUNT(*) INTO v_paid_count FROM cheti_payments WHERE cheti_id = p_cheti_id;
  IF v_opening_paid + v_paid_count >= v_total_instalments THEN
    RAISE EXCEPTION 'This cheti has already been fully paid' USING ERRCODE = '23514';
  END IF;

  v_net_paid := p_gross_instalment - p_dividend;

  IF v_role = 'Owner' THEN
    SELECT owner_bf_balance INTO v_owner_bf
    FROM businesses WHERE business_id = v_business_id FOR UPDATE;
    IF v_owner_bf < v_net_paid THEN
      RAISE EXCEPTION 'Owner BF is only %, cannot pay a % instalment', v_owner_bf, v_net_paid USING ERRCODE = '23514';
    END IF;
    UPDATE businesses SET owner_bf_balance = owner_bf_balance - v_net_paid
    WHERE business_id = v_business_id;
  ELSIF v_role = 'Agent' THEN
    SELECT assignment_id, agent_bf_current INTO v_assignment_id, v_agent_bf
    FROM agent_bf_assignments
    WHERE membership_id = v_membership_id
    ORDER BY business_date DESC NULLS LAST
    LIMIT 1
    FOR UPDATE;
    IF v_assignment_id IS NULL THEN
      RAISE EXCEPTION 'No BF assignment for this agent — the Owner must grant BF first' USING ERRCODE = 'P0002';
    END IF;
    IF v_agent_bf < v_net_paid THEN
      RAISE EXCEPTION 'Agent BF is only %, cannot pay a % instalment', v_agent_bf, v_net_paid USING ERRCODE = '23514';
    END IF;
    UPDATE agent_bf_assignments
    SET agent_bf_current = agent_bf_current - v_net_paid, updated_at = now()
    WHERE assignment_id = v_assignment_id;
  ELSE
    RAISE EXCEPTION 'Only the Owner or an Agent may pay a cheti instalment' USING ERRCODE = '42501';
  END IF;

  INSERT INTO cheti_payments (cheti_id, business_id, business_date, gross_instalment, dividend, recorded_by_membership_id, remarks)
  VALUES (p_cheti_id, v_business_id, CURRENT_DATE, p_gross_instalment, p_dividend, v_membership_id, p_remarks)
  RETURNING cheti_payment_id INTO v_payment_id;

  RETURN json_build_object('status', 'saved', 'cheti_payment_id', v_payment_id, 'net_paid', v_net_paid);
END;
$$;

COMMENT ON FUNCTION app.record_cheti_payment(UUID, DECIMAL, DECIMAL, TEXT) IS
  'Records one cheti instalment and deducts it from the payer''s own cash (Owner BF, or an Owner-permitted agent''s float). Fixed chetis must match the scheduled instalment; the term can never be overpaid.';

GRANT EXECUTE ON FUNCTION app.record_cheti_payment(UUID, DECIMAL, DECIMAL, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION app.avail_cheti(p_cheti_id UUID, p_amount DECIMAL(14,0))
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_business_id UUID;
BEGIN
  SELECT business_id INTO v_business_id
  FROM chetis
  WHERE cheti_id = p_cheti_id
    AND availed_date IS NULL
  FOR UPDATE;

  IF v_business_id IS NULL THEN
    IF EXISTS (SELECT 1 FROM chetis WHERE cheti_id = p_cheti_id) THEN
      RAISE EXCEPTION 'This cheti has already been availed' USING ERRCODE = '23514';
    ELSE
      RAISE EXCEPTION 'Cheti not found' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may avail a cheti' USING ERRCODE = '42501';
  END IF;
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Availed amount must be positive' USING ERRCODE = '23514';
  END IF;

  UPDATE chetis
  SET availed_date = CURRENT_DATE, availed_amount = p_amount
  WHERE cheti_id = p_cheti_id AND availed_date IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This cheti has already been availed' USING ERRCODE = '23514';
  END IF;

  UPDATE businesses SET owner_bf_balance = owner_bf_balance + p_amount
  WHERE business_id = v_business_id;

  RETURN json_build_object('status', 'saved');
END;
$$;

COMMENT ON FUNCTION app.avail_cheti(UUID, DECIMAL) IS
  'Owner-only. Marks the cheti availed and adds the lumpsum to owner_bf_balance in the same transaction. Re-checks availed_date server-side so a cheti can never be availed twice.';

GRANT EXECUTE ON FUNCTION app.avail_cheti(UUID, DECIMAL) TO authenticated;
