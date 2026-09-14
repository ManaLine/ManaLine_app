-- A person is often two things at once, and the app made you say so twice.
--
-- The schema has always allowed it: business_members is UNIQUE on
-- (person_id, business_id, role), one row per role, and six people in this
-- production database already hold more than one. What was missing is a way to
-- SAY it in a single action. attach_person_to_business takes exactly one role,
-- so adding somebody as Agent and Customer meant two calls from the client --
-- and a failure on the second leaves a person who is an Agent but not a
-- Customer, with nothing on screen saying so. A half-made membership surfaces
-- weeks later as "why can't he collect".
--
-- THIS DELEGATES RATHER THAN DUPLICATING. It calls
-- app.attach_person_to_business once per role instead of copying its body.
-- That body is where the real rules live -- Customer goes straight to Active
-- while Agent and Investor go to Pending Invitation, the customers row is
-- created only for the role that is live immediately, re-adding a removed
-- member asks again -- and a second copy of those rules is how two paths end
-- up disagreeing about what adding somebody means. A plpgsql function's calls
-- run inside its own transaction, so the loop is all-or-nothing for free:
-- a failure on the third role rolls back the first two.
--
-- The ownership check inside attach_person_to_business runs on every
-- iteration. That is deliberate and not worth optimising away; it is the same
-- check, and skipping it here would mean this function trusting itself.
CREATE OR REPLACE FUNCTION app.attach_person_to_business_roles(
    p_business_id UUID,
    p_person_id   BIGINT,
    p_roles       TEXT[]
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $$
DECLARE
    v_roles   TEXT[];
    v_role    TEXT;
    v_results JSON[] := '{}';
BEGIN
    IF p_roles IS NULL OR cardinality(p_roles) = 0 THEN
        RAISE EXCEPTION 'Choose at least one role.' USING ERRCODE = '22023';
    END IF;

    -- Deduplicated, and ordered so the answer reads the same way twice.
    SELECT array_agg(DISTINCT r ORDER BY r) INTO v_roles
      FROM unnest(p_roles) AS r;

    -- Checked BEFORE anything is written. The transaction would roll back a
    -- bad third role anyway, but the message is better when it names the
    -- problem instead of reporting a failure halfway through.
    FOREACH v_role IN ARRAY v_roles LOOP
        IF v_role NOT IN ('Agent', 'Investor', 'Customer') THEN
            RAISE EXCEPTION 'Invalid role -- must be Agent, Investor or Customer.'
                USING ERRCODE = '22023';
        END IF;
    END LOOP;

    FOREACH v_role IN ARRAY v_roles LOOP
        v_results := v_results
            || app.attach_person_to_business(p_business_id, p_person_id, v_role);
    END LOOP;

    RETURN array_to_json(v_results);
END;
$$;

GRANT EXECUTE ON FUNCTION app.attach_person_to_business_roles(UUID, BIGINT, TEXT[])
    TO authenticated;
