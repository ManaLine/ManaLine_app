-- The bell carries a withdrawal request now, and the inbox row is a request
-- id -- it has no investment id, because InboxAction is shared by approvals,
-- invitations and settlements and none of the others need one.
--
-- A thin wrapper rather than widening that model, and rather than a second
-- copy of the payout: this looks the investment up from the request and hands
-- straight over to withdraw_from_investment, so there is exactly one place
-- where interest-then-principal, affordability and already-paid are decided.
--
-- Amount defaults to what was actually requested, which is what the Owner is
-- agreeing to when they press Pay Out on a card that shows that figure.
CREATE OR REPLACE FUNCTION app.pay_out_withdrawal_request(
  p_request_id uuid,
  p_amount numeric DEFAULT NULL,
  p_business_date date DEFAULT CURRENT_DATE
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
DECLARE
  v_investment_id uuid;
  v_requested numeric;
BEGIN
  SELECT wr.investment_id, wr.requested_amount
    INTO v_investment_id, v_requested
    FROM investment_withdrawal_requests wr
   WHERE wr.request_id = p_request_id;

  IF v_investment_id IS NULL THEN
    RAISE EXCEPTION 'No such withdrawal request' USING ERRCODE = 'P0002';
  END IF;

  RETURN app.withdraw_from_investment(
    v_investment_id,
    COALESCE(p_amount, v_requested),
    p_business_date,
    p_request_id);
END;
$function$;
