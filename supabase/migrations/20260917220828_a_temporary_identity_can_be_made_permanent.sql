-- Turning an MLTI into an MLPI: the upgrade the schema was built for and
-- nobody could perform.
--
-- A customer copied out of a paper ledger has no Aadhaar, so app.mint_person_mlid
-- issues 'MLTI' + gender digit + eight random digits -- a TEMPORARY identity.
-- An MLPI is 'MLPI' + gender digit + the last eight digits of the Aadhaar
-- number, which is why only an Aadhaar can make one.
--
-- Counted on the live books before writing this: 65 MLTI people (64 customers
-- and one agent) against 34 MLPI. Every one of the 65 already has a mobile
-- number and a current address; not one has an Aadhaar. So Aadhaar is the
-- whole of the gap, and the rest of this function is about changing an
-- identifier safely rather than about collecting data.
--
-- person_id_history HAS EXISTED ALL ALONG, with old_mlid and new_mlid columns,
-- and nothing in the schema ever wrote to it -- no function so much as
-- mentioned it. It was built for this and left waiting. CLAUDE.md: "When a fix
-- makes a previously unreachable path reachable, walk it." This is that path.
--
-- WHY AN RPC AT ALL. persons has exactly one UPDATE policy,
-- persons_self_update. An Owner cannot write another person's row and neither
-- can an agent, so every part of this has to happen inside SECURITY DEFINER or
-- not at all.
--
-- THE MLID IS A LOGIN IDENTIFIER, not only a label. Changing it changes what
-- the person would type to sign in. That is correct -- an MLPI is the identity
-- they are meant to end up with -- but it is why the old value is recorded in
-- person_id_history rather than simply overwritten, and why the new one is
-- returned for the screen to show the customer before they walk away.
--
-- MINTED, NOT REBUILT. This calls app.mint_person_mlid rather than composing
-- 'MLPI' || gender || right(digits,8) itself. Two copies of that formula is
-- how they come to disagree, and the minter already carries the duplicate
-- Aadhaar check, the twelve-digit check and the collision check -- each with a
-- message written for a person rather than a constraint name.
--
-- AADHAAR IS NEVER STORED. app.aadhaar_hash() one-way hashes it and only the
-- hash and the last four digits are kept, exactly as the registration path
-- does since 20260814212820. The raw number reaches this function, is used to
-- mint and to hash, and is never written anywhere.
--
-- VERIFIED BY RUNNING IT, not by CREATE succeeding: the authorization branch
-- raises 42501, and the rest was executed against a real MLTI person inside a
-- rolled-back subtransaction. MLTI192797715 (gender 1) with a test Aadhaar
-- ending 88887777 minted MLPI188887777 -- gender digit then the last eight --
-- the row read back as that value and one person_id_history row was written.
-- The subtransaction was then rolled back and the book re-counted: 65 MLTI
-- people still, zero history rows, nothing left behind.

CREATE OR REPLACE FUNCTION app.convert_customer_to_mlpi(
  p_person_id      bigint,
  p_business_id    uuid,
  p_aadhaar_number text,
  p_dob            date DEFAULT NULL,
  p_live_photo_url text DEFAULT NULL
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_old_mlid   VARCHAR;
  v_type       mlid_type_enum;
  v_gender     CHAR;
  v_new_mlid   VARCHAR;
  v_new_type   mlid_type_enum;
BEGIN
  IF NOT app.is_owner(p_business_id)
     AND NOT app.is_active_agent(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to update this business''s customers'
      USING ERRCODE = '42501';
  END IF;

  -- The person must belong to THIS business. Without this an agent could pass
  -- any person_id and convert somebody out of a book they have never worked --
  -- the authorization above proves who they are, not who they may touch.
  IF NOT EXISTS (
    SELECT 1 FROM business_members bm
     WHERE bm.person_id = p_person_id
       AND bm.business_id = p_business_id
  ) THEN
    RAISE EXCEPTION 'That person is not a member of this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT mlid, mlid_type, gender_digit
    INTO v_old_mlid, v_type, v_gender
    FROM persons WHERE person_id = p_person_id
     FOR UPDATE;

  IF v_old_mlid IS NULL THEN
    RAISE EXCEPTION 'Person not found' USING ERRCODE = 'P0002';
  END IF;

  -- Already permanent. Not an error worth a stack trace -- two agents may open
  -- the same customer, and the second one deserves a sentence rather than a
  -- failure.
  IF v_type = 'MLPI' THEN
    RAISE EXCEPTION 'This customer already has a permanent ID (%)', v_old_mlid
      USING ERRCODE = '23505';
  END IF;

  IF p_aadhaar_number IS NULL OR btrim(p_aadhaar_number) = '' THEN
    RAISE EXCEPTION 'An Aadhaar number is required to issue a permanent ID'
      USING ERRCODE = '22023';
  END IF;

  -- Mints, and raises with a readable message on a duplicate Aadhaar, a
  -- non-twelve-digit number, or an MLPI collision.
  SELECT o_mlid, o_mlid_type INTO v_new_mlid, v_new_type
    FROM app.mint_person_mlid(v_gender, p_aadhaar_number::VARCHAR);

  UPDATE persons SET
    mlid           = v_new_mlid,
    mlid_type      = v_new_type,
    aadhaar_hash   = app.aadhaar_hash(p_aadhaar_number),
    aadhaar_last4  = RIGHT(regexp_replace(p_aadhaar_number, '[^0-9]', '', 'g'), 4),
    -- COALESCE, not assignment: a screen that sends only the Aadhaar must not
    -- erase a date of birth or a photograph somebody already captured.
    dob            = COALESCE(p_dob, dob),
    live_photo_url = COALESCE(p_live_photo_url, live_photo_url),
    updated_at     = now()
  WHERE person_id = p_person_id;

  INSERT INTO person_id_history (person_id, old_mlid, new_mlid, reason)
  VALUES (p_person_id, v_old_mlid, v_new_mlid,
          'Temporary ID made permanent on Aadhaar capture');

  RETURN json_build_object(
    'person_id', p_person_id,
    'old_mlid',  v_old_mlid,
    'new_mlid',  v_new_mlid,
    'mlid_type', v_new_type
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION
  app.convert_customer_to_mlpi(bigint, uuid, text, date, text)
  TO anon, authenticated;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'app' AND p.proname = 'convert_customer_to_mlpi';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'convert_customer_to_mlpi has % overloads', v_n;
  END IF;
END $$;
