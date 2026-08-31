-- Removing an operating area now has three possible answers, and the Owner is
-- told which one happened.
--
-- The second question carries the loan count rather than repeating "are you
-- sure": asking the same question twice teaches people to tap through both,
-- where a number they did not have a moment ago is a reason to stop.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('area_still_has_loans_question', 'Loans Are Still Being Collected Here',
   'ఇక్కడ ఇంకా వసూళ్లు జరుగుతున్నాయి'),
  ('area_still_has_loans_note',
   '{count} live loans sit in {area}. Removing it now leaves them with no round to be collected on.',
   '{area}లో {count} సజీవ రుణాలు ఉన్నాయి. ఇప్పుడు తీసివేస్తే వాటిని వసూలు చేయడానికి రౌండ్ ఉండదు.'),
  ('area_removed_note', '{area} was removed.', '{area} తీసివేయబడింది.'),
  ('area_kept_for_history_note',
   '{area} is no longer worked. It is kept because past account periods refer to it.',
   '{area} ఇకపై పని చేయబడదు. గత ఖాతా వ్యవధులు దీన్ని సూచిస్తున్నందున ఇది ఉంచబడింది.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
