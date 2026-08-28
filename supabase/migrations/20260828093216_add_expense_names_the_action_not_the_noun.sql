-- The floating button said "Expense", which is a noun. In a header of three
-- glyphs the + needs a spoken name, and a screen reader announcing "Expense"
-- says what the thing is rather than what pressing it does.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('add_expense', 'Add Expense', 'ఖర్చు జోడించండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
