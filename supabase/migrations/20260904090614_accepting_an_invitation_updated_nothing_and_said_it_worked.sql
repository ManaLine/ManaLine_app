-- Accepting an invitation was a client-side UPDATE that RLS refused, silently.
--
-- inbox_service.respondToInvitation ran:
--     .from('business_members').update({membership_status: ...}).eq(membership_id)
--
-- business_members has exactly one policy an invited person matches, and it is
-- business_members_self_select -- SELECT only. The only ALL policy is the
-- Owner's. So the invited person could SEE the invitation (which is why it
-- appeared in the bell) and had no permission to change it.
--
-- PostgREST returns 200 for an UPDATE matching zero rows. The app read that as
-- success, reloaded the list, and the invitation was still sitting there. Two
-- agents on Sri Vigneswara Finance had been stuck on Pending Invitation since
-- 07:41 and 07:43 that morning with no error anywhere.
--
-- An RPC rather than a new RLS UPDATE policy, for two reasons:
--
--   1. It can say whether a row actually changed. A policy would leave the
--      same silent-200 shape in place for the next person to trip over.
--   2. A policy wide enough to accept an invitation is wide enough to
--      RE-activate a membership an Owner has Suspended or Removed. The status
--      check below is the whole point, and it belongs somewhere it cannot be
--      bypassed by a hand-written PostgREST call.
--
-- Every enum literal here was read out of enum_range first: membership_status_enum
-- is Pending Invitation | Pending Acceptance | Active | Temporarily Disabled |
-- Suspended | Removed | Pending Approval.

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
     SET membership_status = v_new
   WHERE membership_id = p_membership_id;

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
