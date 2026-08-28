-- The round measures the window the server measures.
--
-- Both sides had their own copy of "which account period covers today", and
-- the copies diverged the moment app.account_period_window started treating a
-- Running period as open-ended while this view still stopped at the planned
-- end. On a business whose periods are planned for four days and worked for
-- seven, the round would have called Saturday a fresh day while
-- record_collection called it the same cycle -- so the round offered Collect
-- and the server answered already_recorded.
--
-- One definition now, called from both.
--
-- Supersedes 20260828120019.
CREATE OR REPLACE VIEW app.v_collection_due AS
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
    (paid.instalments_paid + 1::numeric)::integer AS next_installment_no,
    sched.next_due_date,
    LEAST(GREATEST((COALESCE(sched.due_by_today, 0::bigint)::numeric - paid.instalments_paid) * l.installment_amount, 0::numeric), l.remaining_balance) AS total_due,
    COALESCE(sched.due_by_today, 0::bigint)::numeric > paid.instalments_paid AS is_overdue,
    l.remaining_balance > 0::numeric AND app.loan_penalty_eligible_from(l.loan_id) IS NOT NULL AND app.loan_penalty_eligible_from(l.loan_id) <= CURRENT_DATE AS penalty_eligible,
    l.repayment_type,
    COALESCE(p.mlid, ''::character varying) AS mlid,
    today.result_type AS today_result,
    COALESCE(today.collected_today, 0::numeric) AS collected_today,
    l.grace_period_days,
    (l.grace_period_days > 0
       AND l.remaining_balance > 0::numeric
       AND sched.last_due_date IS NOT NULL
       AND CURRENT_DATE > sched.last_due_date
       AND app.loan_penalty_eligible_from(l.loan_id) IS NOT NULL
       AND app.loan_penalty_eligible_from(l.loan_id) > CURRENT_DATE) AS in_grace,
    cyc.result_type AS cycle_result,
    COALESCE(cyc.collected, 0::numeric) AS cycle_collected,
    cyc.first_at AS cycle_first_at
   FROM loans l
     JOIN customers c ON c.customer_id = l.customer_id
     JOIN persons p ON p.person_id = c.person_id
     LEFT JOIN LATERAL ( SELECT count(*) FILTER (WHERE s.due_date <= CURRENT_DATE) AS due_by_today,
            min(s.due_date) FILTER (WHERE s.due_date > CURRENT_DATE) AS next_due_date,
            max(s.due_date) AS last_due_date,
            COALESCE(sum(s.installment_amount), 0::numeric) AS scheduled_total,
            count(*) AS rows_total
           FROM loan_schedule s
          WHERE s.loan_id = l.loan_id) sched ON true
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN l.installment_amount > 0::numeric AND COALESCE(sched.rows_total, 0::bigint) > 0 THEN GREATEST(floor((sched.scheduled_total - l.remaining_balance) / l.installment_amount), 0::numeric)
                    ELSE 0::numeric
                END AS instalments_paid) paid
     LEFT JOIN LATERAL ( SELECT ( SELECT co.result_type::text AS result_type
                   FROM collections co
                  WHERE co.loan_id = l.loan_id AND co.business_date = CURRENT_DATE AND co.deleted_at IS NULL AND co.collected_amount > 0::numeric
                  ORDER BY co.entry_timestamp DESC
                 LIMIT 1) AS paid_result,
            COALESCE(sum(co2.collected_amount), 0::numeric) AS collected_today,
            count(*) AS rows_today
           FROM collections co2
          WHERE co2.loan_id = l.loan_id AND co2.business_date = CURRENT_DATE AND co2.deleted_at IS NULL) t ON true
     CROSS JOIN LATERAL ( SELECT COALESCE(t.paid_result,
                CASE
                    WHEN t.rows_today > 0 THEN 'No Collection'::text
                    ELSE NULL::text
                END) AS result_type,
            t.collected_today) today
     -- The window the one-entry rule measures for this loan: the collecting
     -- agent's open account period, or today when none covers it.
     LEFT JOIN LATERAL app.account_period_window(
            l.collection_agent_membership_id, CURRENT_DATE) period ON true
     LEFT JOIN LATERAL ( SELECT ( SELECT co.result_type::text
                   FROM collections co
                  WHERE co.loan_id = l.loan_id
                    AND co.business_date BETWEEN COALESCE(period.cycle_from, CURRENT_DATE) AND COALESCE(period.cycle_to, CURRENT_DATE)
                    AND co.deleted_at IS NULL AND co.collected_amount > 0::numeric
                  ORDER BY co.entry_timestamp DESC
                 LIMIT 1) AS result_type,
            COALESCE(sum(co3.collected_amount), 0::numeric) AS collected,
            min(co3.entry_timestamp) AS first_at
           FROM collections co3
          WHERE co3.loan_id = l.loan_id
            AND co3.business_date BETWEEN COALESCE(period.cycle_from, CURRENT_DATE) AND COALESCE(period.cycle_to, CURRENT_DATE)
            AND co3.deleted_at IS NULL AND co3.collected_amount > 0::numeric) cyc ON true
     LEFT JOIN LATERAL ( SELECT loc.village_town_name
           FROM person_addresses pa
             JOIN locations loc ON loc.location_id = pa.village_id
          WHERE pa.person_id = c.person_id AND pa.is_current = true
         LIMIT 1) addr ON true
     LEFT JOIN business_members abm ON abm.membership_id = l.collection_agent_membership_id
     LEFT JOIN persons abm_person ON abm_person.person_id = abm.person_id
  WHERE l.deleted_at IS NULL AND (l.loan_status = ANY (ARRAY['Active'::loan_status_enum, 'Grace Period'::loan_status_enum, 'Penalty'::loan_status_enum]));
