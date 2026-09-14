-- Which kind of loan, asked only while the question has two answers.
--
-- The Owner's rule: while the migration is open, ASK whether this loan is one
-- already running in the old book or new money going out today; once the
-- migration is locked, only new. So the question disappears by itself when a
-- book goes live, and nobody is ever asked something with one answer.
--
-- It is a money question, not a wording one. A pre-existing loan is a balance
-- carried in through app.migrate_loan and it does not touch BF, because that
-- cash left the till before the app existed. A new loan is cash leaving the
-- till today and it moves BF. Writing one when the Owner meant the other is a
-- wrong number that nothing downstream would flag -- which is why both options
-- say what they mean about the money rather than just naming themselves.
--
-- loan_saved_for_note names the person. An Owner entering twenty of these in a
-- sitting needs to see WHOSE loan just saved before deciding to do another;
-- "Saved." alone would be the same sentence twenty times.
--
-- open_customer_to_lend_note is an honest limit. Issuing a new loan needs a
-- customers row, and the found-person path has only a person -- searching
-- finds identities, not customer records. Saying so beats opening a lending
-- screen that cannot find them.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('which_kind_of_loan', 'Which Kind of Loan?', 'ఏ రకమైన రుణం?'),
('pre_existing_loan', 'Already Running', 'ఇప్పటికే నడుస్తున్నది'),
('pre_existing_loan_note',
 'A loan from the old book. Enter the balance as it stands today.',
 'పాత పుస్తకంలోని రుణం. నేటి నాటికి ఉన్న బ్యాలెన్స్‌ను నమోదు చేయండి.'),
('new_loan_cash_note', 'Money going out today, from your cash in hand.',
 'ఈ రోజు మీ చేతిలోని నగదు నుండి వెళ్తున్న డబ్బు.'),
('save_and_enter_another', 'Enter Another', 'మరొకటి నమోదు చేయండి'),
('loan_saved_for_note', 'Loan saved for {name}.',
 '{name} కోసం రుణం సేవ్ చేయబడింది.'),
('open_customer_to_lend_note',
 'Open this customer from the customer list to lend to them.',
 'వారికి రుణం ఇవ్వడానికి కస్టమర్ జాబితా నుండి ఈ కస్టమర్‌ను తెరవండి.')
ON CONFLICT (translation_key) DO NOTHING;
