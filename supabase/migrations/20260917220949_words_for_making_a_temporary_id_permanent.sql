-- The MLTI -> MLPI upgrade, in both workspaces.
--
-- THE EXPLAINER IS NOT DECORATION. "MLTI" means nothing to an Owner and less
-- to a customer standing at their own door being asked for an Aadhaar card.
-- The screen has to say what it wants and why in one sentence, or the answer
-- is "no".
--
-- 'id_now_permanent' names BOTH IDs on purpose. The MLID is what a person
-- would type to sign in, so an upgrade changes their login. Showing the new
-- one while the customer is still standing there is the only moment it can be
-- handed over; a confirmation that said only "done" would leave them with an
-- ID nobody told them about.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('temporary_ids',        'Temporary IDs',        'తాత్కాలిక IDలు'),
('temporary_id',         'Temporary ID',         'తాత్కాలిక ID'),
('make_permanent',       'Make Permanent',       'శాశ్వతం చేయండి'),
('temporary_id_explainer',
 'These customers were entered from a paper book and have a temporary ID. Adding their Aadhaar number gives them a permanent one.',
 'ఈ కస్టమర్లు కాగితం పుస్తకం నుండి నమోదు చేయబడ్డారు, వారికి తాత్కాలిక ID ఉంది. వారి ఆధార్ నంబర్ జోడిస్తే శాశ్వత ID వస్తుంది.'),
('no_temporary_ids',     'Every customer on this book has a permanent ID.',
 'ఈ పుస్తకంలోని ప్రతి కస్టమర్‌కు శాశ్వత ID ఉంది.'),
('aadhaar_12_digits',    'Aadhaar must be 12 digits.', 'ఆధార్ 12 అంకెలు ఉండాలి.'),
('date_of_birth',        'Date of Birth',        'పుట్టిన తేదీ'),
('take_live_photo',      'Take Live Photo',      'లైవ్ ఫోటో తీయండి'),
('photo_captured',       'Photo Captured',       'ఫోటో తీయబడింది'),
('retake',               'Retake',               'మళ్లీ తీయండి'),
('id_now_permanent',     '{name} now has a permanent ID: {mlid}',
 '{name}కు ఇప్పుడు శాశ్వత ID ఉంది: {mlid}'),
('photo_required_for_permanent', 'A live photo is required.',
 'లైవ్ ఫోటో అవసరం.'),
('dob_required_for_permanent',   'A date of birth is required.',
 'పుట్టిన తేదీ అవసరం.')
ON CONFLICT (translation_key) DO NOTHING;
