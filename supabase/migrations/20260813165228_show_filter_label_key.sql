-- Label for the notifications filter dropdown that replaced its chip pair.
INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada) VALUES
  ('show', 'Show', 'చూపించు', 'दिखाएँ', 'காட்டு', 'ತೋರಿಸಿ')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english, telugu = EXCLUDED.telugu,
  hindi = EXCLUDED.hindi, tamil = EXCLUDED.tamil, kannada = EXCLUDED.kannada;
