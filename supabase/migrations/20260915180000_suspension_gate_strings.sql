-- The three strings the suspension gate needs, now that something calls it.
--
-- BusinessSuspendedScreen has existed since the gate was written and has never
-- been reachable, so its text was hardcoded English inside the widget. Wiring
-- the gate makes it a screen people actually land on.
--
-- telugu IS LEFT NULL ON PURPOSE. TranslationCache.t() resolves
-- `row[language] ?? row['English'] ?? key`, so a Telugu reader sees English
-- here rather than a raw key -- which is the failure that matters. Writing the
-- English into the telugu column would have read as three more completed
-- translations and quietly inflated the 1,591-of-1,600 figure that
-- language_completeness_guard_test and CLAUDE.md both hold the app to. A gap
-- that is visible to a translator is worth more than a count that looks good.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('business_suspended_message',
   'This business is temporarily suspended. Will be available soon.', NULL),
  ('business_unconfirmed_message',
   'Could not confirm this business is active. Check your connection and try again.', NULL),
  ('back_to_business_selector', 'Back To Business Selector', NULL)
ON CONFLICT (translation_key) DO NOTHING;
