-- The Add Customer sheet offered "2 matches — choose one" and showed, for
-- each, only the MLID and the father's name. Two men called Naresh, one line
-- of difference, and the Owner picks one and links a real person to a real
-- business on that basis. Village is the thing an Owner in the field actually
-- recognises, and this RPC did not return it.
--
-- Adding a column CHANGES THE RETURN TYPE, so this is DROP then CREATE, not
-- CREATE OR REPLACE -- Postgres refuses to replace a function whose OUT columns
-- differ. The parameter list is untouched, so no second overload can appear;
-- counted after applying (1).
--
-- Consumers checked before touching it: exactly one, customer_state.dart's
-- searchIdentity. No SQL caller, no view. That call site hardcoded village to
-- the empty string because there was nothing to read.
--
-- Village comes from the CURRENT address only. A person with no address on file
-- returns NULL and the sheet shows nothing rather than an empty separator --
-- "no address recorded" must not render as though it were a place.
--
-- NOTE: this migration calls app.person_current_village, which is created by
-- 20260904095342 -- written AFTER this one because this one referenced a
-- function that did not exist yet and applied cleanly regardless. plpgsql
-- bodies are not type-checked at CREATE time. Invoking is what found it.
DROP FUNCTION IF EXISTS app.owner_search_person(text, text, text, text);

CREATE FUNCTION app.owner_search_person(
  p_mlid text DEFAULT NULL::text,
  p_mobile_number text DEFAULT NULL::text,
  p_aadhaar_number text DEFAULT NULL::text,
  p_full_name text DEFAULT NULL::text
)
RETURNS TABLE(person_id bigint, full_name character varying,
              father_husband_name character varying,
              mobile_number character varying, mlid character varying,
              village character varying)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM businesses WHERE owner_person_id = app.current_person_id()
  ) THEN
    RAISE EXCEPTION 'Not authorized — Owner only' USING ERRCODE = '42501';
  END IF;

  IF p_mlid IS NOT NULL AND p_mlid <> '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name,
                        p.mobile_number, p.mlid, app.person_current_village(p.person_id)
      FROM persons p WHERE p.mlid = p_mlid LIMIT 1;
  ELSIF p_aadhaar_number IS NOT NULL AND p_aadhaar_number <> '' THEN
    -- Hash the search term and compare digests. The caller still passes the
    -- number the Owner typed; it is hashed here and never stored.
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name,
                        p.mobile_number, p.mlid, app.person_current_village(p.person_id)
      FROM persons p WHERE p.aadhaar_hash = app.aadhaar_hash(p_aadhaar_number) LIMIT 1;
  ELSIF p_mobile_number IS NOT NULL AND p_mobile_number <> '' THEN
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name,
                        p.mobile_number, p.mlid, app.person_current_village(p.person_id)
      FROM persons p WHERE p.mobile_number = p_mobile_number LIMIT 1;
  ELSIF p_full_name IS NOT NULL AND p_full_name <> '' THEN
    -- Many rows, shortest first so an exact-ish match leads. Capped at 25:
    -- this feeds a bottom sheet, not a report.
    RETURN QUERY SELECT p.person_id, p.full_name, p.father_husband_name,
                        p.mobile_number, p.mlid, app.person_current_village(p.person_id)
      FROM persons p
      WHERE p.full_name ILIKE '%' || p_full_name || '%'
      ORDER BY length(p.full_name), p.full_name
      LIMIT 25;
  END IF;
END;
$function$;

GRANT EXECUTE ON FUNCTION app.owner_search_person(text, text, text, text) TO anon, authenticated;
