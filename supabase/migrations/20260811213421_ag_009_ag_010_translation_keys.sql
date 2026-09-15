INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('profile', 'Profile', 'ప్రొఫైల్'),
('route_area_assignment', 'Route / Area Assignment', 'మార్గం / ప్రాంత కేటాయింపు'),
('my_compensation', 'My Compensation', 'నా వేతనం'),
('other_business_memberships', 'Other Business Memberships', 'ఇతర వ్యాపార సభ్యత్వాలు'),
('tenancy_isolation_note', 'Each Owner sees only their own tenancy''s data for you — nothing here is shared or blended across businesses.', 'ప్రతి యజమాని మీ గురించి వారి స్వంత టెనెన్సీ డేటాను మాత్రమే చూస్తారు — ఇక్కడ ఏదీ వ్యాపారాల మధ్య పంచుకోబడదు లేదా కలపబడదు.'),
('phone', 'Phone', 'ఫోన్'),
('joined_date_label', 'Joined Date', 'చేరిన తేదీ'),
('no_operating_areas_assigned', 'No Operating Areas currently assigned.', 'ప్రస్తుతం పని ప్రాంతాలు కేటాయించలేదు.'),
('in_session', 'In Session', 'సెషన్‌లో'),
('compensation_not_available', 'Compensation not yet available', 'వేతనం ఇంకా అందుబాటులో లేదు'),
('transaction_history', 'Transaction History', 'లావాదేవీల చరిత్ర'),
('total_collected_last_100', 'Total Collected (Last 100)', 'మొత్తం వసూలు (చివరి 100)'),
('no_transactions_recorded_yet', 'No transactions recorded yet.', 'ఇంకా లావాదేవీలు నమోదు కాలేదు.'),
('loan_number_note', 'Loan {number}', 'రుణం {number}'),
('receipt_note', 'Receipt: {number}', 'రసీదు: {number}')
ON CONFLICT (translation_key) DO NOTHING;
