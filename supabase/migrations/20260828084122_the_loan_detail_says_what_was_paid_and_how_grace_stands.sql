-- Grace was one row that read a status nothing writes, so a loan carrying
-- seven days of grace said "Normal". It now says how many days were granted,
-- whether grace is running, and the day it runs out -- or that it has already
-- expired, which is a different thing from never having had any.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('days_count', '{count} Days', '{count} రోజులు'),
  ('until_date', 'Until {date}', '{date} వరకు'),
  ('grace_expired', 'Grace Ended', 'గ్రేస్ ముగిసింది')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
