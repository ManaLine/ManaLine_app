-- A deleted loan is not on the book.
--
-- Every subquery here reads `loans` without `deleted_at IS NULL`, so the
-- Pre-Existing Business screen counted soft-deleted rows as if they were live.
-- After the duplicate import of 22 Aug 2026 was cleaned up, the screen still
-- read "164 pre-existing loans entered" and a line balance of Rs 86,81,200 --
-- 56 live loans and 108 deleted ones, against a true Rs 30,04,900.
--
-- This is the failure mode the project treats as worse than a crash: a
-- confidently wrong number on a money screen, with nothing to suggest it is
-- wrong. Deleting the duplicates had visibly not worked, and the only reason
-- it surfaced is that the Owner knew what the number should be.
--
-- Signature unchanged, so CREATE OR REPLACE is safe: one overload, no
-- PostgREST 300.
CREATE OR REPLACE FUNCTION app.migration_summary(p_business_id uuid)
RETURNS TABLE(migration_locked boolean, business_started_at timestamp without time zone,
              investment_principal numeric, migrated_loan_count integer,
              total_given numeric, total_collected numeric, line_balance numeric,
              bf numeric, opening_bf_declared_amount numeric,
              opening_bf_declared_on date)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_owner(p_business_id) AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    b.migration_locked,
    b.business_started_at,
    COALESCE((SELECT SUM(i.original_principal_amount) FROM investments i
              WHERE i.business_id = p_business_id AND i.status = 'Active'
                AND i.deleted_at IS NULL), 0),
    COALESCE((SELECT COUNT(*)::int FROM loans l
              WHERE l.business_id = p_business_id AND l.loan_number LIKE 'LN-MIG-%'
                AND l.deleted_at IS NULL), 0),
    COALESCE((SELECT SUM(l.amount_given) FROM loans l
              WHERE l.business_id = p_business_id AND l.loan_number LIKE 'LN-MIG-%'
                AND l.deleted_at IS NULL), 0),
    COALESCE((SELECT SUM(l.repayment_amount - l.remaining_balance) FROM loans l
              WHERE l.business_id = p_business_id AND l.loan_number LIKE 'LN-MIG-%'
                AND l.deleted_at IS NULL), 0),
    COALESCE((SELECT SUM(l.remaining_balance) FROM loans l
              WHERE l.business_id = p_business_id
                AND l.loan_status NOT IN ('Closed', 'Cancelled', 'Draft')
                AND l.deleted_at IS NULL), 0),
    b.owner_bf_balance,
    b.opening_bf_declared_amount,
    b.opening_bf_declared_on
  FROM businesses b WHERE b.business_id = p_business_id;
END;
$function$;
