-- =============================================================================
-- app.my_inbox_actions — the two things that need a decision from you
-- =============================================================================
-- Invitations were scattered across OW-002, OW-003, OW-012, LR-012, CW-002 and
-- IW-002, with no single place to see what was waiting. This is the data
-- behind one shared Notifications inbox.
--
-- TWO OPPOSITE DIRECTIONS, and the schema already distinguishes them:
--   'approval'   membership_requests.status = 'Pending'
--                someone asked to join a business YOU own -> approve/reject
--   'invitation' business_members.membership_status = 'Pending Invitation'
--                a business added YOU and is waiting -> accept/decline
-- They are grouped separately in the UI because the verbs differ. Merging them
-- into one list would put "Approve" and "Accept" side by side meaning
-- different things to different people.
--
-- SECURITY INVOKER. membership_requests_owner_all already scopes approvals to
-- businesses you own, and business_members_self_select scopes invitations to
-- you. RLS decides; this function does not re-implement permissions. Same
-- reasoning as app.ledger_history.
--
-- NOT COPIED INTO notifications, deliberately. Writing a row per request would
-- need a trigger and would go stale the moment the request is approved
-- elsewhere — an inbox insisting something is pending after it was decided is
-- worse than no inbox. These are read live; the notifications table stays the
-- read-only feed beside them.
--
-- Verified inside a rolled-back DO block with one row of each kind seeded:
-- returned approval/Investor/Sunitha Sharma and invitation/Owner/(me).
CREATE OR REPLACE FUNCTION app.my_inbox_actions()
RETURNS TABLE (
  kind          TEXT,
  item_id       UUID,
  business_id   UUID,
  business_name TEXT,
  person_name   TEXT,
  role          TEXT,
  amount        NUMERIC,
  created_at    TIMESTAMP
)
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
  -- Requests awaiting MY approval, as an Owner.
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

  ORDER BY 8 DESC;
$function$;

COMMENT ON FUNCTION app.my_inbox_actions() IS
  'Actionable items for the Notifications inbox: membership requests awaiting your approval as an Owner, and invitations awaiting your acceptance. SECURITY INVOKER — RLS scopes both. Read live rather than copied into notifications, so nothing can claim pending after a decision.';

GRANT EXECUTE ON FUNCTION app.my_inbox_actions() TO authenticated;
