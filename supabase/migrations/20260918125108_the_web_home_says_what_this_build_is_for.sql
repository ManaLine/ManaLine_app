-- "Welcome Back" was the entire page.
--
-- A greeting over a stack of unlabelled cards tells somebody they are signed
-- in and nothing else -- and this build is deliberately NOT the app.
-- Collections, loans, day closure and reports were removed from the web on
-- purpose (Plan 3a); they live on the handset. Without a line saying so, an
-- Owner hunts the navigation rail for a collection round that was never going
-- to be there.

INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('web_home_lead',
   'The desk half of MANA LINE. Paperwork, records and setup happen here; collections and the daily round happen in the app on your phone.',
   'MANA LINE యొక్క డెస్క్ భాగం. కాగితపు పని, రికార్డులు, సెటప్ ఇక్కడ; వసూళ్లు, రోజువారీ రౌండ్ మీ ఫోన్‌లోని యాప్‌లో.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_te TEXT;
BEGIN
  SELECT telugu INTO v_te FROM ui_translations WHERE translation_key='web_home_lead';
  IF COALESCE(v_te,'') = '' THEN
    RAISE EXCEPTION 'web_home_lead has no Telugu';
  END IF;
END $$;
