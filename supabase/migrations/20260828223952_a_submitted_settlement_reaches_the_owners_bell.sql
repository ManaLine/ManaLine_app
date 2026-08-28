-- The Agent submits, and the Owner is told.
--
-- my_inbox_actions carried membership requests and invitations and nothing
-- else, so a settlement sat in Pending Owner Review until the Owner happened
-- to open Account Review and look. An Agent who has handed over five lakhs
-- and is waiting to start the next round should not depend on that.
--
-- Note the first branch's shape is preserved: 'approval' rows are not scoped
-- to the caller's own businesses in the original either -- RLS on
-- membership_requests does that scoping. Settlements are scoped explicitly
-- here because account_settlements has no business_id of its own to filter
-- on; it reaches the business through its period.
CREATE OR REPLACE FUNCTION app.my_inbox_actions()
RETURNS TABLE(kind text, item_id uuid, business_id uuid, business_name text,
              person_name text, role text, amount numeric,
              created_at timestamp without time zone)
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

  UNION ALL

  -- Settlements an Agent has handed me, as the Owner of that business. The
  -- amount is what they are handing over, so the bell can say how much is
  -- waiting rather than only that something is.
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

  ORDER BY 8 DESC;
$function$;
