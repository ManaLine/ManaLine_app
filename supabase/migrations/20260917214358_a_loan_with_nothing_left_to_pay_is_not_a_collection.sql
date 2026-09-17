-- Reported from a handset: seven customers on sri satyanarayana business show
-- in the Collections round with Balance Rs 0, each already ticked, and the
-- round's own counter reads "7 of 59 collected" when nothing was collected
-- from them today.
--
-- ONE CAUSE, BOTH SYMPTOMS. app.v_collection_due filters on loan_status but
-- never on remaining_balance, and nothing closes a loan when it is paid off:
-- app.record_collection subtracts from remaining_balance and never sets
-- 'Closed'. app.close_loan exists but is an Owner-only manual action. So a
-- loan paid to zero stays Active for ever, keeps appearing in the round, and
-- -- because it has nothing due -- renders as already done and counts itself
-- into the collected tally.
--
-- Counted before changing anything: 59 live loans on that book, 58 Active and
-- 1 Penalty, of which exactly 7 have remaining_balance = 0. That is the 7 in
-- "7 of 59".
--
-- THE VIEW IS THE DURABLE FIX. A loan with nothing left to pay is not a
-- collection to make, whatever its status says, so the round excludes it on
-- the balance rather than on the status. That way the symptom cannot come back
-- through some other path that forgets to close a loan.
--
-- WHAT THIS DOES NOT FIX, deliberately and named rather than left quiet:
-- record_collection still does not close a loan at zero, so those loans remain
-- 'Active' in the data even though they are finished. That is a lifecycle
-- change on the most important money RPC in this schema, and closing a loan is
-- not only a status -- app.close_loan also stamps recognised_business_date on
-- pending penalty entries, which is what moves penalty income into a day. It
-- needs deciding deliberately, not appending to a display fix.
--
-- The seven rows here are repaired because their repair is provably free of
-- that: checked first, they carry ZERO unrecognised penalty entries between
-- them, so closing them moves no money and recognises no income. A loan with
-- an unrecognised penalty is deliberately left alone by the UPDATE below.

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
    l.grace_period_days > 0 AND l.remaining_balance > 0::numeric AND sched.last_due_date IS NOT NULL AND CURRENT_DATE > sched.last_due_date AND app.loan_penalty_eligible_from(l.loan_id) IS NOT NULL AND app.loan_penalty_eligible_from(l.loan_id) > CURRENT_DATE AS in_grace,
    cyc.result_type AS cycle_result,
    COALESCE(cyc.collected, 0::numeric) AS cycle_collected,
    cyc.first_at AS cycle_first_at,
    visit.reason AS visit_reason_today,
    ext.extended_until
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
     LEFT JOIN LATERAL ( SELECT v.reason
           FROM no_collection_visits v
          WHERE v.loan_id = l.loan_id AND v.business_date = CURRENT_DATE
          ORDER BY v.entry_timestamp DESC
         LIMIT 1) visit ON true
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
                    WHEN t.rows_today > 0 OR visit.reason IS NOT NULL THEN 'No Collection'::text
                    ELSE NULL::text
                END) AS result_type,
            t.collected_today) today
     LEFT JOIN LATERAL ( SELECT max(x.extended_until) AS extended_until
           FROM extension_requests x
          WHERE x.loan_id = l.loan_id AND x.status = 'Approved'::extension_status_enum AND x.extended_until >= CURRENT_DATE) ext ON true
     LEFT JOIN LATERAL app.collection_entry_window(l.collection_agent_membership_id, CURRENT_DATE, l.repayment_type) period(cycle_from, cycle_to, cycle_kind) ON true
     LEFT JOIN LATERAL ( SELECT ( SELECT co.result_type::text AS result_type
                   FROM collections co
                  WHERE co.loan_id = l.loan_id AND co.business_date >= COALESCE(period.cycle_from, CURRENT_DATE) AND co.business_date <= COALESCE(period.cycle_to, CURRENT_DATE) AND co.deleted_at IS NULL AND co.collected_amount > 0::numeric
                  ORDER BY co.entry_timestamp DESC
                 LIMIT 1) AS result_type,
            COALESCE(sum(co3.collected_amount), 0::numeric) AS collected,
            min(co3.entry_timestamp) AS first_at
           FROM collections co3
          WHERE co3.loan_id = l.loan_id AND co3.business_date >= COALESCE(period.cycle_from, CURRENT_DATE) AND co3.business_date <= COALESCE(period.cycle_to, CURRENT_DATE) AND co3.deleted_at IS NULL AND co3.collected_amount > 0::numeric) cyc ON true
     LEFT JOIN LATERAL ( SELECT loc.village_town_name
           FROM person_addresses pa
             JOIN locations loc ON loc.location_id = pa.village_id
          WHERE pa.person_id = c.person_id AND pa.is_current = true
         LIMIT 1) addr ON true
     LEFT JOIN business_members abm ON abm.membership_id = l.collection_agent_membership_id
     LEFT JOIN persons abm_person ON abm_person.person_id = abm.person_id
  WHERE l.deleted_at IS NULL
    AND (l.loan_status = ANY (ARRAY['Active'::loan_status_enum, 'Grace Period'::loan_status_enum, 'Penalty'::loan_status_enum]))
    -- THE NEW LINE. Nothing left to pay is nothing to collect.
    AND l.remaining_balance > 0::numeric;

-- The seven finished loans, told they are finished.
--
-- Status only. remaining_balance is already 0 and is not touched; closed_at is
-- stamped because a Closed loan with no closing time is a row that cannot say
-- when it ended. The penalty guard makes this a no-op for any loan whose
-- closure would recognise income -- there are none today, and if that ever
-- changes this migration must not be the thing that decides it.
UPDATE loans l
   SET loan_status = 'Closed',
       closed_at   = COALESCE(closed_at, now()),
       updated_at  = now()
 WHERE l.deleted_at IS NULL
   AND l.remaining_balance = 0
   AND l.loan_status IN ('Active', 'Grace Period', 'Penalty')
   AND NOT EXISTS (SELECT 1 FROM penalty_entries pe
                    WHERE pe.loan_id = l.loan_id
                      AND pe.recognised_business_date IS NULL
                      AND pe.penalty_amount_applied > 0);

DO $$
DECLARE v_left INT; v_in_view INT;
BEGIN
  SELECT count(*) INTO v_left FROM loans
   WHERE deleted_at IS NULL AND remaining_balance = 0
     AND loan_status IN ('Active','Grace Period','Penalty');
  IF v_left <> 0 THEN
    RAISE NOTICE '% paid-off loan(s) left open because they carry an '
                 'unrecognised penalty', v_left;
  END IF;

  SELECT count(*) INTO v_in_view FROM app.v_collection_due
   WHERE remaining_balance <= 0;
  IF v_in_view <> 0 THEN
    RAISE EXCEPTION 'the round still offers % loan(s) with nothing to pay',
      v_in_view;
  END IF;
END $$;
