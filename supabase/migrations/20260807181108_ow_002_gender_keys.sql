INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('male', 'Male', 'పురుషుడు'),
('female', 'Female', 'స్త్రీ')
ON CONFLICT (translation_key) DO NOTHING;
