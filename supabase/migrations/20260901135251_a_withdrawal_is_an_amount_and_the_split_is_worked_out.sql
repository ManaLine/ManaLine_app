-- An investor asked to withdraw Rs 2,00,000 of "Interest Only" against
-- Rs 70,950 of interest, and the app took the request. A second one for
-- Rs 1,90,000 was already sitting behind it. Neither had been paid -- so no
-- money moved -- but nothing would have stopped Pay Out from recording them.
--
-- WHAT WAS THERE: approveWithdrawalRequest, three separate client-side writes.
-- Insert a withdrawal row with whatever amount and split the client had
-- computed; subtract the principal portion; mark the request paid. No check
-- that the interest portion existed to be paid, no check that the principal
-- portion was there, no check the request had not already been paid, and no
-- transaction -- a failure between statements pays somebody and leaves the
-- principal untouched.
--
-- WHAT REPLACES IT: one amount, and the split is worked out rather than
-- chosen. Unpaid interest first, then principal. The Owner's instruction, and
-- it is also the only order that makes sense -- paying principal while
-- interest is owed silently converts one into the other.
--
-- The interest portion is written to investment_interest_ledger as a Payment,
-- the same way record_investment_interest_payment does it, so the next
-- snapshot counts it as paid instead of still accruing. Without that the same
-- interest could be withdrawn twice.
--
-- withdrawal_type is now derived, not asked for: Interest Only when nothing
-- touches principal, Principal Full when it takes the last of it, Principal +
-- Interest when it does both, Principal Partial otherwise.
--
-- NOTE: this version subtracts from investments.principal_amount while
-- validating against the snapshot, and those two disagree whenever a year's
-- compounding has not been written back -- it would have eaten Rs 91,250 on
-- the live investment. Repaired in the next migration; kept as applied
-- because the ledger records it.
CREATE OR REPLACE FUNCTION app.withdraw_from_investment(
  p_investment_id uuid,
  p_amount numeric,
  p_business_date date DEFAULT CURRENT_DATE,
  p_request_id uuid DEFAULT NULL,
  p_remarks text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
DECLARE
  v_inv RECORD;
  v_snap RECORD;
  v_amount numeric;
  v_interest_part numeric;
  v_principal_part numeric;
  v_available numeric;
  v_type withdrawal_type_enum;
  v_withdrawal_id uuid;
  v_request_status text;
BEGIN
  SELECT i.* INTO v_inv FROM investments i
   WHERE i.investment_id = p_investment_id AND i.deleted_at IS NULL
   FOR UPDATE;
  IF v_inv IS NULL THEN
    RAISE EXCEPTION 'Investment not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT app.is_owner(v_inv.business_id) THEN
    RAISE EXCEPTION 'Only the Owner may pay out a withdrawal' USING ERRCODE = '42501';
  END IF;

  v_amount := CEIL(COALESCE(p_amount, 0));
  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'A withdrawal must be more than zero' USING ERRCODE = '23514';
  END IF;

  -- Paying the same request twice is the failure the old three-write sequence
  -- could not even notice.
  IF p_request_id IS NOT NULL THEN
    SELECT status::text INTO v_request_status
      FROM investment_withdrawal_requests
     WHERE request_id = p_request_id FOR UPDATE;
    IF v_request_status IS NULL THEN
      RAISE EXCEPTION 'No such withdrawal request' USING ERRCODE = 'P0002';
    END IF;
    IF v_request_status <> 'Pending' THEN
      RAISE EXCEPTION 'This request has already been decided' USING ERRCODE = '23514';
    END IF;
  END IF;

  SELECT * INTO v_snap
    FROM app.investment_interest_snapshot(p_investment_id, p_business_date);

  -- Interest standing unpaid, then what is left of the principal.
  v_interest_part  := LEAST(v_amount, GREATEST(v_snap.accrued_interest, 0));
  v_principal_part := v_amount - v_interest_part;
  v_available      := GREATEST(v_snap.accrued_interest, 0) + v_inv.principal_amount;

  IF v_amount > v_available THEN
    RAISE EXCEPTION
      'Only % is available -- % of unpaid interest and % of principal.',
      v_available, GREATEST(v_snap.accrued_interest, 0), v_inv.principal_amount
      USING ERRCODE = '23514';
  END IF;

  v_type := CASE
    WHEN v_principal_part = 0 THEN 'Interest Only'
    WHEN v_interest_part > 0 THEN 'Principal + Interest'
    WHEN v_principal_part >= v_inv.principal_amount THEN 'Principal Full'
    ELSE 'Principal Partial'
  END;

  INSERT INTO investment_withdrawals (
    investment_id, withdrawal_type, amount, principal_portion,
    interest_portion, business_date, approved_by_person_id, remarks
  ) VALUES (
    p_investment_id, v_type, v_amount, v_principal_part,
    v_interest_part, p_business_date, app.current_person_id(), p_remarks
  ) RETURNING withdrawal_id INTO v_withdrawal_id;

  -- Interest actually paid out stops accruing. Same shape as
  -- record_investment_interest_payment, inline so the whole withdrawal is one
  -- transaction.
  IF v_interest_part > 0 THEN
    INSERT INTO investment_interest_ledger (
      investment_id, entry_type, amount, business_date, owner_verified, remarks
    ) VALUES (
      p_investment_id, 'Payment', v_interest_part, p_business_date, TRUE,
      COALESCE(p_remarks, 'Paid out with withdrawal')
    );
    UPDATE investments SET last_interest_payment_date = p_business_date
     WHERE investment_id = p_investment_id;
  END IF;

  IF v_principal_part > 0 THEN
    UPDATE investments
       SET principal_amount = GREATEST(principal_amount - v_principal_part, 0),
           status = CASE WHEN principal_amount - v_principal_part <= 0
                         THEN 'Closed'::investment_status_enum ELSE status END
     WHERE investment_id = p_investment_id;
  END IF;

  IF p_request_id IS NOT NULL THEN
    UPDATE investment_withdrawal_requests
       SET status = 'Approved-Paid',
           resulting_withdrawal_id = v_withdrawal_id,
           resolved_at = now()
     WHERE request_id = p_request_id;
  END IF;

  RETURN json_build_object(
    'withdrawal_id', v_withdrawal_id,
    'withdrawal_type', v_type::text,
    'amount', v_amount,
    'interest_portion', v_interest_part,
    'principal_portion', v_principal_part);
END;
$function$;
