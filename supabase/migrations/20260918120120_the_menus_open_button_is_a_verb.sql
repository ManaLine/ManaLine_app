-- `open` was the wrong key to put on a button, and only Telugu says so.
--
-- ui_translations.open is English "Open" / Telugu "తెరిచి ఉంది", which means
-- "IS open" -- a state. It is correct where it is used: a loan that is still
-- open. On the bulk-onboarding menu's step rows it would have labelled a
-- button "Is Open", and an English reader reviewing the screen would never
-- have seen it, because English uses one word for both.
--
-- The previous migration (20260918120026) said not to mint a key for a word
-- already here. That rule holds; this is not the same word. Reusing it would
-- have been the silent kind of wrong this project keeps a guard for.
--
-- `open` itself is left exactly as it is. It is right for loan status, which
-- is what its other callers mean by it.

INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('bulk_menu_open_step', 'Open', 'తెరవండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_new TEXT; v_old TEXT;
BEGIN
  SELECT telugu INTO v_new FROM ui_translations WHERE translation_key='bulk_menu_open_step';
  SELECT telugu INTO v_old FROM ui_translations WHERE translation_key='open';
  IF v_new IS NULL OR v_new = '' THEN
    RAISE EXCEPTION 'the button key has no Telugu, which is the entire reason it exists';
  END IF;
  -- If these two ever agree, one of them has been "tidied" into the other and
  -- the distinction this migration exists for has been lost.
  IF v_new = v_old THEN
    RAISE EXCEPTION 'the verb and the state now read the same in Telugu';
  END IF;
END $$;
