-- Locking says what was promised and never arrived.
--
-- lock_migration had no preconditions at all beyond ownership: it would close
-- a book with no loans, no BF and no weekly sheet as readily as a finished
-- one, and closing is the point past which imports are refused. Nothing asked
-- whether the Owner had done what they set out to do.
--
-- Now that the plan says which sections apply, the gap between what was
-- promised and what is there can be named. Returned, NOT enforced: an Owner
-- who ticked "weekly account book" and then decided against it is allowed to
-- lock, and the screen puts the list in front of them first. A hard block here
-- would strand a book over a tick made ten minutes earlier.
CREATE OR REPLACE FUNCTION app.migration_plan_gaps(p_business_id uuid)
RETURNS TABLE(section text, promised boolean, present integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_plan jsonb;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(migration_plan, '{}'::jsonb) INTO v_plan
    FROM businesses WHERE business_id = p_business_id;

  RETURN QUERY
  SELECT 'identities'::text,
         true,
         (SELECT count(*)::int FROM business_members bm
           WHERE bm.business_id = p_business_id
             AND bm.membership_status <> 'Removed')
  UNION ALL
  SELECT 'investors',
         COALESCE((v_plan ->> 'investors')::boolean, false),
         (SELECT count(*)::int FROM investments i
           WHERE i.business_id = p_business_id AND i.deleted_at IS NULL)
  UNION ALL
  SELECT 'shareholders',
         COALESCE((v_plan ->> 'shareholders')::boolean, false),
         (SELECT count(*)::int FROM migration_shareholders s
           WHERE s.business_id = p_business_id)
  UNION ALL
  SELECT 'customers',
         COALESCE((v_plan ->> 'customers')::boolean, false),
         (SELECT count(*)::int FROM loans l
           WHERE l.business_id = p_business_id AND l.deleted_at IS NULL)
  UNION ALL
  SELECT 'emi_history',
         COALESCE((v_plan ->> 'emi_history')::boolean, false),
         (SELECT count(*)::int FROM collections c
            JOIN loans l ON l.loan_id = c.loan_id
           WHERE l.business_id = p_business_id
             AND c.deleted_at IS NULL AND l.deleted_at IS NULL)
  UNION ALL
  SELECT 'attendance',
         COALESCE((v_plan ->> 'attendance')::boolean, false),
         (SELECT count(*)::int FROM agent_access_days a
            JOIN business_members m ON m.membership_id = a.membership_id
           WHERE m.business_id = p_business_id)
  UNION ALL
  SELECT 'weekly',
         COALESCE((v_plan ->> 'weekly')::boolean, false),
         (SELECT count(*)::int FROM migration_weeks w
           WHERE w.business_id = p_business_id)
  UNION ALL
  SELECT 'snapshot',
         true,
         (SELECT count(*)::int FROM migration_snapshots s
           WHERE s.business_id = p_business_id);
END;
$$;

GRANT EXECUTE ON FUNCTION app.migration_plan_gaps(uuid) TO authenticated, service_role;
