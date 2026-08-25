-- What is due today comes from the balance, not from a plan nobody updates.
--
-- v_collection_due summed every Pending loan_schedule row dated on or before
-- today. Nothing ever marks a row Paid -- record_collection updates
-- loans.remaining_balance and does not touch loan_schedule, and neither did
-- the migration replay -- so "Pending" means "was ever scheduled", and the
-- screen asked for every instalment the loan has ever had.
--
-- On the live book it told the Agent that Rs 6,00,000 was due today on a loan
-- whose entire outstanding balance is Rs 5,70,000. next_installment_no was 1
-- on all 56 loans for the same reason: the lowest Pending number is always 1.
-- A customer who has paid 15 of 21 instalments was shown as being on their
-- first.
--
-- This is deliberately NOT fixed by marking schedule rows paid. CLAUDE.md is
-- explicit that there is one remaining_balance per loan and no payment
-- waterfall; adding one here would be a second source of truth for the same
-- money, and the two would drift the first time a collection was deleted.
-- remaining_balance already knows what has been paid, so everything is derived
-- from it:
--
--   paid            = repayment_amount - remaining_balance
--   instalments paid= floor(paid / installment_amount)
--   next instalment = instalments paid + 1
--   due by today    = scheduled dates on or before today (status ignored)
--   total_due       = (due by today - instalments paid) x installment_amount
--
-- CAPPED AT remaining_balance, which is the safety property that matters: the
-- screen can never ask a customer for more than their loan owes, whatever the
-- schedule says. Floored at zero for a customer who has paid ahead.
--
-- BR-112 is preserved -- a part-paid instalment still counts at its full
-- amount -- because instalments_paid uses floor().
--
-- DROP then CREATE, not CREATE OR REPLACE: next_installment_no changes from
-- the schedule's integer to a derived value, and Postgres refuses to change a
-- view column's type in place.
DROP VIEW IF EXISTS app.v_collection_due;

CREATE VIEW app.v_collection_due
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
     -- it is what produced the fault above.
     LEFT JOIN LATERAL ( SELECT
            count(*) FILTER (WHERE s.due_date <= CURRENT_DATE) AS due_by_today,
            min(s.due_date) FILTER (WHERE s.due_date > CURRENT_DATE) AS next_due_date
           FROM loan_schedule s
          WHERE s.loan_id = l.loan_id) sched ON true
  WHERE l.loan_status = ANY (ARRAY['Active'::loan_status_enum, 'Grace Period'::loan_status_enum, 'Penalty'::loan_status_enum]);

GRANT SELECT ON app.v_collection_due TO authenticated, service_role;
