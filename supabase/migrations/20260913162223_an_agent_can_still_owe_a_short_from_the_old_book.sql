-- The one agent figure that survives the handover.
--
-- The Owner's own words, when attendance came out of the migration path:
-- "till then their salaries & sadar is paid off and it's owner entry, make
-- sure short of an agent is recorded if any." Everything else about an agent's
-- past is settled history. A SHORT is not: it is money the agent owes the
-- business on the day the book changes hands, and it is still live.
--
-- Why it cannot be expressed with what already exists:
--
--   app.recompute_agent_bf filters EVERY source by `business_date > v_span`.
--   A row dated before the migration cutoff is deliberately invisible to it,
--   and a row dated after it would be a lie about when the money went missing.
--
--   app.agent_payable_salary derives a short from account_settlements with
--   `difference < 0`, joined to the account period it belongs to. A
--   pre-existing business has no settlements at all, and fabricating one would
--   also feed agent_bf_handed_over back into recompute_agent_bf -- inventing
--   a handover that never happened.
--
-- So this is a DECLARED OPENING POSITION, the same shape as
-- businesses.opening_bf_declared_amount and chetis.opening_instalments_paid:
-- a figure the Owner states once about the world before the app, which the
-- derived machinery then reads but never recomputes.
--
-- It lives on agents rather than in a new table because the two policies that
-- table would need already exist there: agents_owner_all lets the Owner
-- declare it, and agents_self_select lets the AGENT read what they are
-- recorded as owing. A short the agent cannot see is how a deduction becomes
-- an argument.
ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS opening_short_declared_amount DECIMAL(14,0) NULL,
    ADD COLUMN IF NOT EXISTS opening_short_declared_on     DATE NULL,
    ADD COLUMN IF NOT EXISTS opening_short_cleared_on      DATE NULL;

COMMENT ON COLUMN agents.opening_short_declared_amount IS
  'Money this agent owed the business when its book was migrated into the app. '
  'Declared once by the Owner, never derived. NULL means none was declared, '
  'which is not the same as zero.';
COMMENT ON COLUMN agents.opening_short_cleared_on IS
  'The day the Owner recorded this opening short as recovered. While NULL the '
  'amount is still outstanding and app.agent_payable_salary keeps reporting it.';

-- Declaring it, and clearing it, are the Owner's calls.
--
-- An RPC rather than a client UPDATE because clearing must not be able to
-- happen by writing a smaller number over the declaration: the amount owed and
-- the fact it was recovered are two separate records, and overwriting the
-- first would erase the evidence for the second.
CREATE OR REPLACE FUNCTION app.declare_agent_opening_short(
    p_agent_id UUID,
    p_amount   NUMERIC,
    p_declared_on DATE DEFAULT NULL
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
DECLARE
    v_membership_id UUID;
    v_business_id   UUID;
    v_amount        NUMERIC(14,0);
BEGIN
    SELECT a.membership_id INTO v_membership_id FROM agents a WHERE a.agent_id = p_agent_id;
    IF v_membership_id IS NULL THEN
        RAISE EXCEPTION 'Agent not found' USING ERRCODE = 'P0002';
    END IF;

    SELECT bm.business_id INTO v_business_id
      FROM business_members bm WHERE bm.membership_id = v_membership_id;

    IF NOT app.is_owner(v_business_id) THEN
        RAISE EXCEPTION 'Only the owner may declare an opening short'
            USING ERRCODE = '42501';
    END IF;

    -- Whole rupees, like every other money column here.
    v_amount := CEIL(COALESCE(p_amount, 0));

    IF v_amount < 0 THEN
        RAISE EXCEPTION 'A short is an amount owed, so it cannot be negative'
            USING ERRCODE = '22023';
    END IF;

    -- Zero is how an Owner takes back a figure they entered by mistake, and
    -- it must clear the declaration rather than record a debt of nothing.
    IF v_amount = 0 THEN
        UPDATE agents
           SET opening_short_declared_amount = NULL,
               opening_short_declared_on     = NULL,
               opening_short_cleared_on      = NULL
         WHERE agent_id = p_agent_id;
        RETURN 0;
    END IF;

    UPDATE agents
       SET opening_short_declared_amount = v_amount,
           opening_short_declared_on     = COALESCE(p_declared_on, CURRENT_DATE),
           -- Re-declaring an amount reopens it. An Owner correcting the figure
           -- upward after marking it recovered means it was not recovered.
           opening_short_cleared_on      = NULL
     WHERE agent_id = p_agent_id;

    RETURN v_amount;
END;
$$;

CREATE OR REPLACE FUNCTION app.clear_agent_opening_short(
    p_agent_id UUID,
    p_cleared_on DATE DEFAULT NULL
) RETURNS DATE
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $$
DECLARE
    v_membership_id UUID;
    v_business_id   UUID;
    v_amount        NUMERIC(14,0);
    v_day           DATE;
BEGIN
    SELECT a.membership_id, a.opening_short_declared_amount
      INTO v_membership_id, v_amount
      FROM agents a WHERE a.agent_id = p_agent_id;
    IF v_membership_id IS NULL THEN
        RAISE EXCEPTION 'Agent not found' USING ERRCODE = 'P0002';
    END IF;

    SELECT bm.business_id INTO v_business_id
      FROM business_members bm WHERE bm.membership_id = v_membership_id;

    IF NOT app.is_owner(v_business_id) THEN
        RAISE EXCEPTION 'Only the owner may clear an opening short'
            USING ERRCODE = '42501';
    END IF;

    IF v_amount IS NULL THEN
        RAISE EXCEPTION 'This agent has no opening short to clear'
            USING ERRCODE = 'P0002';
    END IF;

    v_day := COALESCE(p_cleared_on, CURRENT_DATE);

    UPDATE agents
       SET opening_short_cleared_on = v_day
     WHERE agent_id = p_agent_id;

    RETURN v_day;
END;
$$;

GRANT EXECUTE ON FUNCTION app.declare_agent_opening_short(UUID, NUMERIC, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION app.clear_agent_opening_short(UUID, DATE) TO authenticated;
