-- A deleted loan is not due today.
--
-- v_collection_due filtered on loan_status alone. A soft delete does not
-- change loan_status, so every loan ever deleted stayed in the collection
-- round: on the live book that is 164 rows for a business with 56 live loans,
-- 108 of them belonging to loans that no longer exist.
--
-- This is the worst place in the app for that fault to live. The Agent works
-- the round off this list, house by house. It would send them to collect
-- against loans the Owner had already removed, and the money would arrive
-- with nothing to attach it to.
--
-- Found while crosschecking the 85-customers count, which was the same shape
-- of mistake seen from a different angle: the row is still there, and exactly
-- one column says it should not be counted.
CREATE OR REPLACE VIEW app.v_collection_due
WITH (security_invoker = true) AS
SELECT l.loan_id,
    l.business_id,
    l.customer_id,
    c.membership_id AS customer_membership_id,
    p.full_name AS customer_name,
    COALESCE(addr.village_town_name, ''::character varying) AS village,
    l.loan_number,
    l.installment_amount,
    l.remaining_balance,
    l.loan_status,
    l.collection_agent_membership_id,
    abm_person.full_name AS collection_agent_name,
    (paid.instalments_paid + 1)::integer AS next_installment_no,
    sched.next_due_date,
    LEAST(
      GREATEST(
        (COALESCE(sched.due_by_today, 0) - paid.instalments_paid)
          * l.installment_amount,
        0::numeric),
      l.remaining_balance
    ) AS total_due,
    COALESCE(sched.due_by_today, 0) > paid.instalments_paid AS is_overdue,
    l.remaining_balance > 0::numeric
      AND app.loan_penalty_eligible_from(l.loan_id) IS NOT NULL
      AND app.loan_penalty_eligible_from(l.loan_id) <= CURRENT_DATE AS penalty_eligible,
    l.repayment_type
   FROM loans l
     JOIN customers c ON c.customer_id = l.customer_id
     JOIN persons p ON p.person_id = c.person_id
     -- What the balance says has already been paid.
     CROSS JOIN LATERAL (
       SELECT CASE WHEN l.installment_amount > 0
                   THEN floor((l.repayment_amount - l.remaining_balance)
                              / l.installment_amount)
                   ELSE 0 END AS instalments_paid) paid
     LEFT JOIN LATERAL ( SELECT loc.village_town_name
           FROM person_addresses pa
             JOIN locations loc ON loc.location_id = pa.village_id
          WHERE pa.person_id = c.person_id AND pa.is_current = true
         LIMIT 1) addr ON true
     LEFT JOIN business_members abm ON abm.membership_id = l.collection_agent_membership_id
     LEFT JOIN persons abm_person ON abm_person.person_id = abm.person_id
     -- Dates only. Status is ignored on purpose: it never changes, so reading
     -- it is what produced the overstated due figures.
     LEFT JOIN LATERAL ( SELECT
            count(*) FILTER (WHERE s.due_date <= CURRENT_DATE) AS due_by_today,
            min(s.due_date) FILTER (WHERE s.due_date > CURRENT_DATE) AS next_due_date
           FROM loan_schedule s
          WHERE s.loan_id = l.loan_id) sched ON true
  WHERE l.deleted_at IS NULL
    AND l.loan_status = ANY (ARRAY['Active'::loan_status_enum, 'Grace Period'::loan_status_enum, 'Penalty'::loan_status_enum]);

GRANT SELECT ON app.v_collection_due TO authenticated, service_role;
