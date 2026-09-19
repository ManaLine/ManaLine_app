-- Asking at pick time stops NEW villages being stamped with the pre-2022
-- district. These are for the ones already stored -- on this book, every
-- village in Srikalahasti mandal.
--
-- 'your_villages_note' says what tapping one does BEFORE it is tapped. A list
-- of places with a pencil beside each is otherwise a list that might do
-- anything, and the thing it does -- rewriting a row every book shares -- is
-- worth one sentence.
--
-- 'district_corrected' names both the old and the new district. A confirmation
-- reading only "saved" leaves somebody who tapped the wrong row with no way to
-- know they did.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('your_villages', 'Your Villages', 'మీ గ్రామాలు'),
  ('your_villages_note',
   'Tap a village to correct its mandal or district. This changes the name of the place, not who lives there or what they owe.',
   'మండలం లేదా జిల్లా సరిచేయడానికి ఒక గ్రామంపై నొక్కండి. ఇది ప్రదేశం పేరును మాత్రమే మారుస్తుంది, అక్కడ ఎవరు ఉన్నారో లేదా వారు ఎంత చెల్లించాలో కాదు.'),
  ('district_corrected', '{village} moved from {was} to {now}.',
   '{village} {was} నుంచి {now}కి మార్చబడింది.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key IN ('your_villages','your_villages_note','district_corrected')
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'expected 3 translated keys, found %', v_n;
  END IF;
END $$;
