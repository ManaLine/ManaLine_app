-- History shows the expenses the migrated book declared.
--
-- The Owner asked why no expense has ever appeared in History. Because
-- ledger_history reads the `expenses` table, and for a migrated book that
-- table is empty: import_weekly_account deliberately writes nothing to it,
-- keeping each week's lines as JSON on migration_weeks.expense_lines instead.
-- On the live book that is Rs 1,84,500 across 31 lines -- Petrol, Sadaru, a
-- new bike, train tickets, salary -- none of them visible anywhere.
--
-- READ where they live rather than copied into `expenses`. Copying would give
-- the same rupee two homes: day_ledger already takes the week's declared
-- expense figure, and migration_profit_summary sums migration_weeks.expenses,
-- so inserting rows would double-count against both and quietly move profit.
--
-- One row per line, dated to the account it belongs to. The amounts are text
-- in the JSON because that is how the sheet was read; cast here, and a line
-- that will not cast is skipped rather than allowed to fail the whole feed.
CREATE OR REPLACE FUNCTION app.migrated_expense_lines(p_business_id uuid)
RETURNS TABLE(line_key text, business_date date, amount numeric, label text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT 'migrated_expense:' || w.account_date::text || ':' || (e.ord - 1)::text,
         w.account_date,
         (e.line ->> 'amount')::numeric,
         COALESCE(NULLIF(btrim(e.line ->> 'label'), ''), 'Expense')
    FROM migration_weeks w
    CROSS JOIN LATERAL json_array_elements(COALESCE(w.expense_lines, '[]'::json))
                       WITH ORDINALITY AS e(line, ord)
   WHERE w.business_id = p_business_id
     AND (e.line ->> 'amount') ~ '^[0-9]+(\.[0-9]+)?$';
$$;

GRANT EXECUTE ON FUNCTION app.migrated_expense_lines(uuid) TO authenticated, service_role;
