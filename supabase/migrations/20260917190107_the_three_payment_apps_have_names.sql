-- The three providers, for the mode line under Vasool.
--
-- cash, upi, cheque and bank_transfer already exist, from the migration that
-- gave the collection form all four modes. These three are new.
--
-- THE TELUGU IS THE BRAND NAME TRANSLITERATED, not translated. These are
-- products, and a customer in a village says "PhonePe" in either language --
-- the same reason the app writes Cheeti rather than glossing it.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('gpay',    'GPay',    'జీపే'),
('phonepe', 'PhonePe', 'ఫోన్‌పే'),
('paytm',   'Paytm',   'పేటీఎం')
ON CONFLICT (translation_key) DO NOTHING;
