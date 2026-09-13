-- The second door into a pre-existing book: one person at a time.
--
-- The bulk wizard is seven pages of grids and a spreadsheet. Right for two
-- hundred customers, wrong for three investors, and wrong for the one person
-- the wizard missed -- finishing that entry means walking all seven pages
-- again.
--
-- WHICH DOOR SUITS IS DECIDED PER STAGE, not per business. A real book has 200
-- customers, 2 agents and 3 investors: the wizard is the only sane way to do
-- the customers, and building a spreadsheet for the other five people is not.
-- many_people_use_the_wizard_note is how the app says that ON SCREEN 0 rather
-- than letting somebody find it out on screen 40.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('enter_one_by_one', 'Enter One by One', 'ఒక్కొక్కరిగా నమోదు చేయండి'),
('entry_stage_investors', 'Investors', 'పెట్టుబడిదారులు'),
('entry_stage_agents', 'Agents', 'ఏజెంట్లు'),
('entry_stage_customers', 'Customers & Loans', 'కస్టమర్లు & రుణాలు'),
('person_of_total', '{n} of {total}', '{total}లో {n}'),
('nobody_in_this_stage_yet', 'Nobody in this business holds this role yet.',
 'ఈ వ్యాపారంలో ఇంకా ఎవరూ ఈ పాత్రలో లేరు.'),
('person_not_in_this_stage', 'This person does not hold that role in this business.',
 'ఈ వ్యక్తి ఈ వ్యాపారంలో ఆ పాత్రను కలిగి లేరు.'),
('many_people_use_the_wizard_note',
 'This stage has {count} people. One by one means {count} screens — the Bulk Onboarding Wizard is faster for this many.',
 'ఈ దశలో {count} మంది ఉన్నారు. ఒక్కొక్కరిగా అంటే {count} స్క్రీన్‌లు — ఇంత మందికి బల్క్ ఆన్‌బోర్డింగ్ విజార్డ్ వేగవంతమైనది.')
ON CONFLICT (translation_key) DO NOTHING;
