-- The village search could only find villages somebody had already typed in
-- once. GPS prefills the box with a name the LGD reference knows and
-- `locations` does not, so the search came back empty and the only way
-- forward on screen was Add New Village -- which is how
-- "Panagal, Tirupati, Andhrapradesh" came to sit in this database beside the
-- reference's own "Panagallu (Rural), Srikalahasti, Chittoor, Andhra
-- Pradesh". Not a typo. A dead end.
--
-- The reference villages are offered alongside the ones in use, marked so
-- that choosing one reads as safe rather than as inventing something.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('from_the_pin_code_directory', 'From the PIN code directory',
   'పిన్ కోడ్ డైరెక్టరీ నుండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
