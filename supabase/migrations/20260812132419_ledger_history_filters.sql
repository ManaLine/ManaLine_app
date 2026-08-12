-- =============================================================================
-- app.ledger_history — add filtering and search
-- =============================================================================
-- Filters have to run server-side. The feed is keyset-paginated, so filtering
-- a loaded page in Dart would filter only the rows that happened to be
-- fetched: "Expenses only" would show the expenses within the newest 50
-- events and silently claim that was all of them. The month summary has the
-- same property, which is why it comes from day_ledger and not from this.
--
-- Dropped and recreated rather than CREATE OR REPLACE: adding parameters
-- changes the signature, which would leave the old three-argument function in
-- place as a second overload and make the PostgREST call ambiguous.
--
-- Verified inside a rolled-back DO block against three seeded events:
--   all=3  expenseOnly=1  from-the-10th=2  search'L-F1'=2  before-09:00=2
--   chetiOnly=0
DROP FUNCTION IF EXISTS app.ledger_history(UUID, TIMESTAMP, INT);

CREATE FUNCTION app.ledger_history(
  p_business_id UUID,
  p_before      TIMESTAMP DEFAULT NULL,
  p_limit       INT       DEFAULT 50,
  p_types       TEXT[]    DEFAULT NULL,
  p_from        DATE      DEFAULT NULL,
  p_to          DATE      DEFAULT NULL,
  p_search      TEXT      DEFAULT NULL
)
RETURNS TABLE (
  event_id      TEXT,
  event_type    TEXT,
  direction     TEXT,
  business_date DATE,
  occurred_at   TIMESTAMP,
  amount        NUMERIC,
  counterparty  TEXT,
  reference     TEXT,
  method        TEXT
)
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
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

    -- amount_given is generated (repayment - interest - fee): the cash that
    -- actually left, not the repayment amount.
    SELECT 'loan:' || l.loan_id, 'loan_distribution', 'out',
           l.issue_business_date,
           COALESCE(l.entry_timestamp, l.issue_business_date::timestamp),
           l.amount_given, p.full_name, l.loan_number, NULL
    FROM loans l
    JOIN customers cu ON cu.customer_id = l.customer_id
    JOIN persons p    ON p.person_id = cu.person_id
    WHERE l.business_id = p_business_id

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

    -- net_paid is generated (gross - dividend). A cheti instalment is an
    -- asset, not an expense (CLAUDE.md money rules) — it appears here because
    -- cash moved, not because it is a cost.
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
$function$;

COMMENT ON FUNCTION app.ledger_history(UUID, TIMESTAMP, INT, TEXT[], DATE, DATE, TEXT) IS
  'Unified money-movement feed, newest first, keyset-paginated on occurred_at, with type/date/search filters applied server-side. SECURITY INVOKER: RLS decides what the caller sees, so an Agent gets their permitted subset and any total from it is their own activity, not the business position.';

GRANT EXECUTE ON FUNCTION app.ledger_history(UUID, TIMESTAMP, INT, TEXT[], DATE, DATE, TEXT) TO authenticated;
