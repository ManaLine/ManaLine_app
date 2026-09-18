-- Finding a person meant knowing something unique about them already.
--
-- The Owner, 2026-09-18: "Global search - while searching a user - select
-- village first - then search becomes easy and findable when the user count
-- goes up."
--
-- The search asks for a phone, an MLID, an Aadhaar or a name, and at 99 people
-- a name is enough. At 900 it is not: three Lakshmis come back and the Owner
-- opens two wrong records before the right one. A village is the one thing
-- about a customer that the person asking always knows, and it cuts the book
-- by however many villages it has.
--
-- 'no_people_in_village' is its own sentence rather than the general "no
-- identity found", because they mean different things and the difference is
-- actionable: nobody matched what you typed is a typo, nobody lives here yet
-- is a village waiting for its first customer.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('search_within_a_village', 'Search Within a Village', 'ఒక గ్రామంలో వెతకండి'),
  ('no_people_in_village',
   'Nobody has been added to this village yet.',
   'ఈ గ్రామంలో ఇంకా ఎవరినీ చేర్చలేదు.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key IN ('search_within_a_village','no_people_in_village')
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'expected 2 translated keys, found %', v_n;
  END IF;
END $$;
