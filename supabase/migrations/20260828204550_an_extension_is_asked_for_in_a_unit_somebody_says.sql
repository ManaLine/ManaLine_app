-- Approving an extension granted an unspecified amount of nothing. It asks
-- how long now, in the unit the conversation at the door actually used, and
-- says back the date it lands on before anybody commits to it.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('extend_by', 'Extend By', 'పొడిగించండి'),
  ('unit', 'Unit', 'యూనిట్'),
  ('extension_resolves_to_note', '{days} days — until {date}.',
   '{days} రోజులు — {date} వరకు.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
