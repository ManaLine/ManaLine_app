-- A collection could be recorded and never corrected.
--
-- There was no edit and no void anywhere in the schema -- only the generic
-- app.soft_delete_record -- so a wrong figure at a doorstep stayed wrong,
-- and the only recovery was an Owner deleting the row and re-collecting,
-- which nobody standing in a village can do. The round now allows an
-- amendment, and this is the only way one is written.
--
-- UPDATE IN PLACE, deliberately (Owner's call): the receipt number the
-- customer is holding stays valid, and collections already carries the
-- soft-delete columns for the case where a row must genuinely go away.
--
-- The window closes when the money is handed over. Once a settlement
-- covering this collection's date is Pending Owner Review or Approved, the
-- figure has been counted into a hand-over the Owner is reviewing, and
-- changing it underneath them would make the declared cash disagree with the
-- book that produced it.
--
-- Balance arithmetic: remaining_balance already has the OLD amount taken off
-- it, so the loan is restored to what it owed before this collection and the
-- new amount taken off that. Later collections on the same loan are
-- unaffected -- the net movement is (old - new) either way. Two known
-- imprecisions, both accepted rather than hidden: if the original collection
-- was clamped at zero by record_collection's GREATEST, the restored figure is
-- short by the clamped remainder; and the re-classification below measures
-- against the balance as it stands, so on a loan with later collections a
-- reclassified Full/Partial reads against today's balance rather than that
-- day's.
CREATE OR REPLACE FUNCTION app.amend_collection(
  p_collection_id       UUID,
  p_collected_amount    NUMERIC,
  p_payer_type          payer_type_enum,
  p_payer_name          VARCHAR,
  p_splits              JSON,
  p_excess_disposition  excess_disposition_enum,
  p_remarks             TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_c              collections%ROWTYPE;
  v_business_id    UUID;
  v_agent_id       UUID;
  v_role           business_member_role_enum;
  v_owed_before    NUMERIC(14,0);
  v_new_balance    NUMERIC(14,0);
  v_result_type    collection_result_type_enum;
  v_difference     NUMERIC(14,0);
  v_split          JSON;
  v_total_splits   NUMERIC(14,0) := 0;
  v_disposition    excess_disposition_enum;
BEGIN
  SELECT * INTO v_c FROM collections WHERE collection_id = p_collection_id FOR UPDATE;
  IF v_c.collection_id IS NULL OR v_c.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Collection not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT business_id INTO v_business_id FROM loans WHERE loan_id = v_c.loan_id;

  -- The person who took the money, or the Owner of the book it went into.
  -- Another Agent correcting somebody else's receipt is not an amendment,
  -- it is an unattributed rewrite.
  IF NOT app.is_owner(v_business_id)
     AND NOT app.membership_belongs_to_current_person(v_c.collected_by_membership_id) THEN
    RAISE EXCEPTION 'Only the collector or the Owner may correct this entry'
      USING ERRCODE = '42501';
  END IF;

  SELECT a.agent_id INTO v_agent_id FROM agents a
   WHERE a.membership_id = v_c.collected_by_membership_id;

  IF v_agent_id IS NOT NULL AND EXISTS (
    SELECT 1
      FROM account_settlements s
      JOIN account_periods ap ON ap.account_period_id = s.account_period_id
     WHERE s.agent_id = v_agent_id
       AND s.status IN ('Pending Owner Review', 'Approved')
       AND v_c.business_date >= ap.business_start_date::DATE
       AND v_c.business_date <= COALESCE(ap.actual_end_date,
                                         ap.planned_business_end_date)::DATE
  ) THEN
    RAISE EXCEPTION 'This account has already been submitted to the Owner and can no longer be edited'
      USING ERRCODE = '55006';
  END IF;

  IF p_collected_amount <= 0 THEN
    RAISE EXCEPTION 'Collected amount must be positive' USING ERRCODE = '23514';
  END IF;

  IF p_splits IS NOT NULL THEN
    FOR v_split IN SELECT * FROM json_array_elements(p_splits) LOOP
      IF (v_split->>'amount')::NUMERIC(14,0) <= 0 THEN
        RAISE EXCEPTION 'Split amounts must be positive' USING ERRCODE = '23514';
      END IF;
      v_total_splits := v_total_splits + (v_split->>'amount')::NUMERIC(14,0);
    END LOOP;
    IF v_total_splits <> p_collected_amount THEN
      RAISE EXCEPTION 'Payment splits must sum to the collected amount' USING ERRCODE = '23514';
    END IF;
  END IF;

  SELECT remaining_balance + v_c.collected_amount INTO v_owed_before
    FROM loans WHERE loan_id = v_c.loan_id FOR UPDATE;

  v_difference := p_collected_amount - COALESCE(v_owed_before, 0);
  IF v_difference > 0 THEN
    v_result_type := 'Excess';
  ELSIF p_collected_amount < COALESCE(v_owed_before, 0) THEN
    v_result_type := 'Partial';
    v_difference := 0;
  ELSE
    v_result_type := 'Full';
    v_difference := 0;
  END IF;

  v_disposition := CASE WHEN v_result_type = 'Excess'
                        THEN COALESCE(p_excess_disposition, 'Advance')
                   END;

  v_new_balance := GREATEST(v_owed_before - p_collected_amount, 0);

  UPDATE loans
     SET remaining_balance = v_new_balance, updated_at = now()
   WHERE loan_id = v_c.loan_id;

  UPDATE collections
     SET collected_amount    = p_collected_amount,
         payer_type          = p_payer_type,
         payer_name          = CASE WHEN p_payer_type = 'Others'
                                    THEN NULLIF(btrim(p_payer_name), '') END,
         result_type         = v_result_type,
         difference_amount   = v_difference,
         excess_disposition  = v_disposition,
         remarks             = p_remarks
   WHERE collection_id = p_collection_id;

  -- Splits are replaced wholesale. Reconciling them row by row would leave a
  -- mode behind whenever an amendment drops one.
  DELETE FROM collection_payment_splits WHERE collection_id = p_collection_id;
  IF p_splits IS NOT NULL THEN
    FOR v_split IN SELECT * FROM json_array_elements(p_splits) LOOP
      INSERT INTO collection_payment_splits (collection_id, payment_mode, amount)
      VALUES (p_collection_id,
              (v_split->>'payment_mode')::payment_mode_enum,
              (v_split->>'amount')::NUMERIC(14,0));
    END LOOP;
  ELSE
    INSERT INTO collection_payment_splits (collection_id, payment_mode, amount)
    VALUES (p_collection_id, 'Cash', p_collected_amount);
  END IF;

  -- Recomposed, not adjusted by a delta. record_collection increments the
  -- float because it knows nothing else moved; an amendment cannot assume
  -- that, and BF is derived precisely so it never has to.
  SELECT role INTO v_role FROM business_members
   WHERE membership_id = v_c.collected_by_membership_id;
  IF v_role = 'Agent' THEN
    PERFORM app.recompute_agent_bf(v_c.collected_by_membership_id);
  END IF;
  PERFORM app.recompute_business_bf(v_business_id);

  -- day_ledger follows from the trigger on collections, which recomputes the
  -- day and cascades forward.

  RETURN json_build_object(
    'status',            'amended',
    'collection_id',     p_collection_id,
    'receipt_number',    v_c.receipt_number,
    'result_type',       v_result_type,
    'collected_amount',  p_collected_amount,
    'remaining_balance', v_new_balance
  );
END;
$$;

REVOKE ALL ON FUNCTION app.amend_collection(UUID, NUMERIC, payer_type_enum, VARCHAR, JSON, excess_disposition_enum, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.amend_collection(UUID, NUMERIC, payer_type_enum, VARCHAR, JSON, excess_disposition_enum, TEXT) TO authenticated, anon;
