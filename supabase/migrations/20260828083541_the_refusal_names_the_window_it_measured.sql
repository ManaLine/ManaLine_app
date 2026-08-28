-- A Daily loan may be collected on every day of an account period; a Weekly
-- or Monthly one may be collected once in the whole period. The same refusal
-- therefore means two different things, and "already collected today" over a
-- weekly loan sends the Agent back tomorrow to be refused again.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('already_collected_this_cycle', 'Already Collected This Account Cycle',
   'ఈ ఖాతా వ్యవధిలో ఇప్పటికే వసూలు చేయబడింది'),
  ('recorded_on_note', 'Recorded on {date}.', '{date}న నమోదు చేయబడింది.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
