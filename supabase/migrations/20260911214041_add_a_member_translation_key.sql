-- One link where Business Management had two.
--
-- "Add Existing Agent" and "Add Existing Customer" each opened their own
-- dialog asking for a MANA LINE ID typed from memory -- a box that could not
-- search, could not confirm the ID belonged to the person meant, and offered
-- nothing at all to somebody who did not have one. Neither could add an
-- Investor.
--
-- The word "existing" is dropped everywhere with them: adding somebody who is
-- already registered and adding somebody who is not are the same errand now,
-- answered by one search.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('add_a_member', 'Add a Member', 'సభ్యుడిని జోడించండి')
ON CONFLICT (translation_key) DO NOTHING;
