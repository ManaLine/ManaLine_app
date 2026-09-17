-- Ask about the float BEFORE the loan, and answer according to who is asking.
--
-- TWO FINDINGS, ONE CAUSE. Reported from a handset on the Stf book:
--
--   "why letting user to fill all the details and then showing error"
--   "owner tried to issue loan with BF 0, app asked to send request -- it's a
--    blunder, according to role app should behave"
--
-- app.create_loan_with_bf_check is the only thing that knew the float, and it
-- is a WRITE: it takes a live photo URL, so the only way to learn the answer
-- was to walk six steps, photograph the customer, and be refused. And the
-- refusal handed everybody the same remedy -- the Agent's remedy, a request to
-- the Owner -- which, for the Owner, is a request to themselves.
--
-- This is the read-only half. It answers the same question the write asks,
-- from the same rows, and nothing acts on it: STABLE, no INSERT, no UPDATE.
--
-- WHOSE FLOAT. The check is against the COLLECTION AGENT'S float, not the
-- Owner's till, and that is correct and stays -- the cash physically leaves
-- the collecting agent's hand. What was wrong was never the sum; it was the
-- timing and the remedy. So this returns BOTH figures, because the remedy
-- depends on the second one:
--
--   viewer is the Owner, business has the money -> top the agent up
--                        (app.grant_agent_bf, which already exists)
--   viewer is the Owner, business has no money  -> nobody to ask. The
--                        business itself is empty, and cash enters a book
--                        through an investor deposit, a collection, or the
--                        declared opening BF.
--   viewer is an Agent                          -> request it from the Owner
--                        (app.request_agent_bf, already wired)
--
-- On Stf on 2026-09-17 both figures were 0 and the Owner was the collecting
-- agent, which is how the app came to offer somebody a request to themselves.
--
-- has_assignment is separate from a zero float on purpose. An agent with no
-- agent_bf_assignments row at all has never been given an opening figure --
-- app.ensure_agent_bf_assignment is what makes one -- and "you have not been
-- set up yet" is a different sentence from "you have spent it".

CREATE OR REPLACE FUNCTION app.loan_float_position(
  p_business_id                    uuid,
  p_collection_agent_membership_id uuid
) RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_is_owner       BOOLEAN;
  v_agent_bf       DECIMAL(14,0);
  v_has_assignment BOOLEAN;
  v_business_bf    DECIMAL(14,0);
BEGIN
  v_is_owner := app.is_owner(p_business_id);

  -- The same authorization the write uses, minus the permission bit: this
  -- tells you how much money there is, so an Owner or any active agent of
  -- the business may ask, and nobody else may.
  IF NOT v_is_owner AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to read this business''s float'
      USING ERRCODE = '42501';
  END IF;

  -- The same row app.create_loan_with_bf_check locks and compares against,
  -- selected the same way. Two orderings would be two answers.
  SELECT agent_bf_current, TRUE INTO v_agent_bf, v_has_assignment
    FROM agent_bf_assignments
   WHERE membership_id = p_collection_agent_membership_id
   ORDER BY business_date DESC NULLS LAST
   LIMIT 1;

  SELECT owner_bf_balance INTO v_business_bf
    FROM businesses WHERE business_id = p_business_id;

  RETURN json_build_object(
    'agent_available',  COALESCE(v_agent_bf, 0),
    'has_assignment',   COALESCE(v_has_assignment, FALSE),
    'business_bf',      COALESCE(v_business_bf, 0),
    'viewer_is_owner',  v_is_owner
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION app.loan_float_position(uuid, uuid) TO anon, authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'loan_float_position';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'loan_float_position has % overloads', v_n;
  END IF;
END $$;
