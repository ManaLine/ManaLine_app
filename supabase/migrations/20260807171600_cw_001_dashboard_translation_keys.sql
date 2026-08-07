INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('my_account', 'My Account', 'నా ఖాతా'),
('my_profile', 'My Profile', 'నా ప్రొఫైల్'),
('my_summary', 'My Summary', 'నా సారాంశం'),
('active_loans', 'Active Loans', 'యాక్టివ్ రుణాలు'),
('total_outstanding', 'Total Outstanding', 'మొత్తం బాకీ'),
('next_payment_due', 'Next Payment Due', 'తదుపరి చెల్లింపు గడువు'),
('pending_loan_requests', 'Pending Loan Requests', 'పెండింగ్ రుణ అభ్యర్థనలు'),
('pending_online_payments', 'Pending Online Payments', 'పెండింగ్ ఆన్‌లైన్ చెల్లింపులు'),
('no_business_memberships_yet', 'No Business Memberships Yet', 'ఇంకా వ్యాపార సభ్యత్వాలు లేవు'),
('find_business_membership_note', 'Find a Business to request Customer membership. Once the Owner or Agent approves, it will appear here.', 'కస్టమర్ సభ్యత్వం కోసం అభ్యర్థించడానికి ఒక వ్యాపారాన్ని కనుగొనండి. యజమాని లేదా ఏజెంట్ ఆమోదించిన తర్వాత, అది ఇక్కడ కనిపిస్తుంది.'),
('switch_business', 'Switch Business', 'వ్యాపారం మార్చండి')
ON CONFLICT (translation_key) DO NOTHING;
