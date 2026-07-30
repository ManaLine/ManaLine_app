-- MANA LINE — the Owner is the business's first Agent
--
-- WHY: every operating area is worked by an agent (there is no "Owner-run"
-- mode). But an agent cannot be added to a business that does not exist
-- yet, so OW-000's setup wizard had no agent to assign an area to, and its
-- "assign agent" button was permanently disabled. The business could only
-- be started by marking areas Owner-run — the very concept being removed.
--
-- FIX: creating a business now also gives the creator an Agent membership
-- and an `agents` row, so there is always at least one agent from the first
-- second of a business's life. An Owner who walks a round is assigned to it
-- like anybody else; an Owner who does not can suspend or remove their own
-- Agent membership from OW-012's Members tab (only the Owner ROW is exempt
-- from that menu — the Agent row is not).
--
-- This is legal because uq_business_members_person_business_role is UNIQUE
-- (person_id, business_id, role), not (person_id, business_id) — one person
-- holding both Owner and Agent in one business is already the intended
-- design, and the existing production business already does exactly this.

-- --------------------------------------------------------------------
-- 1. Business creation seeds Owner + Agent.
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.create_business_with_owner(
  p_mlbi character varying,
  p_business_name character varying,
  p_registered_finance_name character varying,
  p_logo_url text DEFAULT NULL::text,
  p_business_type character varying DEFAULT NULL::character varying,
  p_business_address text DEFAULT NULL::text,
  p_business_phone character varying DEFAULT NULL::character varying,
  p_business_email character varying DEFAULT NULL::character varying
)
RETURNS TABLE(business_id uuid, mlbi character varying)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_person_id     BIGINT := app.current_person_id();
  v_business_id   UUID;
  v_agent_member  UUID;
BEGIN
  IF v_person_id IS NULL THEN
    RAISE EXCEPTION 'No authenticated person_id in JWT claims';
  END IF;

  INSERT INTO businesses (
    mlbi, owner_person_id, business_name, registered_finance_name,
    logo_url, business_type, business_address, business_phone, business_email
  ) VALUES (
    p_mlbi, v_person_id, p_business_name, p_registered_finance_name,
    p_logo_url, p_business_type, p_business_address, p_business_phone, p_business_email
  )
  RETURNING businesses.business_id INTO v_business_id;

  -- The creator is always the Owner, always Active immediately — no
  -- invitation/acceptance step applies to self-registration (BR-185:
  -- exactly one Owner per business).
  INSERT INTO business_members (
    person_id, business_id, role, membership_status,
    verification_status, onboarding_method, joined_at
  ) VALUES (
    v_person_id, v_business_id, 'Owner', 'Active',
    'Not Required', 'Direct Registration', now()
  );

  -- ...and the business's first Agent, so an operating area can be
  -- assigned to somebody from day one. Same person, separate membership.
  INSERT INTO business_members (
    person_id, business_id, role, membership_status,
    verification_status, onboarding_method, joined_at
  ) VALUES (
    v_person_id, v_business_id, 'Agent', 'Active',
    'Not Required', 'Direct Registration', now()
  )
  RETURNING membership_id INTO v_agent_member;

  -- An Agent membership WITHOUT a matching agents row is invisible to
  -- every agent picker in the app (they all join through agents), so the
  -- two are always written together. See the backfill below — production
  -- already had one membership in exactly that broken state.
  INSERT INTO agents (membership_id, person_id, joined_date)
  VALUES (v_agent_member, v_person_id, CURRENT_DATE);

  RETURN QUERY SELECT v_business_id, p_mlbi;
END;
$function$;

-- --------------------------------------------------------------------
-- 2. Backfill: Agent memberships with no agents row.
--
-- Found in production: the owner of "sri tirumala finance" held an Active
-- Agent membership with no agents row, so they could never be picked to
-- work an area despite being listed as an agent. Fixes that class of row
-- wherever it exists, not just the one instance.
-- --------------------------------------------------------------------
INSERT INTO agents (membership_id, person_id, joined_date)
SELECT bm.membership_id, bm.person_id, COALESCE(bm.joined_at::date, CURRENT_DATE)
FROM business_members bm
LEFT JOIN agents a ON a.membership_id = bm.membership_id
WHERE bm.role = 'Agent'
  AND a.agent_id IS NULL;

-- --------------------------------------------------------------------
-- 3. Backfill: businesses whose owner has no Agent membership yet.
--    Gives every existing business the same day-one agent a new business
--    now gets, so areas are assignable everywhere.
-- --------------------------------------------------------------------
WITH inserted AS (
  INSERT INTO business_members (
    person_id, business_id, role, membership_status,
    verification_status, onboarding_method, joined_at
  )
  SELECT b.owner_person_id, b.business_id, 'Agent', 'Active',
         'Not Required', 'Direct Registration', now()
  FROM businesses b
  WHERE NOT EXISTS (
    SELECT 1 FROM business_members bm
    WHERE bm.business_id = b.business_id
      AND bm.person_id = b.owner_person_id
      AND bm.role = 'Agent'
  )
  RETURNING membership_id, person_id
)
INSERT INTO agents (membership_id, person_id, joined_date)
SELECT membership_id, person_id, CURRENT_DATE FROM inserted;
