INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('todays_investments', 'Today''s Investments', 'నేటి పెట్టుబడులు'),
('todays_withdrawals', 'Today''s Withdrawals', 'నేటి ఉపసంహరణలు'),
('todays_expenses', 'Today''s Expenses', 'నేటి ఖర్చులు'),
('todays_outstanding', 'Today''s Outstanding', 'నేటి బాకీ'),
('todays_difference', 'Today''s Difference', 'నేటి తేడా'),
('brought_forward', 'BF', 'BF')
ON CONFLICT (translation_key) DO NOTHING;
