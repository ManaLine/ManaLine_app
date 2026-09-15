-- The message shown when a customer has neither phone nor Aadhaar.
--
-- Until now the person at the doorstep saw this instead:
--
--   new row for relation "persons" violates check constraint
--   "persons_mlti_needs_hard_key"
--
-- telugu IS LEFT NULL ON PURPOSE. TranslationCache.t() resolves
-- `row[language] ?? row['English'] ?? key`, so a Telugu reader sees English
-- rather than a raw key. Writing the English into the telugu column would read
-- as a completed translation and inflate the figure CLAUDE.md holds the app to.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('customer_needs_phone_or_aadhaar',
   'Enter a mobile number or an Aadhaar number. Only a customer being brought across from an existing book can have neither.',
   NULL)
ON CONFLICT (translation_key) DO NOTHING;
