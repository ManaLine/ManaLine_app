INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('duration', 'Duration', 'వ్యవధి'),
('installment', 'Installment', 'వాయిదా')
ON CONFLICT (translation_key) DO NOTHING;
