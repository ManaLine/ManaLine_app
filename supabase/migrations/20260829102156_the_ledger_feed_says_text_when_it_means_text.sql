-- The membership rewrite applied cleanly and failed on its first call:
--   structure of query does not match function result type
--   Returned type character varying does not match expected type text in column 7
--
-- persons.full_name, loans.loan_number, chetis.name and expenses.remarks are
-- varchar. LANGUAGE sql coerced them to the declared text columns without
-- comment; plpgsql RETURN QUERY does not, and plpgsql bodies are not
-- type-checked at CREATE time -- so this was a clean apply and a broken
-- function, which is the failure mode the migration notes warn about.
--
-- Every text column of the result is now cast at its source. Behaviour is
-- otherwise identical to the migration before this one.
CREATE OR REPLACE FUNCTION app.ledger_history(
  p_business_id uuid,
  p_before timestamp without time zone DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_types text[] DEFAULT NULL,
  p_from date DEFAULT NULL,
  p_to date DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_membership_id uuid DEFAULT NULL
)
RETURNS TABLE(event_id text, event_type text, direction text, business_date date,
              occurred_at timestamp without time zone, amount numeric,
              counterparty text, reference text, method text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  -- The gate DEFINER removed. The business feed is the Owner's; a membership
  -- feed is that person's own, or the Owner looking at their agent.
  IF p_membership_id IS NULL THEN
    IF NOT app.is_owner(p_business_id) THEN
      RAISE EXCEPTION 'Only the Owner can read the business ledger'
        USING ERRCODE = '42501';
    END IF;
  ELSE
    IF NOT (app.is_owner(p_business_id)
            OR app.membership_belongs_to_current_person(p_membership_id)) THEN
      RAISE EXCEPTION 'Not your ledger' USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN QUERY
  WITH events AS (
    SELECT 'collection:' || c.collection_id            AS event_id,
           'collection'                                AS event_type,
           'in'                                        AS direction,
           c.business_date,
           CASE WHEN c.entry_timestamp IS NULL
                  OR c.entry_timestamp::date <> c.business_date
                THEN c.business_date::timestamp ELSE c.entry_timestamp END AS occurred_at,
           c.collected_amount                          AS amount,
           p.full_name::text                           AS counterparty,
           l.loan_number::text                         AS reference,
           c.result_type::text                         AS method
    FROM collections c
    JOIN loans l      ON l.loan_id = c.loan_id
    JOIN customers cu ON cu.customer_id = c.customer_id
    JOIN persons p    ON p.person_id = cu.person_id
    WHERE l.business_id = p_business_id
      AND c.deleted_at IS NULL
      AND l.deleted_at IS NULL
      AND (p_membership_id IS NULL
           OR c.collected_by_membership_id = p_membership_id)

    UNION ALL

    SELECT 'bf_grant:' || g.grant_id, 'bf_grant', 'in',
           g.business_date, g.business_date::timestamp,
           g.amount, p.full_name::text, NULL::text, NULL::text
    FROM agent_bf_grants g
    JOIN business_members bm ON bm.membership_id = g.membership_id
    JOIN persons p ON p.person_id = bm.person_id
    WHERE g.business_id = p_business_id
      AND g.deleted_at IS NULL
      AND (p_membership_id IS NULL OR g.membership_id = p_membership_id)

    UNION ALL

    -- Every loan, migrated or not. See the note at the top.
    SELECT 'loan:' || l.loan_id, 'loan_distribution', 'out',
           l.issue_business_date,
           CASE WHEN l.entry_timestamp IS NULL
                  OR l.entry_timestamp::date <> l.issue_business_date
                THEN l.issue_business_date::timestamp ELSE l.entry_timestamp END,
           l.amount_given, p.full_name::text, l.loan_number::text, NULL::text
    FROM loans l
    JOIN customers cu ON cu.customer_id = l.customer_id
    JOIN persons p    ON p.person_id = cu.person_id
    WHERE l.business_id = p_business_id
      AND l.deleted_at IS NULL
      AND (p_membership_id IS NULL
           OR l.collection_agent_membership_id = p_membership_id)

    UNION ALL

    SELECT 'expense:' || e.expense_id, 'expense', 'out',
           e.business_date,
           CASE WHEN e.entry_timestamp IS NULL
                  OR e.entry_timestamp::date <> e.business_date
                THEN e.business_date::timestamp ELSE e.entry_timestamp END,
           e.amount, NULL::text, e.category::text, e.remarks::text
    FROM expenses e
    WHERE e.business_id = p_business_id
      AND e.deleted_at IS NULL
      AND (p_membership_id IS NULL
           OR e.recorded_by_membership_id = p_membership_id)

    UNION ALL

    -- From here down: the business's own money, with no agent behind it. A
    -- membership feed excludes all of it rather than showing it unattributed.
    SELECT 'investment:' || i.investment_id, 'investor_deposit', 'in',
           i.effective_date, i.effective_date::timestamp,
           i.original_principal_amount, p.full_name::text, NULL::text,
           i.interest_type::text
    FROM investments i
    JOIN investors inv ON inv.investor_id = i.investor_id
    JOIN persons p     ON p.person_id = inv.person_id
    WHERE i.business_id = p_business_id
      AND i.deleted_at IS NULL
      AND p_membership_id IS NULL

    UNION ALL

    SELECT 'withdrawal:' || w.withdrawal_id, 'investor_withdrawal', 'out',
           w.business_date,
           CASE WHEN w.entry_timestamp IS NULL
                  OR w.entry_timestamp::date <> w.business_date
                THEN w.business_date::timestamp ELSE w.entry_timestamp END,
           w.amount, p.full_name::text, NULL::text, w.withdrawal_type::text
    FROM investment_withdrawals w
    JOIN investments i ON i.investment_id = w.investment_id
    JOIN investors inv ON inv.investor_id = i.investor_id
    JOIN persons p     ON p.person_id = inv.person_id
    WHERE i.business_id = p_business_id
      AND w.deleted_at IS NULL
      AND i.deleted_at IS NULL
      AND p_membership_id IS NULL

    UNION ALL

    SELECT 'cheti_payment:' || cp.cheti_payment_id, 'cheti_paid', 'out',
           cp.business_date,
           CASE WHEN cp.entry_timestamp IS NULL
                  OR cp.entry_timestamp::date <> cp.business_date
                THEN cp.business_date::timestamp ELSE cp.entry_timestamp END,
           cp.net_paid, ch.name::text, NULL::text, NULL::text
    FROM cheti_payments cp
    JOIN chetis ch ON ch.cheti_id = cp.cheti_id
    WHERE cp.business_id = p_business_id
      AND cp.deleted_at IS NULL
      AND ch.deleted_at IS NULL
      AND p_membership_id IS NULL

    UNION ALL

    SELECT 'cheti_availed:' || ch.cheti_id, 'cheti_received', 'in',
           ch.availed_date, ch.availed_date::timestamp,
           ch.availed_amount, ch.name::text, NULL::text, NULL::text
    FROM chetis ch
    WHERE ch.business_id = p_business_id
      AND ch.availed_date IS NOT NULL
      AND ch.availed_amount IS NOT NULL
      AND ch.deleted_at IS NULL
      AND p_membership_id IS NULL

    UNION ALL

    -- The migrated book's own expense lines. They live on migration_weeks
    -- because import_weekly_account writes nothing to `expenses`; copying them
    -- there would double-count against day_ledger and profit, both of which
    -- already take the week's declared figure. Read, not copied.
    SELECT me.line_key::text, 'expense', 'out',
           me.business_date, me.business_date::timestamp,
           me.amount, NULL::text, me.label::text, NULL::text
    FROM app.migrated_expense_lines(p_business_id) me
    WHERE p_membership_id IS NULL

    UNION ALL

    SELECT 'adjustment:' || sa.adjustment_id,
           CASE WHEN sa.adjustment_type = 'Excess' THEN 'adjustment_excess'
                ELSE 'adjustment_short' END,
           CASE WHEN sa.adjustment_type = 'Excess' THEN 'in' ELSE 'out' END,
           sa.business_date, sa.business_date::timestamp,
           sa.amount, NULL::text, sa.adjustment_type::text, sa.applied_to::text
    FROM settlement_adjustments sa
    WHERE sa.business_id = p_business_id
      AND sa.deleted_at IS NULL
      AND p_membership_id IS NULL
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
END;
$function$;
