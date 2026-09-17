-- An Agent's BF request was a notice, not a decision.
--
-- app.request_agent_bf writes a notification -- "Karri Manikanta has asked
-- for BF of 9800. They cannot issue loans until it is granted." -- and it
-- reaches the Owner's bell. Then it stops. app.my_inbox_actions had four
-- kinds and this was not one of them, so the only thing the Owner could do
-- with it was Ignore or Close. Reported from a handset, with the screenshot:
-- "add a react before ignore - which leads to proper action that user needs
-- to take ... app should drive user accordingly."
--
-- An agent sitting at zero float cannot issue a single loan, and the person
-- who can unblock them was being shown a sentence with two dismiss buttons.
--
-- THE FIFTH KIND, not a button bolted onto a notice. The inbox already has
-- the shape for "somebody is waiting on your decision" -- approvals,
-- invitations, settlements, withdrawals -- and this is that, exactly. It
-- gets the same card, the same badge count, and the same two answers.
--
-- app.decide_agent_bf_request already exists and already grants the float on
-- approval, so nothing new decides anything; this only makes the decision
-- reachable.
--
-- InboxActionKind.fromWire THROWS on a kind it does not know, deliberately --
-- "a row the app cannot act on is a row somebody is waiting behind". So this
-- migration and lib/shared/inbox_service.dart ship together or the inbox
-- stops loading.
--
-- CREATE OR REPLACE, and the rule in CLAUDE.md is satisfied rather than
-- skipped: my_inbox_actions takes NO parameters and its RETURNS TABLE is
-- unchanged -- same eight columns, same types, same order. The new branch is
-- a UNION ALL inside the body. Overload count asserted below anyway.

CREATE OR REPLACE FUNCTION app.my_inbox_actions()
 RETURNS TABLE(kind text, item_id uuid, business_id uuid, business_name text, person_name text, role text, amount numeric, created_at timestamp without time zone)
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

  UNION ALL

  -- Float an Agent has asked me for, as the Owner who holds the till.
  --
  -- The amount is what they asked for. app.decide_agent_bf_request takes a
  -- decided amount separately, so an Owner may grant less than was asked --
  -- but this row reports the ASK, because that is what is waiting.
  SELECT 'bf_request'::text,
         r.request_id,
         r.business_id,
         b.business_name::text,
         p.full_name::text,
         'Agent'::text,
         r.requested_amount,
         r.created_at
  FROM agent_bf_requests r
  JOIN businesses b        ON b.business_id = r.business_id
  JOIN business_members bm ON bm.membership_id = r.membership_id
  JOIN persons p           ON p.person_id = bm.person_id
  WHERE r.status = 'Pending'
    AND app.is_owner(r.business_id)

  ORDER BY 8 DESC;
$function$;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'my_inbox_actions';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'my_inbox_actions has % overloads', v_n;
  END IF;
END $$;
