-- A page that looks identical before and after saving invites a second entry.
--
-- The one-by-one door shows one person per page, and the Owner swipes on. With
-- nothing marking the page they just finished, coming back to it later -- or
-- swiping back one to check -- gives no sign the entry landed. Entering the
-- same investor twice is caught server-side and reported as skipped rather
-- than doubled, but making somebody rely on that is making them test the
-- safety net instead of reading the screen.
--
-- Scoped to this sitting deliberately. Reopening the screen re-reads the
-- server, because the server is the authority on what is already in the book
-- and a remembered "done" flag on the handset is not.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('entered_in_this_sitting', 'Entered.', 'నమోదైంది.')
ON CONFLICT (translation_key) DO NOTHING;
