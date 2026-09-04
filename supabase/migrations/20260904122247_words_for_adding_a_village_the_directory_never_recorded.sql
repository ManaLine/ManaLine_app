-- The Add New Village panel, which opens where "No villages found for that
-- PIN" used to be a dead end. Villages the LGD directory has never heard of
-- are legitimate and permanent -- hamlets, new settlements, local names that
-- never entered government records -- so a miss has to be the start of adding
-- one rather than the end of the road.
--
-- did_you_mean_note comes FIRST, before the offer to create, because the
-- cheapest fix for a duplicate is not making it. ichapuram and Ichchapuram are
-- one town (the Owner confirms: the railway station carries the second
-- spelling), they score 0.83, and add_location_if_missing would otherwise
-- write a second row for it and split the customers between them.
--
-- mandal_district_field replaces three free-text boxes. That is where a
-- village came to record its state as "Andhrapradesh" and then narrow every
-- picker to nothing.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('did_you_mean_note',
 'Did you mean one of these?',
 'మీరు వీటిలో ఒకదాన్ని ఉద్దేశించారా?'),
('add_village_named_note',
 'Add "{name}" as a new village',
 '"{name}"ని కొత్త గ్రామంగా జోడించండి'),
('mandal_district_field',
 'Mandal / District',
 'మండలం / జిల్లా'),
('pin_not_in_directory_note',
 'The directory does not carry this PIN code, so mandal and district cannot be suggested.',
 'డైరెక్టరీలో ఈ పిన్ కోడ్ లేదు, కాబట్టి మండలం మరియు జిల్లాను సూచించలేము.'),
('add_this_village',
 'Add This Village',
 'ఈ గ్రామాన్ని జోడించండి')
ON CONFLICT (translation_key) DO NOTHING;
