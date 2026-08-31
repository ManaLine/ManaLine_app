-- The disputing agent's wait screen had no action on it. It has a Check Again
-- now, so an agent whose Owner has just answered does not have to kill the app
-- to find out.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('check_again', 'Check Again', 'మళ్లీ చూడండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
