-- ManaLedgerTable's desk-width header row (Plan 2a Task 4 gap-closure) reads
-- ref.t('time'), ref.t('description'), ref.t('amount'). 'time' and 'amount'
-- already exist; 'description' does not, so TranslationCache's documented
-- never-blocks-on-missing-translation fallback drew the raw key
-- "description" in lowercase on every desk-width ledger screen -- also a
-- Title Case violation per 11_UI_Guidelines.
--
-- Three-column shape (translation_key, english, telugu), matching
-- 20260808220000_owner_utility_translation_keys.sql -- not the five-column
-- shape of 20260812133534_ledger_history_translation_keys.sql, because this
-- pass supplies only what can be supplied confidently. Telugu is left NULL
-- rather than guessed: the same way 'amount' itself already carries a NULL
-- hindi/tamil/kannada from its own three-column insert
-- (20260807180725_ow_002_workforce_management_translation_keys.sql) -- an
-- unlisted/NULL language column is this table's existing convention for "not
-- supplied yet," and TranslationCache falls back to English for it, not to a
-- raw key.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('description', 'Description', NULL)
ON CONFLICT (translation_key) DO NOTHING;
