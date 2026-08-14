-- The admin panel's person lookup returned the full Aadhaar number and the
-- screen printed it. That column is hashed at rest now and always reads NULL,
-- so the field would simply have gone blank — but the fix is not to restore
-- the number. A platform admin looking someone up to delete them needs enough
-- to confirm they have the right person, and the last four digits beside the
-- name, MLID and mobile is enough for that.
--
-- The OUT parameter keeps its name so the signature is unchanged and the RPC
-- has no chance of going ambiguous (PGRST203); only what fills it changes.
CREATE OR REPLACE FUNCTION app.admin_lookup_person(p_mlid character varying)
 RETURNS TABLE(person_id bigint, full_name character varying, mlid character varying, mobile_number character varying, aadhaar_number character varying, gender_digit character, verification_ring character varying, business_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — Platform Admin only' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT p.person_id, p.full_name, p.mlid, p.mobile_number,
         p.aadhaar_last4::VARCHAR,
         p.gender_digit, p.verification_ring::VARCHAR,
         (SELECT count(*) FROM business_members bm WHERE bm.person_id = p.person_id)
  FROM persons p WHERE p.mlid = p_mlid LIMIT 1;
END;
$function$;
