-- The agent's dashboard line was labelled UPI and summed only UPI. It now
-- covers every online mode -- GPay, PhonePe, Paytm and the historical UPI --
-- so the word has to widen with it, or the label names one app while the
-- figure counts four.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('online_payment', 'Online Payment', 'ఆన్‌లైన్ చెల్లింపు')
ON CONFLICT (translation_key) DO NOTHING;
