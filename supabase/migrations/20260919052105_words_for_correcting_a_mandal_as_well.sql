-- The Owner asked for both -- "enable user to select mandal, district" -- and
-- the first pass only made the district correctable.
--
-- 'correct_place_note' names the PIN because the PIN is the one part of an
-- address the app will NOT change here, and it is what scopes both lists: the
-- mandals offered are the mandals the directory has at that PIN. Somebody
-- correcting a village needs to know which part is fixed.
--
-- 'add_a_different_one' is deliberately not "Add a new mandal" or "Add a new
-- district" -- one string serves both choosers, and the dialog it opens
-- carries the title that says which. Two keys differing by one word is two
-- keys to keep translated in step.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('which_mandal', 'Which Mandal?', 'ఏ మండలం?'),
  ('add_a_different_one', 'Add a different one', 'వేరేది జోడించండి'),
  ('correct_place_note',
   'PIN {pin}. The mandal and district are what the directory recorded, and after a district split that can be out of date.',
   'పిన్ {pin}. మండలం, జిల్లా డైరెక్టరీ నమోదు చేసినవి, జిల్లాల విభజన తర్వాత అవి పాతవి కావచ్చు.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key IN ('which_mandal','add_a_different_one','correct_place_note')
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'expected 3 translated keys, found %', v_n;
  END IF;
END $$;
