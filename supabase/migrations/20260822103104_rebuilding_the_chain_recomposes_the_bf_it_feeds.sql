-- Rebuilding the ledger chain must also recompose BF.
--
-- BF is derived from the chain -- app.recompute_business_bf reads the latest
-- day_ledger closing and subtracts what the agents hold. But nothing called it
-- after a rebuild, so the two drifted apart in ordinary use: record_collection
-- adds each payment straight onto owner_bf_balance (and onto the agent's
-- agent_bf_current), while the ledger is recomputed from source rows. Two ways
-- of counting the same cash, only one of them derived.
--
-- Found on the sri satyanarayana migration: after replaying 250 historical
-- instalments the stored owner_bf_balance read Rs 35,15,000 against a derived
-- Rs 33,97,400 -- Rs 1,17,600 apart, in the direction that flatters the till.
-- Page 6 would have rebuilt the chain and still left that figure standing,
-- because record_opening_snapshot calls recompute_ledger_chain and nothing
-- else.
--
-- One call, at the end, where the chain is finished and the closing it feeds
-- on is final. recompute_business_bf recomputes every agent first and nets
-- them off, so this covers agent BF too.
--
-- Signature unchanged, so CREATE OR REPLACE is safe here -- a changed
-- parameter list would need DROP first or PostgREST answers 300 on the
-- overload pair.
CREATE OR REPLACE FUNCTION app.recompute_ledger_chain(p_business_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_date DATE;
BEGIN
    FOR v_date IN
        SELECT business_date FROM day_ledger
         WHERE business_id = p_business_id
         ORDER BY business_date
    LOOP
        PERFORM app.recompute_day_ledger(p_business_id, v_date);
    END LOOP;

    -- The chain is what BF is derived from. Recomposing one without the other
    -- is what let them drift.
    PERFORM app.recompute_business_bf(p_business_id);
END;
$function$;
