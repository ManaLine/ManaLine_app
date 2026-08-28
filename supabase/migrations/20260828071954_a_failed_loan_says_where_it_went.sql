-- A loan refused for float parked a draft and said so. A loan that THREW --
-- a dropped reply, a timeout, an RLS refusal -- parked nothing and said
-- nothing, so the Owner retyped it. It parks a draft now, and this is the
-- line that tells them not to retype.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('saved_as_draft_note',
   'Saved as a draft. Nothing you entered is lost — it is waiting in Draft Transactions.',
   'డ్రాఫ్ట్‌గా భద్రపరచబడింది. మీరు నమోదు చేసినది ఏదీ పోలేదు — అది డ్రాఫ్ట్ లావాదేవీలలో ఉంది.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
