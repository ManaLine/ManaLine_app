-- The account sheet's own vocabulary.
--
-- VASOOL, KARCHU, VADDI -- the words the business uses, on the sheet the
-- business has always used. They are not translations of "Collections",
-- "Loan Distribution" and "Interest"; they are what these lines are called,
-- and the English on the old screen was the abstraction. The app already
-- says "Cheeti" for the same reason.
--
-- The English column carries the vernacular with a gloss in brackets, because
-- this app has an English UI as well as a Telugu one and an Owner reading it
-- in English still runs a line business. The Telugu column is the word alone
-- -- a gloss there would be explaining somebody's own vocabulary to them.
--
-- next_bf is what the closing figure IS. The paper sheet writes it under the
-- two totals as the next day's Brought Forward, which is the point of
-- carrying it: one day's closing is the next day's opening, and naming it
-- that way is what makes the chain visible.
--
-- of_which_penalty is a NOTE, not a row. Penalty is already inside Vasool --
-- it arrived as part of ordinary collections -- and a two-column sheet adds
-- its columns up, so a penalty line in Credits would overstate the day by
-- exactly the penalties collected. The old screen could keep that straight
-- with a comment beside a figure because nothing summed the figures. This one
-- cannot, so the information moves beside the sheet instead of into it.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('vasool', 'Vasool (Collections)', 'వసూల్'),
('karchu', 'Karchu (Loans Given)', 'ఖర్చు'),
('vaddi', 'Vaddi (Interest)', 'వడ్డీ'),
('brought_forward', 'Brought Forward (BF)', 'గత నిల్వ (BF)'),
('short_excess', 'Excess / Short', 'అధికం / తక్కువ'),
('credits', 'Credits', 'జమ'),
('debits', 'Debits', 'ఖర్చు'),
('next_bf', 'Next BF', 'తదుపరి BF'),
('account_sheet', 'Account Sheet', 'ఖాతా షీట్'),
('add_row', 'Add Row', 'వరుస జోడించండి'),
('rows_to_show', 'Rows To Show', 'చూపవలసిన వరుసలు'),
('of_which_penalty', 'Includes {amount} penalty',
 '{amount} జరిమానా ఇందులో ఉంది')
ON CONFLICT (translation_key) DO NOTHING;
