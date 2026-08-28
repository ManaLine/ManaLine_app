-- Every collection in the app was written as Cash. The only way to say
-- otherwise was a Mixed Payment switch offering Cash and UPI, whose two
-- boxes had to be totalled by the Agent and then checked against the
-- collected amount by the app ("Split sum ... must equal collected
-- amount"). With the switch off -- which is every ordinary collection --
-- the split list was hardcoded to Cash, so a customer paying entirely by
-- UPI, cheque or bank transfer was recorded as having handed over notes.
--
-- payment_mode_enum has carried all four modes since it was created. The
-- form now offers all four, the app adds them up, and Mixed is gone.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('bank_transfer', 'Bank Transfer', 'బ్యాంక్ బదిలీ'),
  ('how_it_was_paid', 'How It Was Paid', 'ఎలా చెల్లించారు'),
  ('added_up_from_modes_note',
   'Added up from the payment modes below.',
   'కింది చెల్లింపు విధానాల నుండి కూడబెట్టబడింది.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
