-- The members roster listed people in whatever order the query returned them.
--
-- An Owner looking for somebody scans by name; an Owner planning a round
-- scans by village. Neither is served by insertion order, and on a book with
-- fifty-six members the difference is between finding a person and reading
-- every row.
--
-- Village sorts EMPTY LAST rather than first: a member with no current
-- address on file is a real state, and burying the addressed majority under
-- the unaddressed few would make the sort useless for the round it exists for.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('sort_by', 'Sort by', 'క్రమబద్ధీకరించు'),
('sort_by_name', 'Name (A–Z)', 'పేరు (A–Z)'),
('sort_by_village', 'Village (A–Z)', 'గ్రామం (A–Z)'),
('no_village_on_file', 'No village on file', 'గ్రామం నమోదు కాలేదు')
ON CONFLICT (translation_key) DO NOTHING;
