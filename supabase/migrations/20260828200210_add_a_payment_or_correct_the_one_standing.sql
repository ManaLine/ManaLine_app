-- A weekly customer paying daily, and an Agent who tapped Collect twice by
-- accident, arrive at the same dialog. They mean opposite things to the
-- balance, so the screen asks instead of guessing.
--
-- "Add Payment" is another day against the same receipt; "Correct" amends the
-- figure already recorded. The note above them quotes the WINDOW total rather
-- than the last day, because Rs 200 already collected this cycle is what
-- decides whether another Rs 100 is right.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('add_payment', 'Add Payment', 'చెల్లింపు జోడించండి'),
  ('correct_entry', 'Correct', 'సరిచేయండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
