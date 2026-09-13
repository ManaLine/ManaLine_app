-- Pressing Save with an empty box used to do nothing at all.
--
-- The guard itself is right: an empty box is NOT zero. Zero is a deliberate
-- "nothing owed" and clears the declaration; an empty box is somebody who has
-- not answered yet, and writing it as zero would record a decision the Owner
-- never made.
--
-- Returning quietly was the mistake. The button looked broken, and a silent
-- no-op is indistinguishable from a failed write -- which is exactly how this
-- book ended up with two Karri Priyanka rows created two minutes apart. Its
-- first fix reused the loan form's message with a string substitution, which
-- works in English and produces the untouched English sentence in Telugu.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('enter_amount_owed',
 'Enter the amount owed, or 0 if nothing is.',
 'బాకీ ఉన్న మొత్తాన్ని నమోదు చేయండి, ఏమీ లేకపోతే 0 అని నమోదు చేయండి.')
ON CONFLICT (translation_key) DO NOTHING;
