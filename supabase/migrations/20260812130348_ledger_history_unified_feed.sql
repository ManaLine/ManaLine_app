-- =============================================================================
-- app.ledger_history — one chronological feed of every money movement
-- =============================================================================
-- WHY: OW-017 built its "history" from three client-side queries (collections,
-- loans, settlement adjustments) and called the result the business's history.
-- day_ledger — the canonical account of what moves money — has eight
-- categories. Expenses, investor deposits, investor withdrawals, cheti paid
-- and cheti received were simply missing, so the screen was quietly
-- incomplete, and its "Net Change" was summed from the rows it happened to
-- have rather than from the ledger.
--
-- SECURITY INVOKER, DELIBERATELY. This is the load-bearing decision here.
-- Every underlying table already has RLS that says exactly what each role may
-- read: an Owner sees the whole business; an Agent sees collections and loans
-- for customers on their own route, expenses they recorded, adjustments where
-- they are the agent, and investments only with can_view_investor_info. By
-- running as the caller, this function inherits all of that for free. The
-- Owner and the Agent call the SAME function and each correctly gets their own
-- slice — no second implementation, no permission logic duplicated in Dart,
-- and no SECURITY DEFINER hole to get wrong.
--
-- A consequence worth stating: an Agent's result is a PARTIAL view by design.
-- Any total computed from it is that agent's own activity, never the
-- business's position. AG-010 must label it as such and must never show a
-- closing balance.
--
-- Soft-deleted rows are excluded by the *_hide_deleted RLS policies already on
-- each table, so there is no deleted_at predicate here — adding one would
-- imply the filtering happens here when it does not.
--
-- Verified by inserting one row of every kind inside a rolled-back DO block:
-- 8 events returned, newest first, directions and counterparties correct, and
-- loan_distribution reporting amount_given (the generated repayment − interest
-- − fee) rather than the repayment amount.

CREATE OR REPLACE FUNCTION app.ledger_history(
  p_business_id UUID,
  p_before      TIMESTAMP DEFAULT NULL,
  p_limit       INT       DEFAULT 50
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
    -- Money in: customer repayments.
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
    JOIN loans l     ON l.loan_id = c.loan_id
    JOIN customers cu ON cu.customer_id = c.customer_id
    JOIN persons p    ON p.person_id = cu.person_id
    WHERE l.business_id = p_business_id

    UNION ALL

    -- Money out: cash handed to the customer. amount_given is generated
    -- (repayment - interest - fee) and is the cash that actually left.
    SELECT 'loan:' || l.loan_id,
           'loan_distribution',
           'out',
           l.issue_business_date,
           COALESCE(l.entry_timestamp, l.issue_business_date::timestamp),
           l.amount_given,
           p.full_name,
           l.loan_number,
           NULL
    FROM loans l
    JOIN customers cu ON cu.customer_id = l.customer_id
    JOIN persons p    ON p.person_id = cu.person_id
    WHERE l.business_id = p_business_id

    UNION ALL

    SELECT 'expense:' || e.expense_id,
           'expense',
           'out',
           e.business_date,
           COALESCE(e.entry_timestamp, e.business_date::timestamp),
           e.amount,
           NULL,
           e.category::text,
           e.remarks
    FROM expenses e
    WHERE e.business_id = p_business_id

    UNION ALL

    -- Investor money in. investments has no entry_timestamp; effective_date
    -- is the business day the money counts against.
    SELECT 'investment:' || i.investment_id,
           'investor_deposit',
           'in',
           i.effective_date,
           i.effective_date::timestamp,
           i.principal_amount,
           p.full_name,
           NULL,
           i.interest_type::text
    FROM investments i
    JOIN investors inv ON inv.investor_id = i.investor_id
    JOIN persons p     ON p.person_id = inv.person_id
    WHERE i.business_id = p_business_id

    UNION ALL

    SELECT 'withdrawal:' || w.withdrawal_id,
           'investor_withdrawal',
           'out',
           w.business_date,
           COALESCE(w.entry_timestamp, w.business_date::timestamp),
           w.amount,
           p.full_name,
           NULL,
           w.withdrawal_type::text
    FROM investment_withdrawals w
    JOIN investments i ON i.investment_id = w.investment_id
    JOIN investors inv ON inv.investor_id = i.investor_id
    JOIN persons p     ON p.person_id = inv.person_id
    WHERE i.business_id = p_business_id

    UNION ALL

    -- A cheti instalment paid out. net_paid is generated (gross - dividend)
    -- and is the cash that moved; the instalment is an asset, not an expense
    -- (see CLAUDE.md money rules).
    SELECT 'cheti_payment:' || cp.cheti_payment_id,
           'cheti_paid',
           'out',
           cp.business_date,
           COALESCE(cp.entry_timestamp, cp.business_date::timestamp),
           cp.net_paid,
           ch.name,
           NULL,
           NULL
    FROM cheti_payments cp
    JOIN chetis ch ON ch.cheti_id = cp.cheti_id
    WHERE cp.business_id = p_business_id

    UNION ALL

    -- The availed lumpsum coming back in, once.
    SELECT 'cheti_availed:' || ch.cheti_id,
           'cheti_received',
           'in',
           ch.availed_date,
           ch.availed_date::timestamp,
           ch.availed_amount,
           ch.name,
           NULL,
           NULL
    FROM chetis ch
    WHERE ch.business_id = p_business_id
      AND ch.availed_date IS NOT NULL
      AND ch.availed_amount IS NOT NULL

    UNION ALL

    SELECT 'adjustment:' || sa.adjustment_id,
           CASE WHEN sa.adjustment_type = 'Excess' THEN 'adjustment_excess'
                ELSE 'adjustment_short' END,
           CASE WHEN sa.adjustment_type = 'Excess' THEN 'in' ELSE 'out' END,
           sa.business_date,
           sa.business_date::timestamp,
           sa.amount,
           NULL,
           sa.adjustment_type::text,
           sa.applied_to::text
    FROM settlement_adjustments sa
    WHERE sa.business_id = p_business_id
  )
  SELECT e.event_id, e.event_type, e.direction, e.business_date,
         e.occurred_at, e.amount, e.counterparty, e.reference, e.method
  FROM events e
  WHERE e.business_date IS NOT NULL
    AND (p_before IS NULL OR e.occurred_at < p_before)
  ORDER BY e.occurred_at DESC, e.event_id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
$function$;

COMMENT ON FUNCTION app.ledger_history(UUID, TIMESTAMP, INT) IS
  'Unified money-movement feed for a business, newest first, keyset-paginated on occurred_at. SECURITY INVOKER: RLS decides what the caller sees, so an Agent gets their permitted subset and any total from it is their own activity, not the business position.';

GRANT EXECUTE ON FUNCTION app.ledger_history(UUID, TIMESTAMP, INT) TO authenticated;

-- -----------------------------------------------------------------------------
-- Month summary — from day_ledger, never from summing the feed above.
-- -----------------------------------------------------------------------------
-- The headline figure has to come from the same derived ledger Day Closure
-- reconciles against. Summing the visible rows is how the old screen produced
-- a "Net Change" that was not any real quantity: a page of rows is not the
-- month, and a filtered page certainly is not.
CREATE OR REPLACE FUNCTION app.ledger_month_summary(
  p_business_id UUID,
  p_month       DATE
)
RETURNS TABLE (
  month_start     DATE,
  received        NUMERIC,
  spent           NUMERIC,
  net             NUMERIC,
  opening_balance NUMERIC,
  closing_balance NUMERIC,
  days_recorded   INT
)
LANGUAGE sql
STABLE
SET search_path TO 'pg_catalog', 'public'
AS $function$
  WITH bounds AS (
    SELECT date_trunc('month', p_month)::date AS m_start,
           (date_trunc('month', p_month) + interval '1 month - 1 day')::date AS m_end
  ), d AS (
    SELECT dl.*
    FROM day_ledger dl, bounds b
    WHERE dl.business_id = p_business_id
      AND dl.business_date BETWEEN b.m_start AND b.m_end
  )
  SELECT b.m_start,
         COALESCE(SUM(d.total_collections + d.investor_deposits + d.excess_amount + d.cheti_received), 0),
         COALESCE(SUM(d.total_loan_distribution + d.total_expenses + d.investor_withdrawals + d.short_amount + d.cheti_paid), 0),
         COALESCE(SUM(d.total_collections + d.investor_deposits + d.excess_amount + d.cheti_received)
                - SUM(d.total_loan_distribution + d.total_expenses + d.investor_withdrawals + d.short_amount + d.cheti_paid), 0),
         (SELECT dd.opening_balance FROM d dd ORDER BY dd.business_date ASC  LIMIT 1),
         (SELECT dd.closing_balance FROM d dd ORDER BY dd.business_date DESC LIMIT 1),
         COALESCE(COUNT(d.business_date), 0)::int
  FROM bounds b LEFT JOIN d ON true
  GROUP BY b.m_start;
$function$;

COMMENT ON FUNCTION app.ledger_month_summary(UUID, DATE) IS
  'Month totals for the history header, derived from day_ledger. Never sum the transaction feed to produce this.';

GRANT EXECUTE ON FUNCTION app.ledger_month_summary(UUID, DATE) TO authenticated;
