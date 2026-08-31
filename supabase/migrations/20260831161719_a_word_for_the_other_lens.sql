-- The capture screen resolved the front camera once at startup and had no way
-- back to any other lens. It has a flip button now, and the button needs a
-- name for its tooltip and for a screen reader.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('switch_camera', 'Switch Camera', 'కెమెరా మార్చండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
