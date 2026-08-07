INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('customers_due', 'Customers Due', 'బకాయి కస్టమర్లు'),
('no_customers_due_right_now', 'No customers due right now.', 'ప్రస్తుతం ఎవరూ బకాయి లేరు.'),
('sorted_by_note_short', 'Sorted by: penalty → grace period → today''s due → village', 'క్రమం: జరిమానా → గ్రేస్ పీరియడ్ → నేటి బకాయి → గ్రామం'),
('todays_collection_total', 'Today''s Collection Total', 'నేటి వసూలు మొత్తం')
ON CONFLICT (translation_key) DO NOTHING;
