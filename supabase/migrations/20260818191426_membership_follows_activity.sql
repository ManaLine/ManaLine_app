-- Membership becomes implicit: you are in a business while you have activity
-- there, and you drop out of its lists when you do not. You stay findable in
-- global search either way, because the person still exists.
--
-- The business_members ROW stays. 12 RLS policies and 66 app functions key off
-- it, so it is the anchor that decides who can read what; deleting rows to
-- express "not active any more" would revoke access to that person's own
-- history. What changes is what the Owner's lists show, and that nobody can be
-- attached to a business without a reason to be there.
--
-- What counts as activity, per role:
--   Customer  a loan that is not Closed/Cancelled/Draft and not deleted
--   Investor  an investment that is Active with principal left, not deleted
--   Agent     an area assignment valid today, or a granted access day
--   Owner     always - it is their business
CREATE OR REPLACE FUNCTION app.membership_is_active(p_membership_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SET search_path = pg_catalog, public AS $$
DECLARE
  v_role business_member_role_enum;
  v_status membership_status_enum;
BEGIN
  SELECT role, membership_status INTO v_role, v_status
    FROM business_members WHERE membership_id = p_membership_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  -- An Owner who removed someone means it; activity does not undo that.
  IF v_status = 'Removed' THEN
    RETURN false;
  END IF;

  IF v_role = 'Owner' THEN
    RETURN true;
  ELSIF v_role = 'Customer' THEN
    RETURN EXISTS (
      SELECT 1 FROM loans l
        JOIN customers c ON c.customer_id = l.customer_id
       WHERE c.membership_id = p_membership_id
         AND l.deleted_at IS NULL
         AND l.loan_status NOT IN ('Closed', 'Cancelled', 'Draft')
    );
  ELSIF v_role = 'Investor' THEN
    RETURN EXISTS (
      SELECT 1 FROM investments i
        JOIN investors iv ON iv.investor_id = i.investor_id
       WHERE iv.membership_id = p_membership_id
         AND i.deleted_at IS NULL
         AND i.status = 'Active'
         AND i.principal_amount > 0
    );
  ELSIF v_role = 'Agent' THEN
    RETURN EXISTS (
      SELECT 1 FROM agent_area_assignments aa
        JOIN agents a ON a.agent_id = aa.agent_id
       WHERE a.membership_id = p_membership_id
         AND aa.valid_from <= CURRENT_DATE
         AND (aa.valid_to IS NULL OR aa.valid_to >= CURRENT_DATE)
    ) OR EXISTS (
      SELECT 1 FROM agent_access_days d WHERE d.membership_id = p_membership_id
    );
  END IF;
  RETURN false;
END;
$$;

GRANT EXECUTE ON FUNCTION app.membership_is_active(uuid) TO authenticated, service_role;

-- Attaching an investor and recording their first investment become one act.
-- The attach-only step was the whole reason a business could hold a member who
-- had never done anything there; now a membership cannot be created without
-- the activity that justifies it.
CREATE OR REPLACE FUNCTION app.attach_investor_with_first_investment(
  p_business_id uuid,
  p_person_id bigint,
  p_amount numeric,
  p_roi_rate numeric,
  p_interest_type investment_interest_type_enum,
  p_effective_date date,
  p_profit_share_percent numeric DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_membership_id uuid;
  v_investor_id uuid;
  v_investment_id uuid;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'An investment amount is required to add an investor.' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM persons WHERE person_id = p_person_id) THEN
    RAISE EXCEPTION 'That person no longer exists.' USING ERRCODE = 'P0002';
  END IF;

  SELECT membership_id INTO v_membership_id
    FROM business_members
   WHERE business_id = p_business_id AND person_id = p_person_id AND role = 'Investor';

  IF v_membership_id IS NULL THEN
    INSERT INTO business_members (
      person_id, business_id, role, membership_status, verification_status,
      onboarding_method, invited_by_person_id, joined_at
    ) VALUES (
      p_person_id, p_business_id, 'Investor', 'Active', 'Not Required',
      'Direct Registration', app.current_person_id(), now()
    ) RETURNING membership_id INTO v_membership_id;
  ELSE
    UPDATE business_members
       SET membership_status = 'Active', removed_at = NULL,
           joined_at = COALESCE(joined_at, now())
     WHERE membership_id = v_membership_id;
  END IF;

  SELECT investor_id INTO v_investor_id FROM investors WHERE membership_id = v_membership_id;
  IF v_investor_id IS NULL THEN
    INSERT INTO investors (membership_id, person_id)
    VALUES (v_membership_id, p_person_id)
    RETURNING investor_id INTO v_investor_id;
  END IF;

  v_investment_id := app.record_investment(
    v_investor_id, ROUND(p_amount), p_roi_rate, p_interest_type, p_effective_date);

  IF p_profit_share_percent IS NOT NULL THEN
    UPDATE investments
       SET profit_share_percent = p_profit_share_percent,
           profit_share_effective_date = p_effective_date
     WHERE investment_id = v_investment_id;
  END IF;

  RETURN json_build_object(
    'membership_id', v_membership_id,
    'investor_id', v_investor_id,
    'investment_id', v_investment_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION app.attach_investor_with_first_investment(
  uuid, bigint, numeric, numeric, investment_interest_type_enum, date, numeric)
  TO authenticated, service_role;
