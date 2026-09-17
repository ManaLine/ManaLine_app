-- A failed load needs words. The alternative on the Line Pending List was
-- printing e.toString() at an Owner -- "PostgrestException(message: ..., code:
-- PGRST203)" -- which is neither English nor Telugu, and tells somebody
-- standing in a field nothing they can act on.
--
-- Pull to refresh is the action, and the list is already inside a
-- RefreshIndicator, so the message names that rather than offering a second
-- button that would do the same thing.
--
-- NOTE: the Telugu inserted by this migration contained a Devanagari letter.
-- It is corrected by 20260917193350, which runs immediately after. Left as it
-- ran rather than edited to look right.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('could_not_load_pull_to_retry',
 'Could not load this list. Pull down to try again.',
 'ఈ జాబితాను లోడ్ చేయलేకపోయాం. మళ్లీ ప్రయత్నించడానికి కిందికి లాగండి.')
ON CONFLICT (translation_key) DO NOTHING;
