-- What the migration wizard has actually put in, counted from the live rows.
--
-- WHY: the wizard's pages remember nothing across a sitting. Go back a page —
-- or come back tomorrow, when the resume pointer drops you on page 5 — and
-- every page looks untouched, whether it holds 55 customers or none. An Owner
-- with no way to see what is already in has exactly one way to find out, which
-- is to import it again. That is how this business ended up with its whole
-- book twice on 22 Aug 2026.
--
-- COUNTED, NOT REMEMBERED. A stored "page 4 done" flag would go stale the
-- moment anything is deleted or added outside the wizard. These are the rows
-- themselves, so the summary cannot claim work that is not there.
--
-- Soft-deleted rows are excluded everywhere they exist (loans, collections,
-- investments, members, area locations) — a deleted loan is not in the book.
CREATE OR REPLACE FUNCTION app.migration_progress(p_business_id uuid)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v json;
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.agent_permission(p_business_id, 'can_migrate_records') THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  SELECT json_build_object(
    'customers', (SELECT count(*) FROM business_members WHERE business_id=p_business_id AND role='Customer' AND removed_at IS NULL),
    'investors', (SELECT count(*) FROM business_members WHERE business_id=p_business_id AND role='Investor' AND removed_at IS NULL),
    'agents',    (SELECT count(*) FROM business_members WHERE business_id=p_business_id AND role='Agent' AND removed_at IS NULL),
    'villages',  (SELECT count(*) FROM operating_area_locations WHERE business_id=p_business_id AND removed_at IS NULL),
    'areas',     (SELECT count(*) FROM operating_areas WHERE business_id=p_business_id AND status='Active'),
    'investments',       (SELECT count(*) FROM investments WHERE business_id=p_business_id AND deleted_at IS NULL),
    'investment_amount', (SELECT COALESCE(sum(principal_amount),0)::bigint FROM investments WHERE business_id=p_business_id AND deleted_at IS NULL),
    'loans',       (SELECT count(*) FROM loans WHERE business_id=p_business_id AND deleted_at IS NULL),
    'loans_open',  (SELECT count(*) FROM loans WHERE business_id=p_business_id AND deleted_at IS NULL AND remaining_balance > 0),
    'line_balance',(SELECT COALESCE(sum(remaining_balance),0)::bigint FROM loans WHERE business_id=p_business_id AND deleted_at IS NULL),
    'collections', (SELECT count(*) FROM collections c JOIN loans l ON l.loan_id=c.loan_id
                     WHERE l.business_id=p_business_id AND c.deleted_at IS NULL),
    'attendance_days', (SELECT count(*) FROM agent_access_days d JOIN business_members m ON m.membership_id=d.membership_id
                         WHERE m.business_id=p_business_id),
    'snapshot_cutoff',  (SELECT max(cutoff_date)::text FROM migration_snapshots WHERE business_id=p_business_id),
    'shareholders',     (SELECT count(*) FROM migration_shareholders WHERE business_id=p_business_id),
    'weeks',            (SELECT count(*) FROM migration_weeks WHERE business_id=p_business_id),
    'weeks_through',    (SELECT max(account_date)::text FROM migration_weeks WHERE business_id=p_business_id)
  ) INTO v;
  RETURN v;
END;
$$;

GRANT EXECUTE ON FUNCTION app.migration_progress(uuid) TO authenticated, service_role;
