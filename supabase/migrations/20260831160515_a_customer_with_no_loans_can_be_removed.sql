-- Removing a customer had no path at all: the roster could add and open, and
-- nothing else. Test rows and mistaken entries accumulated with no way to
-- clear them.
--
-- Why an RPC rather than the client writing membership_status directly. RLS
-- would allow it -- business_members_owner_all covers ALL commands for the
-- Owner -- and that is exactly the problem: the one rule that matters, "not
-- while they still owe money", would live only in the Dart that happened to
-- call it. A second screen, or the same screen after a refactor, removes a
-- customer mid-loan and the loan is left pointing at a Removed member.
--
-- This is NOT a delete. The membership goes to 'Removed', which
-- trg_stamp_membership_removed_at timestamps, and every loan, collection and
-- receipt that person is attached to stays exactly where it was. The history
-- of a business must not change because somebody left it.
--
-- No RLS change: is_owner(business_id) is the same gate the table already
-- enforces, restated here because SECURITY DEFINER bypasses the policy.
CREATE OR REPLACE FUNCTION app.remove_customer_membership(p_membership_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_business_id UUID;
  v_status membership_status_enum;
  v_role business_member_role_enum;
  v_customer_id UUID;
  v_active_loans INT;
  v_name TEXT;
BEGIN
  SELECT bm.business_id, bm.membership_status, bm.role, p.full_name
    INTO v_business_id, v_status, v_role, v_name
  FROM business_members bm
  JOIN persons p ON p.person_id = bm.person_id
  WHERE bm.membership_id = p_membership_id
  FOR UPDATE OF bm;

  IF v_business_id IS NULL THEN
    RAISE EXCEPTION 'No such membership' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner can remove a customer' USING ERRCODE = '42501';
  END IF;
  IF v_role <> 'Customer' THEN
    RAISE EXCEPTION 'That membership is not a customer' USING ERRCODE = '23514';
  END IF;
  IF v_status = 'Removed' THEN
    RAISE EXCEPTION 'Already removed' USING ERRCODE = '23514';
  END IF;

  SELECT c.customer_id INTO v_customer_id
  FROM customers c WHERE c.membership_id = p_membership_id;

  -- The rule this function exists to hold. Grace and Penalty are live loans:
  -- money is still owed on them, and they are exactly the ones somebody would
  -- be tempted to make disappear.
  SELECT count(*) INTO v_active_loans
  FROM loans l
  WHERE l.customer_id = v_customer_id
    AND l.deleted_at IS NULL
    AND l.loan_status IN ('Active', 'Grace Period', 'Penalty');

  IF v_active_loans > 0 THEN
    RAISE EXCEPTION
      '% still has % active loan(s). Close or settle them first.',
      v_name, v_active_loans
      USING ERRCODE = '23514';
  END IF;

  UPDATE business_members
     SET membership_status = 'Removed'
   WHERE membership_id = p_membership_id;

  INSERT INTO audit_log (
    business_id, actor_person_id, action_type, entity_type, entity_id,
    entity_uuid, new_value, business_date
  ) VALUES (
    v_business_id, app.current_person_id(), 'Other Admin Event',
    'customer_removed', 0, p_membership_id,
    json_build_object('customer_id', v_customer_id, 'name', v_name),
    CURRENT_DATE
  );

  RETURN json_build_object('status', 'removed', 'membership_id', p_membership_id);
END;
$$;
