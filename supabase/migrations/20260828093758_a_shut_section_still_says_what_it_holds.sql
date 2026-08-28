-- The Agent's dashboard carried five reference sections open at once, which
-- is about four screens of scrolling before the last one is reached. They
-- collapse now, and a collapsed section keeps one line of what it holds --
-- putting a section away must not mean losing sight of it.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('entries_count', '{count} entries', '{count} నమోదులు')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
