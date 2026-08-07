-- installment_amount landed in the same DB session as 20260807174508 but as
-- a separate apply_migration call; kept as its own stamped file to match
-- supabase_migrations.schema_migrations exactly.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('installment_amount', 'Installment Amount', 'వాయిదా మొత్తం')
ON CONFLICT (translation_key) DO NOTHING;
