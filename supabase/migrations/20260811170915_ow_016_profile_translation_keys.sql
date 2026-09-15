INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('my_profile', 'My Profile', 'నా ప్రొఫైల్'),
('could_not_load_profile_plain', 'Could not load profile.', 'ప్రొఫైల్ లోడ్ కాలేదు.'),
('edit', 'Edit', 'మార్చండి'),
('businesses_owned', 'Businesses Owned', 'స్వంత వ్యాపారాలు'),
('no_businesses_found', 'No businesses found.', 'వ్యాపారాలు కనుగొనబడలేదు.'),
('no_address_on_file', 'No address on file.', 'ఫైల్‌లో చిరునామా లేదు.'),
('add_profile_photo', 'Add Profile Photo', 'ప్రొఫైల్ ఫోటో జోడించండి'),
('change_profile_photo', 'Change Profile Photo', 'ప్రొఫైల్ ఫోటో మార్చండి'),
('edit_address', 'Edit Address', 'చిరునామా మార్చండి')
ON CONFLICT (translation_key) DO NOTHING;
