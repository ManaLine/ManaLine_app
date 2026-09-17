-- Two words the agent picker needs, and the distinction between them.
--
-- The picker's first draft showed an indeterminate progress bar while it
-- loaded, and an empty-list message if it came back with nothing. Both were
-- wrong in their own way.
--
-- The bar animates forever, and AG-007's layout tests call pumpAndSettle --
-- six of them timed out the moment it was added. The harness's own note
-- records the same thing about the shimmer screens. A settled placeholder
-- says as much and settles.
--
-- And a failed load is not an empty list. "There is no other agent on this
-- business" is a statement about the BOOK; a phone that could not reach the
-- server has not learned anything about the book. Saying the first when the
-- second happened is the app being confidently wrong about somebody's
-- business, which is the failure mode this project treats as worse than a
-- crash.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('loading', 'Loading…', 'లోడ్ అవుతోంది…'),
('could_not_load_agents_note', 'Could not load the agent list.',
 'ఏజెంట్ జాబితాను లోడ్ చేయలేకపోయాము.')
ON CONFLICT (translation_key) DO NOTHING;
