-- Two renames, both about the app saying what it means.
--
-- ADD A USER. "Add a Member" and "Add a Customer" were on buttons that do not
-- know yet which of the three a person is going to be -- the Members roster,
-- the Pre-Existing Business screen, the global search's empty state. Naming
-- the role before the Owner has chosen it is how somebody ends up filed as a
-- borrower when they were meant to be an agent, which is a mistake this app
-- has already made once. The role-specific labels stay exactly where the role
-- IS known: Add a Customer on the customer screens, Add an Agent on the
-- workforce ones, Add Investor on the investor ones.
--
-- STRUCK BECOMES ON HOLD. "Struck" is the field word and it is a judgement --
-- a customer who has not paid in six months is not necessarily gone, and the
-- figure beside it may be an ESTIMATE worked out from a loan's own dates
-- rather than a fact read from collections. "On Hold" says the same thing
-- about the money without the app deciding what it means about the person.
-- Only the words change: isStruck, the month dropdown, the chosen-date
-- option and the estimate note are all untouched.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('add_a_user', 'Add a User', 'వినియోగదారుని జోడించండి')
ON CONFLICT (translation_key) DO NOTHING;

UPDATE ui_translations SET english = 'On Hold', telugu = 'నిలిపివేయబడినది'
 WHERE translation_key = 'struck_amount';

UPDATE ui_translations
   SET english = 'Not collected since',
       telugu  = 'నుండి వసూలు కాలేదు'
 WHERE translation_key = 'not_recovered_since';
