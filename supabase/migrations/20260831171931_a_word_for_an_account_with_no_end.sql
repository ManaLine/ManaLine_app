-- OW-012 lists account periods as "start -> end". An open account has no end
-- to show, and printing a predicted one read as a deadline the agent
-- routinely worked past -- the forecast-as-boundary mistake in visible form.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('until_submitted', 'until submitted', 'సమర్పించే వరకు')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
