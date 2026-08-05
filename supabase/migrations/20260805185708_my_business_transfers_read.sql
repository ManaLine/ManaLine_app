-- Read model for the transfer screens.
--
-- A plain SELECT on business_transfers would return person and business IDs
-- and nothing a human can read; joining to persons and businesses from the
-- client runs into their own RLS, and the recipient of an offer has no
-- membership in that business yet, so they cannot see its name. Hence one
-- SECURITY DEFINER read that returns exactly the fields both screens show and
-- nothing more.
--
-- Scoped to the caller in the WHERE clause, not by RLS: this function bypasses
-- RLS by definition, so the restriction has to be written here. It returns
-- only rows where the caller is one of the two parties.
CREATE OR REPLACE FUNCTION app.my_business_transfers()
RETURNS TABLE (
  transfer_id     uuid,
  business_id     uuid,
  business_name   varchar,
  mlbi            varchar,
  direction       text,
  counterparty    varchar,
  counterparty_mlid varchar,
  status          business_transfer_status_enum,
  note            text,
  decline_reason  text,
  requested_at    timestamp
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT
    t.transfer_id,
    t.business_id,
    b.business_name,
    b.mlbi,
    CASE WHEN t.from_person_id = app.current_person_id()
         THEN 'outgoing' ELSE 'incoming' END AS direction,
    -- The other party, whichever side the caller is on.
    CASE WHEN t.from_person_id = app.current_person_id()
         THEN pto.full_name ELSE pfrom.full_name END AS counterparty,
    CASE WHEN t.from_person_id = app.current_person_id()
         THEN pto.mlid ELSE pfrom.mlid END AS counterparty_mlid,
    t.status,
    t.note,
    t.decline_reason,
    t.requested_at
  FROM business_transfers t
  JOIN businesses b   ON b.business_id = t.business_id
  JOIN persons pfrom  ON pfrom.person_id = t.from_person_id
  JOIN persons pto    ON pto.person_id   = t.to_person_id
  WHERE app.current_person_id() IN (t.from_person_id, t.to_person_id)
  ORDER BY t.requested_at DESC;
$function$;

REVOKE ALL ON FUNCTION app.my_business_transfers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.my_business_transfers() TO authenticated;
