-- Collection mode is worked village by village, and a Daily line and a
-- Monthly line are not collected on the same trip. The due list could show
-- neither: repayment_type was on `loans` but never surfaced, so the screen had
-- nothing to group or filter by.
--
-- Column added at the end so ordinal-position readers are unaffected; the
-- view stays security_invoker, so an Agent still sees only their areas.
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
    COALESCE(sched.next_installment_no, 1) AS next_installment_no,
    sched.next_due_date,
    COALESCE(sched.total_due, 0::numeric) AS total_due,
    COALESCE(sched.is_overdue, false) AS is_overdue,
    l.remaining_balance > 0::numeric
      AND app.loan_penalty_eligible_from(l.loan_id) IS NOT NULL
      AND app.loan_penalty_eligible_from(l.loan_id) <= CURRENT_DATE AS penalty_eligible,
    l.repayment_type
   FROM loans l
     JOIN customers c ON c.customer_id = l.customer_id
     JOIN persons p ON p.person_id = c.person_id
     LEFT JOIN LATERAL ( SELECT loc.village_town_name
           FROM person_addresses pa
             JOIN locations loc ON loc.location_id = pa.village_id
          WHERE pa.person_id = c.person_id AND pa.is_current = true
         LIMIT 1) addr ON true
     LEFT JOIN business_members abm ON abm.membership_id = l.collection_agent_membership_id
     LEFT JOIN persons abm_person ON abm_person.person_id = abm.person_id
     LEFT JOIN LATERAL ( SELECT min(s.installment_number) AS next_installment_no,
            min(s.due_date) AS next_due_date,
            sum(s.installment_amount) FILTER (WHERE s.due_date <= CURRENT_DATE) AS total_due,
            bool_or(s.due_date < CURRENT_DATE) AS is_overdue
           FROM loan_schedule s
          WHERE s.loan_id = l.loan_id AND s.status = 'Pending'::loan_schedule_status_enum) sched ON true
  WHERE l.loan_status = ANY (ARRAY['Active'::loan_status_enum, 'Grace Period'::loan_status_enum, 'Penalty'::loan_status_enum]);
