-- An agent could still see customers in a village their area no longer works.
--
-- operating_area_locations is soft deleted. Both of the functions that decide
-- an agent's reach joined it without asking:
--
--   JOIN operating_area_locations oal ON oal.location_id = pa.village_id
--
-- so a village REMOVED from an area went on conferring that area's agents,
-- for as long as the row sat there with a removed_at on it. Every other reader
-- of this table filters it -- migration_create_areas, migration_progress,
-- deactivate_operating_area, remove_operating_area, migration_customer_
-- positions -- and the unique index that lets a village be re-attached
-- somewhere else is partial on exactly this column:
--
--   uq_oal_business_location ON (business_id, location_id) WHERE removed_at IS NULL
--
-- So the table has always meant "removed", and these two functions were the
-- pair that did not read it that way. Removing a village from an area was not
-- the removal it looked like: the customers stayed visible, and stayed
-- attributable, to the agents of an area that had given them up.
--
-- HOW IT WAS FOUND, which matters because nobody reported it. Building the
-- village merge, the Owner's rule was that a merge move nothing but the
-- address. The test was to run the merge in a rolled-back transaction and
-- compare every customer's loan count, outstanding balance and collecting
-- agent before and after. Balances never moved. THREE AGENTS DID -- the two
-- people who changed village, one of whom is a customer of two books. The
-- merge was correct; the coverage it was measured against was reading deleted
-- rows.
--
-- THIS IS AN AGENT-VISIBILITY PATH AND IT HAS THIRTY CONSUMERS. 25 RLS
-- policies -- customers, loans, collections, collection_payment_splits,
-- penalty_entries, extension_requests, guarantors, loan_requests,
-- loan_schedule, loan_group_members, loan_cancellations, no_collection_visits,
-- customer_remarks, customer_documents, customer_online_payments,
-- business_members, and two storage.objects policies -- plus agent_covers_loan,
-- can_apply_penalty_on_loan, agent_update_customer_address,
-- agent_update_customer_phone and migrate_loan. All of them read the same
-- predicate, so all of them narrow identically; none of them needed changing.
--
-- MEASURED BEFORE APPLYING, because narrowing a visibility rule is how an
-- agent arrives at a door and finds the customer gone from their list:
--
--   customers with any agent coverage at all                      91
--   customers whose ONLY coverage runs through a removed link      0
--
-- Zero. No agent loses a customer today. What changes is that the next village
-- an Owner takes off an area actually comes off it.
--
-- Raised with the Owner before applying, with that measurement and the
-- alternative -- leave these two alone and make the merge refuse instead --
-- and they chose the fix.

CREATE OR REPLACE FUNCTION app.agent_covers_customer(p_customer_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, app
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM customers c
    JOIN person_addresses pa
      ON pa.person_id = c.person_id AND pa.is_current = TRUE
    JOIN operating_area_locations oal
      ON oal.location_id = pa.village_id
      AND oal.removed_at IS NULL
    JOIN operating_areas oa
      ON oa.operating_area_id = oal.operating_area_id
    JOIN agent_area_assignments aaa
      ON aaa.operating_area_id = oa.operating_area_id
      AND aaa.removed_at IS NULL
      AND COALESCE(aaa.valid_from, CURRENT_DATE) <= CURRENT_DATE
      AND (aaa.valid_to IS NULL OR aaa.valid_to >= CURRENT_DATE)
    JOIN agents ag ON ag.agent_id = aaa.agent_id
    JOIN business_members bm ON bm.membership_id = ag.membership_id
    WHERE c.customer_id = p_customer_id
      AND bm.person_id = app.current_person_id()
      AND bm.membership_status = 'Active'
      AND bm.role = 'Agent'
  );
$$;

CREATE OR REPLACE FUNCTION app.covering_agent_membership_id(p_customer_id uuid)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, app
AS $$
  SELECT bm.membership_id
  FROM customers c
  JOIN person_addresses pa
    ON pa.person_id = c.person_id AND pa.is_current = TRUE
  JOIN operating_area_locations oal
    ON oal.location_id = pa.village_id
    AND oal.removed_at IS NULL
  JOIN operating_areas oa
    ON oa.operating_area_id = oal.operating_area_id
  JOIN agent_area_assignments aaa
    ON aaa.operating_area_id = oa.operating_area_id
    AND aaa.removed_at IS NULL
    AND COALESCE(aaa.valid_from, CURRENT_DATE) <= CURRENT_DATE
    AND (aaa.valid_to IS NULL OR aaa.valid_to >= CURRENT_DATE)
  JOIN agents ag ON ag.agent_id = aaa.agent_id
  JOIN business_members bm ON bm.membership_id = ag.membership_id
  WHERE c.customer_id = p_customer_id
    AND bm.membership_status = 'Active'
  ORDER BY aaa.valid_from DESC NULLS LAST
  LIMIT 1;
$$;
