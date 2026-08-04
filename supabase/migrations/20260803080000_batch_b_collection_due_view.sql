-- =============================================================================
-- BATCH B (2/3) — v_collection_due, the real due list (#18)
-- =============================================================================
-- WHAT THIS FILE DOES:
--   The app's collection due list was assembled client-side from a loans
--   query, with three KNOWN SIMPLIFICATIONS: installmentDue was just the
--   installment_amount, lineRepaymentIndex was always 0, and collectionStatus
--   was always 'Pending'. This view replaces that guesswork with the server's
--   own arithmetic over loan_schedule:
--
--     total_due          = SUM of Pending installments due up to today
--                          (a missed installment stays due — the amount you
--                          actually collect today is the catch-up).
--     next_installment_no = the lowest Pending installment_number.
--     is_overdue          = any Pending installment dated strictly before
--                          today.
--     penalty_eligible    = remaining_balance > 0 AND the loan's penalty
--                          window (last due + grace + 1, app.loan_penalty_
--                          eligible_from) has opened.
--
--   BR-112 FLAG, faithfully preserved: a PARTIAL collection does not advance
--   an installment — loan_schedule.status flips to Completed only on full
--   completion (see its table comment). So total_due counts a partially-paid
--   installment at its full amount, not the unpaid remainder. That is the
--   model's own rule, not a bug to patch here.
--
--   SECURITY: security_invoker = true, so this view is scoped by the
--   underlying tables' RLS. For an Agent that means app.agent_covers_customer
--   (M4) — an agent sees exactly their areas' due loans; the Owner sees the
--   whole business. No view-level policy needed, and no policy can drift out
--   of sync with the tables.
-- -----------------------------------------------------------------------------

CREATE VIEW app.v_collection_due
WITH (security_invoker = true)
AS
SELECT
  l.loan_id,
  l.business_id,
  l.customer_id,
  c.membership_id AS customer_membership_id,
  p.full_name AS customer_name,
  COALESCE(addr.village_town_name, '') AS village,
  l.loan_number,
  l.installment_amount,
  l.remaining_balance,
  l.loan_status,
  l.collection_agent_membership_id,
  abm_person.full_name AS collection_agent_name,
  COALESCE(sched.next_installment_no, 1) AS next_installment_no,
  sched.next_due_date,
  COALESCE(sched.total_due, 0) AS total_due,
  COALESCE(sched.is_overdue, false) AS is_overdue,
  (l.remaining_balance > 0
   AND app.loan_penalty_eligible_from(l.loan_id) IS NOT NULL
   AND app.loan_penalty_eligible_from(l.loan_id) <= CURRENT_DATE) AS penalty_eligible
FROM loans l
JOIN customers c ON c.customer_id = l.customer_id
JOIN persons p ON p.person_id = c.person_id
LEFT JOIN LATERAL (
  SELECT loc.village_town_name
  FROM person_addresses pa
  JOIN locations loc ON loc.location_id = pa.village_id
  WHERE pa.person_id = c.person_id AND pa.is_current = TRUE
  LIMIT 1
) addr ON true
LEFT JOIN business_members abm ON abm.membership_id = l.collection_agent_membership_id
LEFT JOIN persons abm_person ON abm_person.person_id = abm.person_id
LEFT JOIN LATERAL (
  SELECT
    MIN(s.installment_number) AS next_installment_no,
    MIN(s.due_date) AS next_due_date,
    SUM(s.installment_amount) FILTER (WHERE s.due_date <= CURRENT_DATE) AS total_due,
    BOOL_OR(s.due_date < CURRENT_DATE) AS is_overdue
  FROM loan_schedule s
  WHERE s.loan_id = l.loan_id AND s.status = 'Pending'
) sched ON true
WHERE l.loan_status IN ('Active', 'Grace Period', 'Penalty');

COMMENT ON VIEW app.v_collection_due IS
  'One row per collectable loan. total_due sums Pending installments due up to today; BR-112 means a partially-paid installment still counts in full. security_invoker: Agent rows are scoped by loans/customers RLS (app.agent_covers_customer), Owner rows by is_owner.';

GRANT SELECT ON app.v_collection_due TO authenticated;
