-- The label said what the search could do, and it could do less than asked.
--
-- The Owner, 2026-09-19: "add search - in one-by-one - customers - if there
-- are n customers user needs a search inside it by name, phone no, MLID."
--
-- 'search_by_name_or_mlid' stays where it is -- it is still correct on the
-- screens that genuinely cannot match a phone, and rewording a key in place
-- would change what those say without anybody deciding to.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('search_by_name_phone_or_mlid', 'Search by name, phone or MLID',
   'పేరు, ఫోన్ లేదా MLIDతో వెతకండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key = 'search_by_name_phone_or_mlid'
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 1 THEN RAISE EXCEPTION 'the key is missing or untranslated'; END IF;
END $$;
