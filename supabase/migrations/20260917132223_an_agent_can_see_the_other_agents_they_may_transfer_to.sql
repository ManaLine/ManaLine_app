-- Who an Agent may send BF Cash to, listed rather than typed from memory.
--
-- THE FORM ASKED FOR AN AGENT ID. Two free-text boxes -- "To Agent Name" and
-- "To Agent ID" -- and the code beside them says what they were:
--
--     final _toAgentId = TextEditingController(); // stub picker
--
-- An agents.agent_id is a uuid. Nobody carries one, and nothing in the app
-- displays one, so BF Cash Transfer could not be completed by a person.
-- Reported from a handset: "show search results only existing agents in the
-- business and remove agent id user entry, just name & amount enough."
--
-- THE SAME RESOLUTION app.initiate_cash_transfer USES, deliberately. That
-- function finds the caller's own agent row with
--
--     WHERE bm.person_id = app.current_person_id()
--       AND bm.role = 'Agent' AND bm.membership_status = 'Active' LIMIT 1
--
-- and refuses a transfer whose target is in a different business. If this
-- list resolved the caller's business any other way, the picker could offer
-- somebody the transfer would then refuse. Copied exactly so the two cannot
-- disagree.
--
-- WORTH RECORDING, NOT FIXED HERE: that LIMIT 1 is arbitrary for somebody who
-- is an active Agent of TWO businesses -- the transfer comes from whichever
-- row the planner returns first. This function inherits the same ambiguity on
-- purpose, because a picker that showed a different business's agents than
-- the transfer would use is worse than one that is consistently uncertain.
-- Fixing it means passing a business explicitly through both, which is a
-- signature change to a money RPC and belongs in its own migration.
--
-- Self is excluded, because initiate_cash_transfer raises 23514 on it -- an
-- option that cannot work has no business being offered.

CREATE OR REPLACE FUNCTION app.transferable_agents()
RETURNS TABLE(
  agent_id      uuid,
  full_name     character varying,
  mlid          character varying,
  bf_current    numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_from_agent_id UUID;
  v_business_id   UUID;
BEGIN
  SELECT a.agent_id, bm.business_id
    INTO v_from_agent_id, v_business_id
  FROM agents a
  JOIN business_members bm ON bm.membership_id = a.membership_id
  WHERE bm.person_id = app.current_person_id()
    AND bm.role = 'Agent'
    AND bm.membership_status = 'Active'
  LIMIT 1;

  IF v_from_agent_id IS NULL THEN
    RAISE EXCEPTION 'Caller is not an agent' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT a.agent_id,
         p.full_name,
         p.mlid,
         -- What they are holding, so a transfer is aimed at somebody who
         -- needs it rather than at whoever is first alphabetically.
         COALESCE((SELECT ab.agent_bf_current
                     FROM agent_bf_assignments ab
                    WHERE ab.membership_id = bm.membership_id
                    ORDER BY ab.business_date DESC NULLS LAST
                    LIMIT 1), 0)
    FROM agents a
    JOIN business_members bm ON bm.membership_id = a.membership_id
    JOIN persons p ON p.person_id = bm.person_id
   WHERE bm.business_id = v_business_id
     AND bm.role = 'Agent'
     AND bm.membership_status = 'Active'
     AND a.agent_id <> v_from_agent_id
   ORDER BY p.full_name;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.transferable_agents() TO anon, authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'transferable_agents';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'transferable_agents has % overloads', v_n;
  END IF;
END $$;
