-- Three letters into the search box used to answer with an instruction to
-- type, because the only thing it could find was a person and finding a person
-- needs Enter.
--
-- The Owner, 2026-09-18: "Global search - enable to search options that app
-- offers like add a customer, add an agent, etc.. upon entering 3 show matches
-- and on tap lead to that screen or flow."
--
-- 'press_enter_to_find_people' exists because the screen now does two things
-- at once and they answer on different keys. Actions appear while you type;
-- people need Enter, because one is a scan of a list held in the app and the
-- other is a round trip. A screen that shows results for one and silence for
-- the other has to say which is which, or it reads as a search that has
-- already finished and found nobody.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('actions_section', 'What You Can Do', 'మీరు ఏమి చేయవచ్చు'),
  ('press_enter_to_find_people',
   'To find a person, press Enter to search by phone, MLID, Aadhaar or name.',
   'ఒక వ్యక్తిని వెతకాలంటే Enter నొక్కి ఫోన్, MLID, ఆధార్ లేదా పేరుతో వెతకండి.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key IN ('actions_section','press_enter_to_find_people')
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'expected 2 translated keys, found %', v_n;
  END IF;
END $$;
