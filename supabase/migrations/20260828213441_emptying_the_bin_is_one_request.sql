-- Delete All deleted a handful and then said "The server did not respond."
--
-- The screen looped app.purge_record once per record, awaiting each. With 627
-- rows in the bin that is 627 round trips inside a single client timeout, so
-- the timeout won long before the loop did -- and because the loop had
-- already committed the ones it reached, the bin came back smaller each time.
-- That is the "deletes in small chunks" the Owner saw: not chunking by
-- design, a timeout landing partway through.
--
-- One call, one transaction. Either the whole selection goes or none of it
-- does, which is also the honest behaviour for something with no undo.
--
-- Per-record authorisation is unchanged: this calls the same purge_record for
-- each id, so every row is still checked against may_delete_records for its
-- own business. A caller cannot empty somebody else's bin by putting their
-- ids in the array.
CREATE OR REPLACE FUNCTION app.purge_records(p_records JSON)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_rec JSON;
  v_purged INT := 0;
BEGIN
  IF p_records IS NULL OR json_array_length(p_records) = 0 THEN
    RETURN json_build_object('purged', 0);
  END IF;

  -- A cap, so a runaway client cannot ask for an unbounded transaction. The
  -- screen pages at far less than this.
  IF json_array_length(p_records) > 2000 THEN
    RAISE EXCEPTION 'Too many records in one request' USING ERRCODE = '54000';
  END IF;

  FOR v_rec IN SELECT * FROM json_array_elements(p_records) LOOP
    PERFORM app.purge_record(
      (v_rec->>'entity')::TEXT,
      (v_rec->>'record_id')::UUID
    );
    v_purged := v_purged + 1;
  END LOOP;

  RETURN json_build_object('purged', v_purged);
END;
$$;
