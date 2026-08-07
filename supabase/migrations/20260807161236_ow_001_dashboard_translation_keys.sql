-- New ui_translations rows for OW-001 Owner Home Dashboard — phase 1 of
-- wiring the strings the text audit found hardcoded. Telugu marked (AI
-- draft) below is unreviewed, same honest caveat as 0047/0048.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('new_loan', 'New Loan', 'కొత్త రుణం'),
('group_loan_management', 'Group Loan Management', 'సమూహ రుణ నిర్వహణ'),
('workforce', 'Workforce', 'శ్రామికులు'),
('investors', 'Investors', 'పెట్టుబడిదారులు'),
('investor', 'Investor', 'పెట్టుబడిదారు'),
('account_review', 'Account Review', 'ఖాతా సమీక్ష'),
('live_business_activity', 'Live Business Activity', 'ప్రత్యక్ష వ్యాపార కార్యకలాపం'),
('attention_required', 'Attention Required', 'శ్రద్ధ అవసరం'),
('see_all', 'See All', 'అన్నీ చూడండి'),
('loan_requests', 'Loan Requests', 'రుణ అభ్యర్థనలు'),
('group_loans', 'Group Loans', 'సమూహ రుణాలు'),
('day_closure', 'Day Closure', 'దిన ముగింపు'),
('daily_record_book', 'Daily Record Book', 'రోజువారీ రికార్డు పుస్తకం'),
('reports', 'Reports', 'నివేదికలు'),
('add_existing_investor', 'Add Existing Investor', 'ఇప్పటికే ఉన్న పెట్టుబడిదారుని జోడించండి'),
('investor_requests', 'Investor Requests', 'పెట్టుబడిదారు అభ్యర్థనలు'),
('withdrawal_requests', 'Withdrawal Requests', 'ఉపసంహరణ అభ్యర్థనలు'),
('notifications', 'Notifications', 'నోటిఫికేషన్‌లు'),
('nothing_else_to_report', 'Nothing else to report.', 'నివేదించడానికి మరేమీ లేదు.'),
('no_notifications_yet', 'No notifications yet.', 'ఇంకా నోటిఫికేషన్‌లు లేవు.'),
('more_options', 'More Options', 'మరిన్ని ఎంపికలు'),
('search', 'Search', 'శోధించండి'),
('search_by_phone_mlid_aadhaar_name', 'Search by Phone, MANA LINE ID, Aadhaar, or Name.', 'ఫోన్, MANA LINE ID, ఆధార్ లేదా పేరు ద్వారా శోధించండి.'),
('not_a_member_of_business', 'Not a member of this business.', 'ఈ వ్యాపారంలో సభ్యుడు కాదు.'),
('could_not_load_dashboard', 'Could Not Load Dashboard', 'డాష్‌బోర్డ్ లోడ్ కాలేదు'),
('session_timed_out', 'Session Timed Out', 'సెషన్ గడువు ముగిసింది'),
('retry', 'Retry', 'మళ్ళీ ప్రయత్నించండి'),
('no_activity_today', 'No activity yet today.', 'ఈరోజు ఇంకా కార్యకలాపం లేదు.'),
('nothing_needs_attention', 'Nothing needs attention right now.', 'ప్రస్తుతం దేనికీ శ్రద్ధ అవసరం లేదు.')
ON CONFLICT (translation_key) DO NOTHING;
