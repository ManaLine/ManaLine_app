-- The signed-out pages are a website's front door, and they said nothing.
--
-- Twelve /lr-* routes -- login, registration, OTP, PIN, workspace and role
-- choice -- rendered as a bare column on grey. They are the first thing any
-- visitor sees, and until now the only thing identifying the product on them
-- was a small wordmark the screens draw themselves.
--
-- ONE LINE, NOT A PITCH. The marketing site at / does the selling. Somebody
-- on this page has already decided; they are here to get in. The panel beside
-- the form says what the product is, once, and then gets out of the way.

INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('auth_panel_lead',
   'The ledger for a lending business that, until now, lived in one notebook.',
   'ఇప్పటివరకు ఒక నోట్‌బుక్‌లో ఉన్న రుణ వ్యాపార ఖాతా, ఇప్పుడు ఇక్కడ.'),
  ('auth_panel_site_link', 'About MANA LINE', 'MANA LINE గురించి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key LIKE 'auth_panel_%' AND COALESCE(telugu,'') <> '';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'expected 2 translated auth panel keys, found %', v_n;
  END IF;
END $$;
