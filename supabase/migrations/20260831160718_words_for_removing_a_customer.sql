-- Swipe-left to remove a customer who owes nothing.
--
-- The note says what removal actually does, because "Remove" on its own
-- sounds like a delete and this is not one: the person's loans, collections
-- and receipts all stay exactly where they were.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('remove_customer_question', 'Remove This Customer?',
   'ఈ ఖాతాదారుని తొలగించాలా?'),
  ('remove_customer_note',
   '{name} will no longer appear in this business. Their past loans, collections and receipts are kept.',
   '{name} ఇకపై ఈ వ్యాపారంలో కనిపించరు. వారి గత రుణాలు, వసూళ్లు మరియు రసీదులు అలాగే ఉంచబడతాయి.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
