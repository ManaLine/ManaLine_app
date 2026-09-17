-- OW-009 now shows accounts, not days, so its empty state means something
-- different and must say something different.
--
-- 'no_business_days_yet' was true when the screen listed every day_ledger row:
-- an empty list meant the book had never been touched. Now the list is
-- filtered to days that carry an account, and three of the five live books
-- have ledger rows but no accounts at all -- 6, 4 and 2 empty days each. Those
-- Owners would have read "no business days yet" beside a book they know they
-- have opened, which is the app calling them wrong.
--
-- CLAUDE.md, on widening a filter: "Ask what reads this, and what that thing
-- takes it to mean." The filter here narrowed, and this string is the thing
-- that read it.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('no_accounts_yet',
 'No accounts yet. A day appears here once it has a collection, a loan or an expense on it.',
 'ఇంకా ఖాతాలు లేవు. ఒక రోజున వసూల్, అప్పు లేదా ఖర్చు నమోదైన తర్వాత అది ఇక్కడ కనిపిస్తుంది.')
ON CONFLICT (translation_key) DO NOTHING;
