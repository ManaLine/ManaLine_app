-- What a day opened and closed on, for whoever is looking.
--
-- History showed a day as a NET: collections less disbursements, which on any
-- lending day is negative and reads as a loss. A day does not start at zero --
-- it starts on the cash carried into it. Opening BF, then the ins and outs,
-- and the figure at the end is a balance rather than a swing.
--
-- The two askers need different answers and neither is a running total:
--
--   OWNER  -- day_ledger already holds opening_balance and closing_balance per
--            day, recomputed from source rows. It is authoritative and is read
--            straight out.
--
--   AGENT  -- an agent's float is NOT stored per day. agent_bf_assignments
--            holds one row saying what they hold NOW. So it is derived here
--            the same way recompute_agent_bf derives the current figure, but
--            summed by day: grants and collections in, loans, expenses, cheti
--            and handovers out, confirmed transfers both ways. Anything at or
--            before migrated_through_date is excluded, because the declared
--            book already accounts for it -- the same cut the float itself
--            uses.
--
-- Returned as a range rather than per day so a screen paging through a month
-- asks once. Authoritative either way, so a part-loaded day still shows the
-- right balance: the events are the detail, these two numbers are the truth.
CREATE OR REPLACE FUNCTION app.ledger_day_balances(
  p_business_id uuid,
  p_from date,
  p_to date,
  p_membership_id uuid DEFAULT NULL
) RETURNS TABLE(business_date date, opening numeric, closing numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_span date;
BEGIN
  IF NOT (app.is_owner(p_business_id) OR app.is_active_agent(p_business_id)) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  IF p_membership_id IS NULL THEN
    RETURN QUERY
      SELECT d.business_date, d.opening_balance, d.closing_balance
        FROM day_ledger d
       WHERE d.business_id = p_business_id
         AND (p_from IS NULL OR d.business_date >= p_from)
         AND (p_to   IS NULL OR d.business_date <= p_to)
       ORDER BY d.business_date;
    RETURN;
  END IF;

  -- An agent may only ask about their own float; the Owner may ask about any.
  IF NOT app.is_owner(p_business_id)
     AND NOT app.own_active_agent_membership_permits(
               p_membership_id, 'can_collect_payments', p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this agent' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(migrated_through_date, '-infinity'::date) INTO v_span
    FROM businesses WHERE business_id = p_business_id;

  RETURN QUERY
  WITH deltas AS (
    SELECT g.business_date AS d, SUM(g.amount) AS delta
      FROM agent_bf_grants g
     WHERE g.membership_id = p_membership_id AND g.deleted_at IS NULL
       AND g.business_date > v_span
     GROUP BY 1
    UNION ALL
    SELECT c.business_date, SUM(c.collected_amount)
      FROM collections c
      JOIN loans l ON l.loan_id = c.loan_id
     WHERE c.collected_by_membership_id = p_membership_id
       AND c.deleted_at IS NULL AND l.deleted_at IS NULL
       AND c.business_date > v_span
     GROUP BY 1
    UNION ALL
    SELECT l.issue_business_date, -SUM(l.amount_given)
      FROM loans l
     WHERE l.collection_agent_membership_id = p_membership_id
       AND l.deleted_at IS NULL AND l.is_pre_existing = false
       AND l.issue_business_date > v_span
     GROUP BY 1
    UNION ALL
    SELECT e.business_date, -SUM(e.amount)
      FROM expenses e
     WHERE e.recorded_by_membership_id = p_membership_id
       AND e.deleted_at IS NULL
       AND e.business_date > v_span
     GROUP BY 1
    UNION ALL
    SELECT cp.business_date, -SUM(cp.net_paid)
      FROM cheti_payments cp
     WHERE cp.recorded_by_membership_id = p_membership_id
       AND cp.deleted_at IS NULL
       AND cp.business_date > v_span
     GROUP BY 1
    UNION ALL
    SELECT t.business_date,
           SUM(CASE WHEN t.to_agent_id = a.agent_id THEN t.amount ELSE -t.amount END)
      FROM cash_transfers t
      JOIN agents a ON a.membership_id = p_membership_id
     WHERE (t.from_agent_id = a.agent_id OR t.to_agent_id = a.agent_id)
       AND t.from_agent_confirmed_at IS NOT NULL
       AND t.to_agent_confirmed_at IS NOT NULL
       AND t.deleted_at IS NULL
       AND t.business_date > v_span
     GROUP BY 1
  ),
  by_day AS (
    SELECT d, SUM(delta) AS delta FROM deltas WHERE d IS NOT NULL GROUP BY d
  ),
  running AS (
    SELECT d,
           SUM(delta) OVER (ORDER BY d) AS closing,
           SUM(delta) OVER (ORDER BY d) - delta AS opening
      FROM by_day
  )
  SELECT r.d, r.opening, r.closing
    FROM running r
   WHERE (p_from IS NULL OR r.d >= p_from)
     AND (p_to   IS NULL OR r.d <= p_to)
   ORDER BY r.d;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.ledger_day_balances(uuid, date, date, uuid)
  TO authenticated, service_role;
