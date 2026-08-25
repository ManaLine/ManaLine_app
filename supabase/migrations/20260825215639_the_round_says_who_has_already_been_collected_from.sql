-- The round says who has already been collected from today.
--
-- CollectionDueRow.collectionStatus was the literal string 'Pending' for every
-- row, with a comment saying the view has no collections join "by design". The
-- effect: after recording a payment the row looked exactly as it had before,
-- the tick never appeared, and the Collected / Skipped counters read 0
-- forever. An Agent halfway through a round had nothing on screen telling them
-- which doors they had already knocked on.
--
-- That mattered less when Pay pushed a separate screen, because the screen
-- itself was the acknowledgement. Now that the row opens in place and closes
-- again, the row IS the feedback, and it was saying nothing.
--
-- The classification is not recomputed here. record_collection already decides
-- Full / Partial / Excess server-side and writes it to result_type; this reads
-- that back. Re-deriving it from amounts would be a second opinion on a
-- question already answered, and the two would disagree the first time a rule
-- changed.
--
-- The LATEST payment of the day wins. An Agent who records "No Collection" and
-- then actually collects has collected; taking the last row rather than the
-- first is what makes that read correctly. A day with only a No Collection row
-- is a visit without payment, which is a different fact from not having gone.
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
    COALESCE(p.mlid, ''::character varying) AS mlid,
    today.result_type AS today_result,
    COALESCE(today.collected_today, 0) AS collected_today
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
     -- Today's outcome at this door, as the server classified it.
     LEFT JOIN LATERAL (
       SELECT
         (SELECT co.result_type::text
            FROM collections co
           WHERE co.loan_id = l.loan_id
             AND co.business_date = CURRENT_DATE
             AND co.deleted_at IS NULL
             AND co.collected_amount > 0
           ORDER BY co.entry_timestamp DESC
           LIMIT 1) AS paid_result,
         COALESCE(SUM(co2.collected_amount), 0) AS collected_today,
         count(*) AS rows_today
       FROM collections co2
      WHERE co2.loan_id = l.loan_id
        AND co2.business_date = CURRENT_DATE
        AND co2.deleted_at IS NULL) t ON true
     CROSS JOIN LATERAL (
       SELECT COALESCE(
                t.paid_result,
                CASE WHEN t.rows_today > 0 THEN 'No Collection' END
              ) AS result_type,
              t.collected_today) today
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
