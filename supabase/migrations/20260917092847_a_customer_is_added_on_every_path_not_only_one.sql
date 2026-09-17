-- A Customer is ADDED. That rule lived in one function and two screens went
-- on asking them to accept an invitation.
--
-- 20260911211146 set the Owner's rule in app.attach_person_to_business: an
-- Agent or an Investor gets reach into somebody else's book so both are
-- asked, a Customer is being recorded and is simply in. It fixed the
-- function. It did not look for the other writers.
--
-- There were two, both in Dart, both inserting into business_members
-- directly with 'Pending Invitation' hardcoded for every role:
--
--   BusinessManagementService.addExistingMember       ("Add Existing Member")
--   BusinessManagementService.decideMembershipRequest (approving a request)
--
-- FOUND FROM A HANDSET, on a screenshot: "if Ashok is a customer why
-- invitation sent to him". Ashok Goud, MLPI100000026, added to Sri Durga
-- Finance as a Customer by ID Lookup on 2026-09-11 at 18:32 -- two hours and
-- forty minutes BEFORE the migration above, and by the path it never
-- touched, so the row is not residue. That path is still live today.
--
-- One row out of ninety customer memberships, which is why nothing else
-- noticed. The other eighty-nine came through the RPC.
--
-- AND THE HALF NOBODY SAW. A direct INSERT makes a membership and nothing
-- else, so Ashok has no `customers` row either -- he is a Customer of that
-- book who cannot be lent to, because a loan needs a customer_id. The RPC
-- creates that row in the same statement. Both live Customer memberships
-- missing one came in by 'ID Lookup'; the other was removed long ago and is
-- left alone.
--
-- THE FIX IS NOT TO COPY THE RULE INTO DART. It is to stop having a second
-- writer: both screens call this RPC now, which is why it gains the one
-- thing that kept them from being able to -- the onboarding method they each
-- need to record. 'Migration/Pre-Existing' is the default, so the two
-- existing three-argument callers (app.attach_person_to_business_roles and
-- the global add-person flow) are unchanged.
--
-- DROP THEN CREATE, not CREATE OR REPLACE: the parameter list changes, and a
-- defaulted fourth parameter creates a SECOND function whose PostgREST
-- answer is HTTP 300. Overload count asserted at the bottom.

DROP FUNCTION IF EXISTS app.attach_person_to_business(uuid, bigint, text);

CREATE FUNCTION app.attach_person_to_business(
  p_business_id       uuid,
  p_person_id         bigint,
  p_role              text,
  p_onboarding_method text DEFAULT 'Migration/Pre-Existing'
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
DECLARE
  v_role          business_member_role_enum;
  v_membership_id uuid;
  v_status        membership_status_enum;
  v_method        onboarding_method_enum;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Only the Owner may add a member to this business.'
      USING ERRCODE = '42501';
  END IF;

  IF p_role NOT IN ('Agent', 'Investor', 'Customer') THEN
    RAISE EXCEPTION 'Invalid role - must be Agent, Investor or Customer.'
      USING ERRCODE = '22023';
  END IF;
  v_role := p_role::business_member_role_enum;

  -- Read out of enum_range, not guessed: onboarding_method_enum is
  -- ('Direct Registration','ID Lookup','Migration/Pre-Existing'). Checked
  -- here rather than left to the cast, so a wrong method is a sentence and
  -- not 22P02 out of the middle of an INSERT.
  IF p_onboarding_method NOT IN
     ('Direct Registration', 'ID Lookup', 'Migration/Pre-Existing') THEN
    RAISE EXCEPTION 'Invalid onboarding method: %', p_onboarding_method
      USING ERRCODE = '22023';
  END IF;
  v_method := p_onboarding_method::onboarding_method_enum;

  -- Read out of enum_range, not guessed: membership_status_enum is
  -- ('Pending Invitation','Pending Acceptance','Active','Temporarily
  -- Disabled','Suspended','Removed','Pending Approval').
  v_status := CASE WHEN v_role = 'Customer'
                   THEN 'Active'
                   ELSE 'Pending Invitation'
              END::membership_status_enum;

  SELECT membership_id INTO v_membership_id
    FROM business_members
   WHERE person_id = p_person_id AND business_id = p_business_id AND role = v_role
   FOR UPDATE;

  IF v_membership_id IS NULL THEN
    INSERT INTO business_members (
      person_id, business_id, role, membership_status, verification_status,
      onboarding_method, invited_by_person_id, joined_at
    ) VALUES (
      p_person_id, p_business_id, v_role, v_status,
      (CASE WHEN v_role = 'Customer' THEN 'Not Required'
            ELSE 'Pending Verification' END)::membership_verification_status_enum,
      v_method, app.current_person_id(),
      -- Nobody has joined anything until they say yes.
      CASE WHEN v_role = 'Customer' THEN now() ELSE NULL END
    ) RETURNING membership_id INTO v_membership_id;
  ELSE
    -- Re-adding somebody who was removed asks again, for the same reason.
    UPDATE business_members
       SET membership_status = v_status, removed_at = NULL,
           joined_at = CASE WHEN v_role = 'Customer'
                            THEN COALESCE(joined_at, now()) ELSE joined_at END
     WHERE membership_id = v_membership_id;
  END IF;

  -- The role-side row is created here ONLY for the role that is active
  -- immediately. An Agent or Investor who has not accepted yet gets theirs
  -- from respond_to_invitation, which is the moment they become real.
  IF v_role = 'Customer' AND NOT EXISTS (
      SELECT 1 FROM customers WHERE membership_id = v_membership_id) THEN
    INSERT INTO customers (membership_id, person_id, occupation,
                           customer_status, customer_since)
    VALUES (v_membership_id, p_person_id, 'Other-Custom', 'Active', CURRENT_DATE);
  END IF;

  RETURN json_build_object(
    'membership_id',     v_membership_id,
    'role',              v_role::text,
    'membership_status', v_status::text
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION app.attach_person_to_business(uuid, bigint, text, text)
  TO anon, authenticated;

-- THE ROWS THE TWO DART PATHS LEFT BEHIND.
--
-- Written as a rule rather than as Ashok's membership_id, because the defect
-- ran for six days and a hand-picked id repairs whatever was true the
-- afternoon somebody looked. A Customer is Active by the Owner's rule, so a
-- Customer sitting at Pending Invitation is one of these and nothing else --
-- no other path can produce one.
--
-- Removed and Suspended are left exactly as they are: those are decisions
-- somebody made, and this is not entitled to overturn them.
UPDATE business_members
   SET membership_status = 'Active',
       joined_at = COALESCE(joined_at, now())
 WHERE role = 'Customer'
   AND membership_status IN ('Pending Invitation', 'Pending Acceptance');

-- And the customers row a direct INSERT never made. Restricted to memberships
-- that are Active now: a Removed customer with no row is a removed customer,
-- and giving them one would put somebody back on a book they are off.
INSERT INTO customers (membership_id, person_id, occupation,
                       customer_status, customer_since)
SELECT bm.membership_id, bm.person_id, 'Other-Custom', 'Active', CURRENT_DATE
  FROM business_members bm
 WHERE bm.role = 'Customer'
   AND bm.membership_status = 'Active'
   AND NOT EXISTS (SELECT 1 FROM customers c WHERE c.membership_id = bm.membership_id);

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'attach_person_to_business';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'attach_person_to_business has % overloads; PostgREST answers 300 with more than one', v_n;
  END IF;
END $$;
