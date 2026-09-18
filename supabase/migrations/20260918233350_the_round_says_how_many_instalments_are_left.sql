-- The due row showed the instalment and the balance, and never how many
-- instalments were left in between.
--
-- The Owner, 2026-09-18: "collections - customer - after EMI - add R.Emi's
-- (count of remaining EMI's to be paid)."
--
-- An agent at a door is asked "how many more?" constantly, and the answer was
-- a division nobody should do standing up: balance divided by instalment,
-- rounded up. The row has both figures already.
--
-- SHORT LABEL, because it sits beside the EMI figure on a 360dp row that
-- already carries a name, a ring, a balance and a button. "R. EMIs" is what
-- the Owner called it and it is what fits.

INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('remaining_emis_short', 'R. EMIs', 'మిగిలిన EMIలు'),
  ('show_to_pay_tooltip', 'Show where to pay', 'ఎక్కడ చెల్లించాలో చూపండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key IN ('remaining_emis_short','show_to_pay_tooltip')
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'expected 2 translated keys, found %', v_n;
  END IF;
END $$;
