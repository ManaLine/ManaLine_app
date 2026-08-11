-- Applied via MCP as owner_utility_screens_translation_keys.
-- English values follow 11_UI_Guidelines' locked Title Case rule: minor words
-- (a/an/the/of/in/for/and/or/to) stay lowercase unless first. ManaText used to
-- enforce that on literals; ManaText.raw + ui_translations moves the job here.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('backup', 'Backup', 'బ్యాకప్'),
('export_to_excel', 'Export to Excel', 'ఎక్సెల్‌కు ఎగుమతి చేయండి'),
('share_file', 'Share File', 'ఫైల్ షేర్ చేయండి'),
('could_not_share_file_note', 'Could not share the file: {error}', 'ఫైల్ షేర్ చేయలేకపోయాము: {error}'),
('export_to_excel_note', 'Creates a spreadsheet of your customers, loans, collections, expenses, investments and daily ledger. Deleted records are not included.', 'మీ కస్టమర్లు, రుణాలు, వసూళ్లు, ఖర్చులు, పెట్టుబడులు మరియు రోజువారీ లెడ్జర్ యొక్క స్ప్రెడ్‌షీట్ సృష్టిస్తుంది. తొలగించిన రికార్డులు చేర్చబడవు.'),
('truncated_sheets_note', 'Some sheets were too large and were cut to {rows} rows: {sheets}. This backup is incomplete.', 'కొన్ని షీట్‌లు చాలా పెద్దవి కావడంతో {rows} వరుసలకు కత్తిరించబడ్డాయి: {sheets}. ఈ బ్యాకప్ అసంపూర్ణం.'),
('business_transfer', 'Business Transfer', 'వ్యాపార బదిలీ'),
('transfer_this_business_question', 'Transfer This Business?', 'ఈ వ్యాపారాన్ని బదిలీ చేయాలా?'),
('send_offer', 'Send Offer', 'ఆఫర్ పంపండి'),
('offered_to_you', 'Offered to You', 'మీకు ఆఫర్ చేయబడింది'),
('waiting_to_be_accepted', 'Waiting to Be Accepted', 'అంగీకారం కోసం వేచి ఉంది'),
('hand_business_to_someone', 'Hand This Business to Someone', 'ఈ వ్యాపారాన్ని ఎవరికైనా అప్పగించండి'),
('transfer_business_note', 'They have to accept before anything moves. Settle your own agent cash and review any waiting settlements first.', 'ఏదైనా కదిలే ముందు వారు అంగీకరించాలి. ముందుగా మీ స్వంత ఏజెంట్ నగదును సెటిల్ చేసి, వేచి ఉన్న సెటిల్‌మెంట్లను సమీక్షించండి.'),
('their_mlid_field', 'Their MLID', 'వారి MLID'),
('find_person', 'Find Person', 'వ్యక్తిని కనుగొనండి'),
('note_optional_field', 'Note (optional)', 'గమనిక (ఐచ్ఛికం)'),
('import_records', 'Import Records', 'రికార్డులు దిగుమతి చేయండి'),
('could_not_build_template_note', 'Could not build the template: {error}', 'టెంప్లేట్ నిర్మించలేకపోయాము: {error}'),
('spreadsheet', 'Spreadsheet', 'స్ప్రెడ్‌షీట్'),
('import_records_note', 'Enter loans your business already had before it came onto MANA LINE. If any row is wrong, nothing is imported — fix the sheet and upload it again.', 'మానా లైన్‌కు రాకముందే మీ వ్యాపారంలో ఉన్న రుణాలను నమోదు చేయండి. ఏదైనా వరుస తప్పు అయితే, ఏదీ దిగుమతి కాదు — షీట్ సరిచేసి మళ్లీ అప్‌లోడ్ చేయండి.'),
('step_1', 'Step 1', 'దశ 1'),
('get_template', 'Get Template', 'టెంప్లేట్ పొందండి'),
('step_2', 'Step 2', 'దశ 2'),
('choose_file', 'Choose File', 'ఫైల్ ఎంచుకోండి'),
('step_3', 'Step 3', 'దశ 3'),
('import_label', 'Import', 'దిగుమతి'),
('loans_imported_note', '{count} loans imported.', '{count} రుణాలు దిగుమతి చేయబడ్డాయి.'),
('nothing_imported_note', 'Nothing was imported. {count} rows need fixing:', 'ఏదీ దిగుమతి కాలేదు. {count} వరుసలు సరిచేయాలి:'),
('row_error_note', 'Row {row}: {message}', 'వరుస {row}: {message}'),
('loan_requests', 'Loan Requests', 'రుణ అభ్యర్థనలు'),
('reject_loan_request', 'Reject Loan Request', 'రుణ అభ్యర్థనను తిరస్కరించండి'),
('could_not_load_loan_requests_note', 'Could not load loan requests.\n{error}', 'రుణ అభ్యర్థనలు లోడ్ కాలేదు.\n{error}'),
('no_pending_loan_requests', 'No pending loan requests.', 'పెండింగ్ రుణ అభ్యర్థనలు లేవు.'),
('subscription', 'Subscription', 'సబ్‌స్క్రిప్షన్'),
('could_not_load_usage_note', 'Could not load your current usage.\n\n{error}', 'మీ ప్రస్తుత వినియోగం లోడ్ కాలేదు.\n\n{error}'),
('planned_prices_note', 'Nothing is being charged yet. These are the planned prices, shown so you can see which one fits your business.', 'ఇంకా ఏమీ వసూలు చేయడం లేదు. ఇవి ప్రణాళికాబద్ధ ధరలు, మీ వ్యాపారానికి ఏది సరిపోతుందో చూడటానికి చూపబడ్డాయి.'),
('plans', 'Plans', 'ప్లాన్‌లు'),
('customers_and_investors', 'Customers and Investors', 'కస్టమర్లు మరియు పెట్టుబడిదారులు'),
('customers_investors_free_note', 'Customers and Investors view their records free. Requesting a loan, or requesting to invest or withdraw, is ₹99 a year for that role — and one discounted Combo covers a person who is both.', 'కస్టమర్లు మరియు పెట్టుబడిదారులు వారి రికార్డులను ఉచితంగా చూస్తారు. రుణం అభ్యర్థించడం, లేదా పెట్టుబడి/ఉపసంహరణ అభ్యర్థించడం ఆ పాత్రకు సంవత్సరానికి ₹99 — మరియు ఒక రాయితీ కాంబో రెండూ ఉన్న వ్యక్తిని కవర్ చేస్తుంది.'),
('your_business_today', 'Your Business Today', 'ఈ రోజు మీ వ్యాపారం'),
('agents', 'Agents', 'ఏజెంట్లు'),
('customers', 'Customers', 'కస్టమర్లు'),
('investors', 'Investors', 'పెట్టుబడిదారులు'),
('fits_plan_note', 'That fits the {plan} plan.', 'అది {plan} ప్లాన్‌కు సరిపోతుంది.'),
('your_business_fits_here', 'Your business fits here.', 'మీ వ్యాపారం ఇక్కడ సరిపోతుంది.'),
('withdrawal_requests_title', 'Withdrawal Requests', 'ఉపసంహరణ అభ్యర్థనలు'),
('reject_withdrawal_request', 'Reject Withdrawal Request', 'ఉపసంహరణ అభ్యర్థనను తిరస్కరించండి'),
('pay_out_withdrawal', 'Pay Out Withdrawal', 'ఉపసంహరణ చెల్లించండి'),
('requested_amount_type_note', 'Requested: {amount} ({type})', 'అభ్యర్థించినది: {amount} ({type})'),
('principal_portion_field', 'Principal Portion *', 'అసలు భాగం *'),
('interest_portion_field', 'Interest Portion *', 'వడ్డీ భాగం *'),
('total_note', 'Total: {amount}', 'మొత్తం: {amount}'),
('pay_out', 'Pay Out', 'చెల్లించండి'),
('could_not_load_withdrawal_requests_note', 'Could not load withdrawal requests.\n{error}', 'ఉపసంహరణ అభ్యర్థనలు లోడ్ కాలేదు.\n{error}'),
('no_pending_withdrawal_requests', 'No pending withdrawal requests.', 'పెండింగ్ ఉపసంహరణ అభ్యర్థనలు లేవు.')
ON CONFLICT (translation_key) DO NOTHING;

-- Retro-fix keys added earlier in this pass that broke the minor-word rule.
-- `%note%` keys are full sentences, where normal sentence casing already applies.
UPDATE ui_translations SET english = replace(english, ' To ', ' to ') WHERE english LIKE '% To %' AND translation_key NOT LIKE '%note%';
UPDATE ui_translations SET english = replace(english, ' And ', ' and ') WHERE english LIKE '% And %' AND translation_key NOT LIKE '%note%';
UPDATE ui_translations SET english = replace(english, ' Of ', ' of ') WHERE english LIKE '% Of %' AND translation_key NOT LIKE '%note%';
UPDATE ui_translations SET english = replace(english, ' In ', ' in ') WHERE english LIKE '% In %' AND translation_key NOT LIKE '%note%';
UPDATE ui_translations SET english = replace(english, ' For ', ' for ') WHERE english LIKE '% For %' AND translation_key NOT LIKE '%note%';
UPDATE ui_translations SET english = replace(english, ' The ', ' the ') WHERE english LIKE '% The %' AND translation_key NOT LIKE '%note%';
UPDATE ui_translations SET english = replace(english, ' A ', ' a ') WHERE english LIKE '% A %' AND translation_key NOT LIKE '%note%';
UPDATE ui_translations SET english = replace(english, ' An ', ' an ') WHERE english LIKE '% An %' AND translation_key NOT LIKE '%note%';
