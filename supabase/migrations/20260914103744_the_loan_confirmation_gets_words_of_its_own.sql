-- The confirmation that shows the numbers nobody typed.
--
-- Three figures go into a pre-existing loan and five come out: interest is
-- repayment - given - fee, and collected is repayment - remaining. Both are
-- derived by app.migrate_loan and neither appears on the form, so an Owner
-- entering a loan is settling two numbers they have never seen.
--
-- The entry form already REFUSES the impossible -- a repayment below what was
-- handed over, a balance above the repayment. That is not the same as showing
-- the possible-but-wrong, which is the one that reaches a doorstep: 12,000
-- mistyped as 1,200 is arithmetically perfect and completely false.
--
-- These words come from the migration screen's own "Check This Loan" dialog,
-- which has had this confirmation since it was written and had it in
-- HARDCODED ENGLISH -- so an Owner reading the app in Telugu got the one
-- screen that states the money back to them in a language they may not read.
-- Moving it to the shared sheet is also the first time it has had keys.
--
-- loan_issued_on_note exists because effective_date does not carry a
-- placeholder: it is the FIELD LABEL, and calling replaceAll on it would have
-- rendered "Effective Date" and silently dropped the date.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('check_this_loan', 'Check This Loan', 'ఈ రుణాన్ని సరిచూడండి'),
('go_back', 'Go Back', 'వెనుకకు వెళ్లండి'),
('save_this_loan', 'Save This Loan', 'ఈ రుణాన్ని సేవ్ చేయండి'),
('loan_issued_on_note', 'Issued {date}', '{date}న ఇవ్వబడింది')
ON CONFLICT (translation_key) DO NOTHING;
