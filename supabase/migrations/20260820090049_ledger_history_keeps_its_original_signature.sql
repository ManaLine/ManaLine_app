-- BF opens the day, and a pre-existing loan is not a movement.
--
-- SEEN LIVE: "Thu 8 Jan, Day Net -1,17,600" — two migrated loans and nothing
-- else. Both problems are here:
--
--   * agent_bf_grants was in no feed at all, so granting an Agent their float
--     was invisible: the Owner pressed Add BF, the number on the profile moved,
--     and History never mentioned it. BF is what a collection round is funded
--     by, so it is the first thing that should appear on a day.
--
--   * a pre-existing loan was listed as money out. Its cash left the till
--     before this business joined MANA LINE, so counting it makes every
--     migrated day look like a catastrophic loss and no BF grant could ever
--     balance it. Those loans stay visible on the customer and loan screens,
--     where they are a balance owed rather than a movement of cash.
--
-- The previous migration reordered the parameters, which CREATE OR REPLACE
-- cannot do: it created a SECOND app.ledger_history instead of replacing the
-- first. Two overloads make the call ambiguous and PostgREST refuses it. Drop
-- the accidental one and rebuild on the original argument order.
DROP FUNCTION IF EXISTS app.ledger_history(uuid, timestamp, text[], date, date, text, int);

CREATE OR REPLACE FUNCTION app.ledger_history(
  p_business_id uuid,
  p_before timestamp DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_types text[] DEFAULT NULL,
  p_from date DEFAULT NULL,
  p_to date DEFAULT NULL,
  p_search text DEFAULT NULL
)
RETURNS TABLE (
  event_id text, event_type text, direction text, business_date date,
  occurred_at timestamp, amount numeric, counterparty text,
  reference text, method text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  WITH events AS (
    SELECT 'collection:' || c.collection_id            AS event_id,
           'collection'                                AS event_type,
           'in'                                        AS direction,
           c.business_date,
           COALESCE(c.entry_timestamp, c.business_date::timestamp) AS occurred_at,
           c.collected_amount                          AS amount,
           p.full_name                                 AS counterparty,
           l.loan_number                               AS reference,
           c.result_type::text                         AS method
    FROM collections c
    JOIN loans l      ON l.loan_id = c.loan_id
    JOIN customers cu ON cu.customer_id = c.customer_id
    JOIN persons p    ON p.person_id = cu.person_id
    WHERE l.business_id = p_business_id

    UNION ALL

    -- The float the round is funded by. Timestamped at the head of its day,
    -- which is the order the money actually moves in.
    SELECT 'bf_grant:' || g.grant_id, 'bf_grant', 'in',
           g.business_date, g.business_date::timestamp,
           g.amount, p.full_name, NULL, NULL
    FROM agent_bf_grants g
    JOIN business_members bm ON bm.membership_id = g.membership_id
    JOIN persons p ON p.person_id = bm.person_id
    WHERE g.business_id = p_business_id
      AND g.deleted_at IS NULL

    UNION ALL

    -- is_pre_existing excluded: that cash left the till before MANA LINE, so
    -- listing it as money out made every migrated day read as a huge loss.
    SELECT 'loan:' || l.loan_id, 'loan_distribution', 'out',
           l.issue_business_date,
           COALESCE(l.entry_timestamp, l.issue_business_date::timestamp),
           l.amount_given, p.full_name, l.loan_number, NULL
    FROM loans l
    JOIN customers cu ON cu.customer_id = l.customer_id
    JOIN persons p    ON p.person_id = cu.person_id
    WHERE l.business_id = p_business_id
      AND l.is_pre_existing = false

    UNION ALL

    SELECT 'expense:' || e.expense_id, 'expense', 'out',
           e.business_date,
           COALESCE(e.entry_timestamp, e.business_date::timestamp),
           e.amount, NULL, e.category::text, e.remarks
    FROM expenses e
    WHERE e.business_id = p_business_id

    UNION ALL

    SELECT 'investment:' || i.investment_id, 'investor_deposit', 'in',
           i.effective_date, i.effective_date::timestamp,
           i.principal_amount, p.full_name, NULL, i.interest_type::text
    FROM investments i
    JOIN investors inv ON inv.investor_id = i.investor_id
    JOIN persons p     ON p.person_id = inv.person_id
    WHERE i.business_id = p_business_id

    UNION ALL

    SELECT 'withdrawal:' || w.withdrawal_id, 'investor_withdrawal', 'out',
           w.business_date,
           COALESCE(w.entry_timestamp, w.business_date::timestamp),
           w.amount, p.full_name, NULL, w.withdrawal_type::text
    FROM investment_withdrawals w
    JOIN investments i ON i.investment_id = w.investment_id
    JOIN investors inv ON inv.investor_id = i.investor_id
    JOIN persons p     ON p.person_id = inv.person_id
    WHERE i.business_id = p_business_id

    UNION ALL

    SELECT 'cheti_payment:' || cp.cheti_payment_id, 'cheti_paid', 'out',
           cp.business_date,
           COALESCE(cp.entry_timestamp, cp.business_date::timestamp),
           cp.net_paid, ch.name, NULL, NULL
    FROM cheti_payments cp
    JOIN chetis ch ON ch.cheti_id = cp.cheti_id
    WHERE cp.business_id = p_business_id

    UNION ALL

    SELECT 'cheti_availed:' || ch.cheti_id, 'cheti_received', 'in',
           ch.availed_date, ch.availed_date::timestamp,
           ch.availed_amount, ch.name, NULL, NULL
    FROM chetis ch
    WHERE ch.business_id = p_business_id
      AND ch.availed_date IS NOT NULL
      AND ch.availed_amount IS NOT NULL

    UNION ALL

    SELECT 'adjustment:' || sa.adjustment_id,
           CASE WHEN sa.adjustment_type = 'Excess' THEN 'adjustment_excess'
                ELSE 'adjustment_short' END,
           CASE WHEN sa.adjustment_type = 'Excess' THEN 'in' ELSE 'out' END,
           sa.business_date, sa.business_date::timestamp,
           sa.amount, NULL, sa.adjustment_type::text, sa.applied_to::text
    FROM settlement_adjustments sa
    WHERE sa.business_id = p_business_id
  )
  SELECT e.event_id, e.event_type, e.direction, e.business_date,
         e.occurred_at, e.amount, e.counterparty, e.reference, e.method
  FROM events e
  WHERE e.business_date IS NOT NULL
    AND (p_before  IS NULL OR e.occurred_at   <  p_before)
    AND (p_types   IS NULL OR e.event_type    =  ANY(p_types))
    AND (p_from    IS NULL OR e.business_date >= p_from)
    AND (p_to      IS NULL OR e.business_date <= p_to)
    AND (
      p_search IS NULL OR btrim(p_search) = ''
      OR e.counterparty ILIKE '%' || btrim(p_search) || '%'
      OR e.reference    ILIKE '%' || btrim(p_search) || '%'
      OR e.method       ILIKE '%' || btrim(p_search) || '%'
    )
  ORDER BY e.occurred_at DESC, e.event_id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
$$;
