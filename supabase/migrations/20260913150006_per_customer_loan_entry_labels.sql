-- Typing one customer's existing loan out of a paper book.
--
-- Most labels this form needs already exist -- amount_given, effective_date,
-- installment_amount, processing_fee, repayment_type, grace_period_end_date.
-- These are the ones that did not.
--
-- The problem messages are sentences an Owner can act on, not codes. Each one
-- names the rule app.migrate_loan actually applies:
--   interest is repayment - given - fee, so a repayment below what was handed
--   over is negative interest;
--   collected is repayment - remaining, so a balance above the repayment
--   stores a negative amount collected.
-- Both are silent corruptions rather than errors, which is why they are caught
-- before the row is sent rather than explained after the server refuses it.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('repayment_amount', 'Repayment Amount', 'తిరిగి చెల్లింపు మొత్తం'),
('remaining_balance', 'Remaining Balance', 'మిగిలిన బ్యాలెన్స్'),
('add_loan', 'Add Loan', 'రుణం జోడించండి'),
('loan_problem_negative_interest',
 'Repayment is less than the amount given plus the fee. Check these three figures.',
 'తిరిగి చెల్లింపు, ఇచ్చిన మొత్తం మరియు ఫీజు కంటే తక్కువగా ఉంది. ఈ మూడు సంఖ్యలను సరిచూడండి.'),
('loan_problem_balance_above_repayment',
 'Remaining balance cannot be more than the repayment amount.',
 'మిగిలిన బ్యాలెన్స్ తిరిగి చెల్లింపు మొత్తం కంటే ఎక్కువ ఉండకూడదు.'),
('loan_problem_nothing_outstanding',
 'Nothing is outstanding, so there is no loan to bring across.',
 'బాకీ ఏమీ లేదు, కాబట్టి తీసుకురావడానికి రుణం లేదు.'),
('loan_problem_no_instalment', 'Enter the instalment amount.',
 'వాయిదా మొత్తాన్ని నమోదు చేయండి.'),
('loan_problem_unknown_frequency', 'Choose Daily, Weekly or Monthly.',
 'రోజువారీ, వారానికి లేదా నెలవారీ ఎంచుకోండి.'),
('loans_already_entered', '{count} already entered', '{count} ఇప్పటికే నమోదైంది'),
('balance_only_note',
 'Enter the balance as it stands today. Instalment history is not asked for here.',
 'నేటి నాటికి ఉన్న బ్యాలెన్స్‌ను నమోదు చేయండి. ఇక్కడ వాయిదాల చరిత్ర అడగబడదు.')
ON CONFLICT (translation_key) DO NOTHING;
