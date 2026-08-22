-- Two things History was not telling the truth about.
--
-- 1. THE LENDING WAS MISSING. Migrated loans were excluded outright, with the
--    reason recorded in the branch: listing that cash as money out "made every
--    migrated day read as a huge loss". True of the screen as it then was --
--    the day header showed a NET, so a day that lent Rs 6,26,800 and collected
--    nothing showed minus Rs 6,26,800 and looked like catastrophe.
--
--    That was never a reason to hide the lending; it was a reason not to draw
--    a swing as though it were a balance. The header now shows the day's
--    closing balance from ledger_day_balances, so the loss it was avoiding
--    cannot happen -- and the day ledger those balances come from has always
--    counted the disbursements. Hiding the rows meant a day closed on a figure
--    the rows on screen could not account for. As the Owner put it, without
--    them the calculation is of no use.
--
--    Rows carry amount_given, the cash that actually left, not the gross
--    repayment. Inside the migrated span the book states its own gross figure
--    in the weekly rows, so the two will not tally line for line; the day
--    balance is authoritative either way. After the cut-off they reconcile
--    exactly, because the day is then derived from these same rows.
--
-- 2. A DEPOSIT SHOWED WHAT WAS LEFT, NOT WHAT WAS PUT IN. The investor branch
--    read principal_amount, which is the CURRENT balance and falls every time
--    that investment is withdrawn from. Karri Bhaskara Reddy put in
--    Rs 10,00,000 on 2 January and has since taken Rs 9,00,000 back out, so
--    his deposit was drawn as Rs 1,00,000 -- a past event restated with a
--    later number, and the day it sits in could never add up.
--    original_principal_amount is what was deposited and does not move.
CREATE OR REPLACE FUNCTION app.ledger_history(
  p_business_id uuid,
  p_before timestamp without time zone DEFAULT NULL::timestamp without time zone,
  p_limit integer DEFAULT 50,
  p_types text[] DEFAULT NULL::text[],
  p_from date DEFAULT NULL::date,
  p_to date DEFAULT NULL::date,
  p_search text DEFAULT NULL::text)
RETURNS TABLE(event_id text, event_type text, direction text, business_date date,
              occurred_at timestamp without time zone, amount numeric,
              counterparty text, reference text, method text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
  WITH events AS (
    SELECT 'collection:' || c.collection_id            AS event_id,
           'collection'                                AS event_type,
           'in'                                        AS direction,
           c.business_date,
           CASE WHEN c.entry_timestamp IS NULL
                  OR c.entry_timestamp::date <> c.business_date
                THEN c.business_date::timestamp ELSE c.entry_timestamp END AS occurred_at,
           c.collected_amount                          AS amount,
           p.full_name                                 AS counterparty,
           l.loan_number                               AS reference,
           c.result_type::text                         AS method
    FROM collections c
    JOIN loans l      ON l.loan_id = c.loan_id
    JOIN customers cu ON cu.customer_id = c.customer_id
    JOIN persons p    ON p.person_id = cu.person_id
    WHERE l.business_id = p_business_id
      AND c.deleted_at IS NULL
      AND l.deleted_at IS NULL

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

    -- Every loan, migrated or not. See the note at the top.
    SELECT 'loan:' || l.loan_id, 'loan_distribution', 'out',
           l.issue_business_date,
           CASE WHEN l.entry_timestamp IS NULL
                  OR l.entry_timestamp::date <> l.issue_business_date
                THEN l.issue_business_date::timestamp ELSE l.entry_timestamp END,
           l.amount_given, p.full_name, l.loan_number, NULL
    FROM loans l
    JOIN customers cu ON cu.customer_id = l.customer_id
    JOIN persons p    ON p.person_id = cu.person_id
    WHERE l.business_id = p_business_id
      AND l.deleted_at IS NULL

    UNION ALL

    SELECT 'expense:' || e.expense_id, 'expense', 'out',
           e.business_date,
           CASE WHEN e.entry_timestamp IS NULL
                  OR e.entry_timestamp::date <> e.business_date
                THEN e.business_date::timestamp ELSE e.entry_timestamp END,
           e.amount, NULL, e.category::text, e.remarks
    FROM expenses e
    WHERE e.business_id = p_business_id
      AND e.deleted_at IS NULL

    UNION ALL

    -- What was PUT IN on the day, which does not change when it is later
    -- withdrawn from.
    SELECT 'investment:' || i.investment_id, 'investor_deposit', 'in',
           i.effective_date, i.effective_date::timestamp,
           i.original_principal_amount, p.full_name, NULL, i.interest_type::text
    FROM investments i
    JOIN investors inv ON inv.investor_id = i.investor_id
    JOIN persons p     ON p.person_id = inv.person_id
    WHERE i.business_id = p_business_id
      AND i.deleted_at IS NULL

    UNION ALL

    SELECT 'withdrawal:' || w.withdrawal_id, 'investor_withdrawal', 'out',
           w.business_date,
           CASE WHEN w.entry_timestamp IS NULL
                  OR w.entry_timestamp::date <> w.business_date
                THEN w.business_date::timestamp ELSE w.entry_timestamp END,
           w.amount, p.full_name, NULL, w.withdrawal_type::text
    FROM investment_withdrawals w
    JOIN investments i ON i.investment_id = w.investment_id
    JOIN investors inv ON inv.investor_id = i.investor_id
    JOIN persons p     ON p.person_id = inv.person_id
    WHERE i.business_id = p_business_id
      AND w.deleted_at IS NULL
      AND i.deleted_at IS NULL

    UNION ALL

    SELECT 'cheti_payment:' || cp.cheti_payment_id, 'cheti_paid', 'out',
           cp.business_date,
           CASE WHEN cp.entry_timestamp IS NULL
                  OR cp.entry_timestamp::date <> cp.business_date
                THEN cp.business_date::timestamp ELSE cp.entry_timestamp END,
           cp.net_paid, ch.name, NULL, NULL
    FROM cheti_payments cp
    JOIN chetis ch ON ch.cheti_id = cp.cheti_id
    WHERE cp.business_id = p_business_id
      AND cp.deleted_at IS NULL
      AND ch.deleted_at IS NULL

    UNION ALL

    SELECT 'cheti_availed:' || ch.cheti_id, 'cheti_received', 'in',
           ch.availed_date, ch.availed_date::timestamp,
           ch.availed_amount, ch.name, NULL, NULL
    FROM chetis ch
    WHERE ch.business_id = p_business_id
      AND ch.availed_date IS NOT NULL
      AND ch.availed_amount IS NOT NULL
      AND ch.deleted_at IS NULL

    UNION ALL

    SELECT 'adjustment:' || sa.adjustment_id,
           CASE WHEN sa.adjustment_type = 'Excess' THEN 'adjustment_excess'
                ELSE 'adjustment_short' END,
           CASE WHEN sa.adjustment_type = 'Excess' THEN 'in' ELSE 'out' END,
           sa.business_date, sa.business_date::timestamp,
           sa.amount, NULL, sa.adjustment_type::text, sa.applied_to::text
    FROM settlement_adjustments sa
    WHERE sa.business_id = p_business_id
      AND sa.deleted_at IS NULL
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
