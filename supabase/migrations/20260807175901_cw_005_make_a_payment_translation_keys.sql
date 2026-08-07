INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('selected_loan', 'Selected Loan', 'ఎంచుకున్న రుణం'),
('payment_amount', 'Payment Amount', 'చెల్లింపు మొత్తం'),
('payment_amount_field', 'Payment Amount *', 'చెల్లింపు మొత్తం *'),
('enter_a_valid_amount', 'Enter A Valid Amount', 'సరైన మొత్తం నమోదు చేయండి'),
('waiting_for_upi_app', 'Waiting for UPI app…', 'UPI యాప్ కోసం వేచి ఉంది…'),
('pay_via_upi', 'Pay Via UPI', 'UPI ద్వారా చెల్లించండి'),
('payment_submitted', 'Payment Submitted', 'చెల్లింపు సమర్పించబడింది'),
('amount_submitted_note', '{amount} submitted {date}', '{amount} {date}న సమర్పించారు'),
('submitted_status_note', 'Status: Submitted By Customer — Pending Owner/Agent Confirmation. You will be notified once it is confirmed.', 'స్థితి: కస్టమర్ సమర్పించారు — యజమాని/ఏజెంట్ నిర్ధారణ పెండింగ్‌లో ఉంది. నిర్ధారించిన తర్వాత మీకు తెలియజేయబడుతుంది.'),
('check_status', 'Check Status', 'స్థితి తనిఖీ చేయండి'),
('back_to_loan_detail', 'Back To Loan Detail', 'రుణ వివరాలకు తిరిగి వెళ్లండి'),
('payment_confirmed', 'Payment Confirmed', 'చెల్లింపు నిర్ధారించబడింది'),
('posted_to_loan_note', '{amount} posted to this loan.', '{amount} ఈ రుణానికి పోస్ట్ చేయబడింది.'),
('view_loan', 'View Loan', 'రుణం చూడండి'),
('payment_could_not_be_confirmed', 'Payment Could Not Be Confirmed', 'చెల్లింపు నిర్ధారించలేకపోయింది'),
('contact_business_note', 'Please contact the Business directly to resolve this payment.', 'ఈ చెల్లింపును పరిష్కరించడానికి దయచేసి నేరుగా వ్యాపారాన్ని సంప్రదించండి.'),
('back_to_my_loans', 'Back To My Loans', 'నా రుణాలకు తిరిగి వెళ్లండి')
ON CONFLICT (translation_key) DO NOTHING;
