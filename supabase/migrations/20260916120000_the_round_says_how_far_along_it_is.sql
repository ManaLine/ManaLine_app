-- How far through the round the agent is.
--
-- The collection round listed every door and said nothing about progress. An
-- agent halfway down a village had no answer to "how many left" except
-- counting the rows they had already walked past.
--
-- telugu IS LEFT NULL ON PURPOSE. TranslationCache.t() resolves
-- `row[language] ?? row['English'] ?? key`, so a Telugu reader sees English
-- rather than a raw key. Writing English into the telugu column would read as
-- a completed translation and inflate the figure CLAUDE.md holds the app to.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('round_progress', '{done} of {total} collected', NULL)
ON CONFLICT (translation_key) DO NOTHING;
