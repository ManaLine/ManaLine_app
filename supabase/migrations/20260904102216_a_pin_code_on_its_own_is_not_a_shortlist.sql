-- Typing a PIN used to search on the PIN alone and answer with every village
-- it carries -- fifty for 517536, twenty-four for 524129. That is the
-- directory, not a shortlist, and scrolling it to find a name you already know
-- is slower than typing three letters of it.
--
-- The Owner's rule: PIN plus at least three letters of the village name, sorted
-- A to Z. A PIN on its own returns nothing and the screen asks for the name.
--
-- Two silences that must not read alike, hence two strings:
--   enter_village_name_to_search -- nothing has been searched for yet
--   no_villages_found_for_pin    -- searched, and there is genuinely no match
-- Conflating them is exactly how "No villages found for that PIN" came to be
-- shown for a PIN that had fifty villages behind it.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('village_name_field',
 'Village Name',
 'గ్రామం పేరు'),
('enter_village_name_to_search',
 'Enter at least 3 letters of the village name.',
 'గ్రామం పేరులోని కనీసం 3 అక్షరాలు నమోదు చేయండి.')
ON CONFLICT (translation_key) DO NOTHING;
