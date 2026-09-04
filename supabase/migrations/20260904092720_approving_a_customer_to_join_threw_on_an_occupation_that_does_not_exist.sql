-- Approving a Customer's request to join threw 22P02 every time.
--
--   invalid input value for enum occupation_enum: "Other"
--
-- occupation_enum is: Farmer | Milk Vendor | Auto Driver | Tea Shop | Tailor |
-- Daily Wage | Government Employee | Private Employee | Business | Housewife |
-- Student | Retired | Other-Custom.  There is no 'Other'.
--
-- app.register_new_customer had it right ('Other-Custom'), which is why every
-- other way of creating a customer works. decide_membership_request did not, so
-- the ONE path that goes through it -- an Owner approving a join request from a
-- Customer -- failed on its first call and every call after. The single
-- approval in this database's history that succeeded was an Investor, which
-- takes a different branch and never touches occupation.
--
-- Fourth instance of the same class: 'General', 'Self Request', 'Full Payment',
-- and now 'Other'. plpgsql bodies are not type-checked at CREATE time, so each
-- applied perfectly and threw on first use. Found by executing the whole
-- request-to-approve flow in a rolled-back transaction rather than by reading
-- the function.
--
-- AND ONE I WROTE MYSELF, in the migration immediately before this one:
-- respond_to_invitation copied the same literal out of decide_membership_request
-- with a comment claiming its values were "known-good" because that path is
-- "exercised in production". It is not exercised -- that branch had never once
-- succeeded. Copying a literal is not verifying it. Both are fixed below.
--
-- my_inbox_actions is also corrected here. Its approval branch was the only one
-- of four with no recipient filter: settlement and withdrawal both call
-- app.is_owner, invitation matches on current_person_id, and approval matched
-- on nothing. RLS kept it from leaking other businesses, but
-- membership_requests_self_select lets a person read their OWN request -- so
-- the requester saw their own pending request in their bell as an item to
-- approve, and pressing Approve called decide_membership_request, which throws
-- 'Only the Owner may decide'. The filter makes the four branches agree.
--
-- test/sql_enum_literal_guard_test.dart now checks this class statically.

CREATE OR REPLACE FUNCTION app.respond_to_invitation(
  p_membership_id uuid,
  p_accept boolean
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_person  bigint := app.current_person_id();
  v_row     business_members%ROWTYPE;
  v_new     membership_status_enum;
BEGIN
  IF v_person IS NULL THEN
    RAISE EXCEPTION 'Not signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row FROM business_members
   WHERE membership_id = p_membership_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'That invitation no longer exists.' USING ERRCODE = 'P0002';
  END IF;

  -- SECURITY DEFINER bypasses RLS, so ownership is checked here by hand. This
  -- is the line that stops somebody answering another person's invitation.
  IF v_row.person_id <> v_person THEN
    RAISE EXCEPTION 'That invitation belongs to somebody else.' USING ERRCODE = '42501';
  END IF;

  IF v_row.membership_status NOT IN ('Pending Invitation', 'Pending Acceptance') THEN
    RAISE EXCEPTION 'This invitation was already answered (%).', v_row.membership_status
      USING ERRCODE = '23514';
  END IF;

  v_new := CASE WHEN p_accept THEN 'Active' ELSE 'Removed' END::membership_status_enum;

  UPDATE business_members
     SET membership_status = v_new,
         joined_at = CASE WHEN p_accept THEN COALESCE(joined_at, now()) ELSE joined_at END
   WHERE membership_id = p_membership_id;

  -- The role-side entity every workspace reads with .single().
  IF p_accept THEN
    IF v_row.role = 'Agent' AND NOT EXISTS (
         SELECT 1 FROM agents WHERE membership_id = p_membership_id) THEN
      INSERT INTO agents (membership_id, person_id, joined_date, current_status)
      VALUES (p_membership_id, v_row.person_id, CURRENT_DATE, 'Active');
    ELSIF v_row.role = 'Customer' AND NOT EXISTS (
         SELECT 1 FROM customers WHERE membership_id = p_membership_id) THEN
      INSERT INTO customers (membership_id, person_id, occupation,
                             customer_status, customer_since)
      -- 'Other-Custom', not 'Other'. Copied wrong from decide_membership_request.
      VALUES (p_membership_id, v_row.person_id, 'Other-Custom', 'Active', CURRENT_DATE);
    ELSIF v_row.role = 'Investor' AND NOT EXISTS (
         SELECT 1 FROM investors WHERE membership_id = p_membership_id) THEN
      INSERT INTO investors (membership_id, person_id)
      VALUES (p_membership_id, v_row.person_id);
    END IF;
  END IF;

  -- verification_status is deliberately untouched. An accepted Agent or
  -- Investor stays 'Pending Verification', which is what sends LR-013 into the
  -- Role Escalation OTP (BR-191); auth-otp-verify sets it to 'Verified' there,
  -- as service_role. Marking it verified here would skip that step entirely.
  RETURN json_build_object(
    'membership_id',       p_membership_id,
    'business_id',         v_row.business_id,
    'role',                v_row.role,
    'membership_status',   v_new,
    'verification_status', v_row.verification_status
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION app.respond_to_invitation(uuid, boolean) TO anon, authenticated;

CREATE OR REPLACE FUNCTION app.decide_membership_request(
  p_request_id uuid,
  p_approve boolean,
  p_rejection_reason text DEFAULT NULL::text
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
DECLARE
  v_person_id BIGINT;
  v_business_id UUID;
  v_role business_member_role_enum;
  v_status membership_request_status_enum;
  v_membership_id UUID;
BEGIN
  SELECT mr.person_id, mr.business_id, mr.requested_role::text::business_member_role_enum,
         mr.status
    INTO v_person_id, v_business_id, v_role, v_status
    FROM membership_requests mr
   WHERE mr.request_id = p_request_id
   FOR UPDATE;

  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'No such request' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may decide a membership request'
      USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'Pending' THEN
    RAISE EXCEPTION 'This request has already been decided' USING ERRCODE = '23514';
  END IF;

  IF NOT p_approve THEN
    UPDATE membership_requests
       SET status = 'Rejected',
           rejection_reason = p_rejection_reason,
           reviewed_by_person_id = app.current_person_id(),
           reviewed_at = now(),
           -- The window request_join_business already checks for.
           cooldown_until = (now() AT TIME ZONE 'Asia/Kolkata') + INTERVAL '24 hours'
     WHERE request_id = p_request_id;

    INSERT INTO notifications (recipient_person_id, business_id,
                               notification_type, message,
                               related_entity_type, related_entity_uuid)
    VALUES (v_person_id, v_business_id, 'Owner Approval Confirmation',
            'Your request to join was not accepted. You can apply again after 24 hours.',
            'membership_request', p_request_id);

    RETURN json_build_object('status', 'rejected');
  END IF;

  SELECT membership_id INTO v_membership_id
    FROM business_members
   WHERE person_id = v_person_id AND business_id = v_business_id AND role = v_role;

  IF v_membership_id IS NULL THEN
    INSERT INTO business_members (
      person_id, business_id, role, membership_status, verification_status,
      onboarding_method, invited_by_person_id, joined_at
    ) VALUES (
      v_person_id, v_business_id, v_role, 'Active', 'Not Required',
      'ID Lookup', app.current_person_id(), now()
    ) RETURNING membership_id INTO v_membership_id;
  ELSE
    UPDATE business_members
       SET membership_status = 'Active', removed_at = NULL,
           joined_at = COALESCE(joined_at, now())
     WHERE membership_id = v_membership_id;
  END IF;

  IF v_role = 'Agent' AND NOT EXISTS (
       SELECT 1 FROM agents WHERE membership_id = v_membership_id) THEN
    INSERT INTO agents (membership_id, person_id, joined_date, current_status)
    VALUES (v_membership_id, v_person_id, CURRENT_DATE, 'Active');
  ELSIF v_role = 'Customer' AND NOT EXISTS (
       SELECT 1 FROM customers WHERE membership_id = v_membership_id) THEN
    -- 'Other-Custom', not 'Other'. This is the fix.
    INSERT INTO customers (membership_id, person_id, occupation,
                           customer_status, customer_since)
    VALUES (v_membership_id, v_person_id, 'Other-Custom', 'Active', CURRENT_DATE);
  ELSIF v_role = 'Investor' AND NOT EXISTS (
       SELECT 1 FROM investors WHERE membership_id = v_membership_id) THEN
    INSERT INTO investors (membership_id, person_id)
    VALUES (v_membership_id, v_person_id);
  END IF;

  UPDATE membership_requests
     SET status = 'Approved',
         reviewed_by_person_id = app.current_person_id(),
         reviewed_at = now()
   WHERE request_id = p_request_id;

  INSERT INTO notifications (recipient_person_id, business_id,
                             notification_type, message,
                             related_entity_type, related_entity_uuid)
  VALUES (v_person_id, v_business_id, 'Owner Approval Confirmation',
          'Your request to join was approved. Open the app to start.',
          'membership_request', p_request_id);

  RETURN json_build_object(
    'status', 'approved',
    'membership_id', v_membership_id,
    'role', v_role::text);
END;
$function$;

CREATE OR REPLACE FUNCTION app.my_inbox_actions()
RETURNS TABLE(kind text, item_id uuid, business_id uuid, business_name text,
              person_name text, role text, amount numeric,
              created_at timestamp without time zone)
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
  -- Requests awaiting MY approval, as an Owner.
  -- app.is_owner is the filter the other three branches always had. Without it
  -- the REQUESTER saw their own pending request here as something to approve,
  -- because membership_requests_self_select lets them read their own row.
  SELECT 'approval'::text,
         mr.request_id,
         mr.business_id,
         b.business_name::text,
         p.full_name::text,
         mr.requested_role::text,
         mr.proposed_investment_amount,
         mr.created_at
  FROM membership_requests mr
  JOIN businesses b ON b.business_id = mr.business_id
  JOIN persons p    ON p.person_id   = mr.person_id
  WHERE mr.status = 'Pending'
    AND app.is_owner(mr.business_id)

  UNION ALL

  -- Invitations awaiting MY acceptance, as the invited person.
  SELECT 'invitation'::text,
         bm.membership_id,
         bm.business_id,
         b.business_name::text,
         NULL,
         bm.role::text,
         NULL,
         bm.created_at
  FROM business_members bm
  JOIN businesses b ON b.business_id = bm.business_id
  WHERE bm.person_id = app.current_person_id()
    AND bm.membership_status IN ('Pending Invitation', 'Pending Acceptance')

  UNION ALL

  -- Settlements an Agent has handed me, as the Owner of that business.
  SELECT 'settlement'::text,
         s.settlement_id,
         ap.business_id,
         b.business_name::text,
         p.full_name::text,
         'Agent'::text,
         s.agent_bf_handed_over,
         s.submitted_at
  FROM account_settlements s
  JOIN account_periods ap ON ap.account_period_id = s.account_period_id
  JOIN businesses b       ON b.business_id = ap.business_id
  JOIN business_members bm ON bm.membership_id = ap.agent_membership_id
  JOIN persons p          ON p.person_id = bm.person_id
  WHERE s.status = 'Pending Owner Review'
    AND app.is_owner(ap.business_id)

  UNION ALL

  -- Money an Investor has asked to take out, as the Owner who has to pay it.
  SELECT 'withdrawal'::text,
         wr.request_id,
         inv.business_id,
         b.business_name::text,
         p.full_name::text,
         'Investor'::text,
         wr.requested_amount,
         wr.created_at
  FROM investment_withdrawal_requests wr
  JOIN investments inv ON inv.investment_id = wr.investment_id
  JOIN businesses b    ON b.business_id = inv.business_id
  JOIN investors i     ON i.investor_id = inv.investor_id
  JOIN persons p       ON p.person_id = i.person_id
  WHERE wr.status = 'Pending'
    AND inv.deleted_at IS NULL
    AND app.is_owner(inv.business_id)

  ORDER BY 8 DESC;
$function$;
