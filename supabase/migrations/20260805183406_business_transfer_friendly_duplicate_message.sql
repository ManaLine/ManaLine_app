-- A second offer for the same business was refused by the unique index, which
-- is correct -- but the caller saw "duplicate key value violates unique
-- constraint uq_business_transfer_one_pending". On a screen about handing over
-- a business, a raw Postgres error is not an acceptable answer.
--
-- The index stays: it is what actually makes the rule true under concurrency.
-- This check just gets there first in the ordinary case, and says something a
-- person can act on.
CREATE OR REPLACE FUNCTION app.request_business_transfer(
  p_business_id uuid,
  p_to_person_id bigint,
  p_note text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_me BIGINT := app.current_person_id();
  v_id UUID;
  v_open UUID;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in' USING ERRCODE = '42501';
  END IF;
  IF p_to_person_id = v_me THEN
    RAISE EXCEPTION 'You cannot transfer a business to yourself' USING ERRCODE = '23514';
  END IF;

  PERFORM app.assert_business_transferable(p_business_id, v_me, p_to_person_id);

  SELECT transfer_id INTO v_open
    FROM business_transfers
   WHERE business_id = p_business_id AND status = 'Pending'
   LIMIT 1;
  IF v_open IS NOT NULL THEN
    RAISE EXCEPTION 'This business is already offered to someone. Cancel that offer first.'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO business_transfers (business_id, from_person_id, to_person_id, note)
  VALUES (p_business_id, v_me, p_to_person_id, p_note)
  RETURNING transfer_id INTO v_id;

  INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type,
                         entity_id, entity_uuid, new_value, business_date)
  VALUES (p_business_id, v_me, 'Other Admin Event', 'business_transfer_offered', 0,
          v_id, json_build_object('to_person_id', p_to_person_id), CURRENT_DATE);

  RETURN json_build_object('transfer_id', v_id, 'status', 'Pending');
END;
$function$;
