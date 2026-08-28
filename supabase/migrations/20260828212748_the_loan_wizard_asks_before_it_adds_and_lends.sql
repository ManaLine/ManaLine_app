-- The wizard's search added somebody to the book AND carried them into the
-- loan in one tap. That is usually right and occasionally not: sometimes the
-- person in front of you should be on the book and is not borrowing today.
-- The same two endings as the add-customer sheet, so the question reads the
-- same wherever it is asked.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('not_on_this_book_yet', 'Not on this book yet.', 'ఇంకా ఈ పుస్తకంలో లేరు.'),
  ('added_to_this_business', 'Added to this business.', 'ఈ వ్యాపారానికి జోడించబడింది.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
