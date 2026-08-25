-- A migrated loan's schedule is what is LEFT, not the whole term.
--
-- Yesterday's fix derived "instalments already paid" from
-- (repayment_amount - remaining_balance). That is right for a loan this app
-- issued, whose schedule covers the full term from day one. It is wrong for a
-- migrated loan, because the import materialises only the instalments still to
-- come: Garikipati Kamala Reddy borrowed Rs 24,000, paid Rs 12,000 before the
-- cut-off, and her schedule holds six rows of Rs 2,000 -- exactly the
-- Rs 12,000 she still owes.
--
-- So the payments were counted twice. Six paid, subtracted from a schedule
-- that already excluded them, left nothing due, and the round asked her for
-- Rs 0 while she owed Rs 12,000. The Agent would have walked past the door.
-- Karri Rajesh Kumar was understated the same way, Rs 78,000 against
-- Rs 1,02,000 outstanding.
--
-- The base is the SCHEDULE's own total, not the loan's repayment amount:
--
--   * issued here      -> schedule totals the repayment, so this is unchanged
--   * migrated         -> schedule totals the balance, so nothing reads as
--                         already paid, and the rows themselves say what is due
--
-- On the live book 54 of 56 loans carry a full schedule and do not move; the
-- 5 partial ones are the migrated shape, and only these two were being
-- understated. Both change in the safe direction -- the app was asking for
-- LESS than was owed, which is the kind of wrong nobody reports.
--
-- Guarded for a loan with no schedule at all: nothing is scheduled, so nothing
-- is due today. Without the guard the arithmetic would run negative and
-- demand the entire balance.
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
    l.repayment_type,
    COALESCE(p.mlid, ''::character varying) AS mlid
   FROM loans l
     JOIN customers c ON c.customer_id = l.customer_id
     JOIN persons p ON p.person_id = c.person_id
     -- Dates and totals from the schedule itself. Status is ignored on
     -- purpose: nothing ever marks a row Paid, so reading it is what
     -- overstated every due figure before.
     LEFT JOIN LATERAL ( SELECT
            count(*) FILTER (WHERE s.due_date <= CURRENT_DATE) AS due_by_today,
            min(s.due_date) FILTER (WHERE s.due_date > CURRENT_DATE) AS next_due_date,
            COALESCE(sum(s.installment_amount), 0) AS scheduled_total,
            count(*) AS rows_total
           FROM loan_schedule s
          WHERE s.loan_id = l.loan_id) sched ON true
     -- What THIS SCHEDULE says has already been paid.
     CROSS JOIN LATERAL (
       SELECT CASE WHEN l.installment_amount > 0 AND COALESCE(sched.rows_total, 0) > 0
                   THEN GREATEST(
                          floor((sched.scheduled_total - l.remaining_balance)
                                / l.installment_amount),
                          0)
                   ELSE 0 END AS instalments_paid) paid
     LEFT JOIN LATERAL ( SELECT loc.village_town_name
           FROM person_addresses pa
             JOIN locations loc ON loc.location_id = pa.village_id
          WHERE pa.person_id = c.person_id AND pa.is_current = true
         LIMIT 1) addr ON true
     LEFT JOIN business_members abm ON abm.membership_id = l.collection_agent_membership_id
     LEFT JOIN persons abm_person ON abm_person.person_id = abm.person_id
  WHERE l.deleted_at IS NULL
    AND l.loan_status = ANY (ARRAY['Active'::loan_status_enum, 'Grace Period'::loan_status_enum, 'Penalty'::loan_status_enum]);

GRANT SELECT ON app.v_collection_due TO authenticated, service_role;
