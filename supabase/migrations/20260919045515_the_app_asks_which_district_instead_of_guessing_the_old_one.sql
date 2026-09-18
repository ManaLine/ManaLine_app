-- The app was filling in the district by sort order, and always got the
-- pre-2022 answer.
--
-- The Owner, 2026-09-18 (item 11): "enable user to select mandal, district
-- (while user opts to select show available list and then option to add new if
-- in future more split happens) which is correct if app fills it wrong or old
-- data & one user selects a new mandal or district instead of old app creates
-- it's & suggest the same in next user search new & most used on top."
--
-- Andhra Pradesh split its districts in 2022 and lgd_villages carries both the
-- old and the new name, so 56,163 villages are listed under two districts --
-- every village in Srikalahasti mandal among them. app.suggest_villages orders
-- by district A to Z and the search kept the first row it saw, which means the
-- app stored CHITTOOR for all of them. Srikalahasti has been in Tirupati since
-- 2022. Nothing asked, nothing said so, and nothing could have noticed.
--
-- ASKED ONLY WHEN IT MATTERS. 93% of villages sit in one district and are
-- taken without a question. The rest ask once -- once per village, because a
-- village already in use carries its answer in `locations` and never reaches
-- that path again.
--
-- 'already_used_here' is what makes the question cheap rather than annoying.
-- An Owner does not know which district is legally current; they do know
-- which one the rest of their book says. Showing the count turns a question
-- about administrative geography into a question about their own ledger.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('which_district', 'Which District?', 'ఏ జిల్లా?'),
  ('which_district_note',
   '{village} is in {mandal}, and the directory lists that mandal under two districts because of a district split. Pick the one your book uses.',
   'జిల్లాల విభజన కారణంగా {mandal} మండలం రెండు జిల్లాల కింద నమోదై ఉంది, అందులో {village} ఉంది. మీ పుస్తకం ఉపయోగించేదాన్ని ఎంచుకోండి.'),
  ('already_used_here', 'Already used by {count} of your villages',
   'మీ {count} గ్రామాలు ఇప్పటికే దీన్ని ఉపయోగిస్తున్నాయి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key IN ('which_district','which_district_note','already_used_here')
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'expected 3 translated keys, found %', v_n;
  END IF;
END $$;
