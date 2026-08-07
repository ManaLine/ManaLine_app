INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('village_already_existed_note', 'That village already existed — selected it.', 'ఆ గ్రామం ఇప్పటికే ఉంది — దాన్ని ఎంచుకున్నారు.'),
('village_added_note', 'Village added and selected.', 'గ్రామం జోడించి ఎంచుకున్నారు.')
ON CONFLICT (translation_key) DO NOTHING;
