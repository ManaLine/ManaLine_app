INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('history', 'History', 'చరిత్ర'),
('net_change_this_view', 'Net Change (This View)', 'నికర మార్పు (ఈ వీక్షణ)'),
('no_transactions_yet', 'No transactions yet.', 'ఇంకా లావాదేవీలు లేవు.')
ON CONFLICT (translation_key) DO NOTHING;
