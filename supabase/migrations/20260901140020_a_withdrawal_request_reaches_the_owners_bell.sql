-- An investor asked to withdraw Rs 2,00,000 and the Owner's bell said
-- "Nothing is waiting on you". A second request had been sitting there since
-- the previous evening.
--
-- my_inbox_actions carried approvals, invitations and settlements. Withdrawal
-- requests were never a branch, so the only way to find one was to already
-- know it existed and open Withdrawal Requests from the Investor quick
-- actions. That is the same gap settlements had, fixed the same way.
--
-- Scoped explicitly, like the settlement branch: investment_withdrawal_requests
-- has no business_id of its own and reaches the business through its
-- investment.
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
