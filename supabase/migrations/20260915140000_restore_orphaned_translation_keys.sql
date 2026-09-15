-- Forty translation keys that exist in production and in no migration file.
--
-- Task 9 of docs/superpowers/plans/2026-09-15-production-readiness.md found
-- 42 applied migrations with no local file. Seventeen were the same migration
-- under a second name and were renamed; twenty-five were restored from the
-- ledger. Twenty-two hand-named pre-apply drafts were then deleted as exact
-- duplicates of their ledger-stamped twins -- and nineteen translation keys
-- lived ONLY in those drafts, alongside twenty-one already carried on
-- `_appliedButFileMissing` in test/translation_keys_exist_test.dart.
--
-- Forty keys, then, that the app looks up and that no migration creates. On an
-- empty database every one of them renders as a raw key -- `day_closing`,
-- `balance`, `collect` -- which is precisely the failure
-- language_completeness_guard_test.dart exists to prevent, arriving by a
-- different door.
--
-- The English and Telugu here were read out of production with string_agg and
-- quote_literal and written to this file by psql. Nothing was retyped: Telugu
-- passing through a hand is a corruption nobody in the office can proofread.
--
-- ON CONFLICT DO NOTHING because production already holds all forty; this
-- migration is for the rebuild, not for production, where it is a no-op.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('accept_privacy_policy', 'Accept Privacy Policy *', 'గోప్యతా విధానం అంగీకరించండి *'),
('accept_terms_conditions', 'Accept Terms & Conditions *', 'నిబంధనలు & షరతులు అంగీకరించండి *'),
('admin_panel', 'Admin Panel', 'అడ్మిన్ ప్యానెల్'),
('agent_asked_you_to_check_bf', 'An Agent Says Their Opening BF Is Wrong', 'ఏజెంట్ తన ఓపెనింగ్ BF తప్పు అంటున్నారు'),
('allow', 'Allow', 'అనుమతించండి'),
('are_you_absolutely_sure', 'Are You Absolutely Sure?', 'మీరు ఖచ్చితంగా నిర్ధారించారా?'),
('balance', 'Balance', 'బ్యాలెన్స్'),
('carried_forward', 'Carried Forward', 'తదుపరికి నిల్వ'),
('change_user', 'Change User', 'వినియోగదారుని మార్చండి'),
('collect', 'Collect', 'వసూలు'),
('customers_investors_free_note', 'Customers and Investors view their records free. Requesting a loan, or requesting to invest or withdraw, is ₹99 a year for that role — and one discounted Combo covers a person who is both.', 'కస్టమర్లు మరియు పెట్టుబడిదారులు వారి రికార్డులను ఉచితంగా చూస్తారు. రుణం అభ్యర్థించడం, లేదా పెట్టుబడి/ఉపసంహరణ అభ్యర్థించడం ఆ పాత్రకు సంవత్సరానికి ₹99 — మరియు ఒక రాయితీ కాంబో రెండూ ఉన్న వ్యక్తిని కవర్ చేస్తుంది.'),
('day_closing', 'Closing', 'ముగింపు'),
('emi', 'EMI', 'ఈఎంఐ'),
('existing_customers_only', 'Existing Customers Only', 'ఇప్పటికే ఉన్న ఖాతాదారులకు మాత్రమే'),
('existing_customers_only_off_note', 'Anyone found by search may be given a loan. New borrowers are added to this book as the loan is issued.', 'శోధనలో దొరికిన ఎవరికైనా రుణం ఇవ్వవచ్చు. కొత్త వారిని రుణం ఇచ్చేటప్పుడే ఈ పుస్తకంలో చేరుస్తారు.'),
('existing_customers_only_on_note', 'A loan may only be issued to somebody already on this book.', 'ఈ పుస్తకంలో ఇప్పటికే ఉన్న వ్యక్తికి మాత్రమే రుణం ఇవ్వగలరు.'),
('export_to_excel_note', 'Creates a spreadsheet of your customers, loans, collections, expenses, investments and daily ledger. Deleted records are not included.', 'మీ కస్టమర్లు, రుణాలు, వసూళ్లు, ఖర్చులు, పెట్టుబడులు మరియు రోజువారీ లెడ్జర్ యొక్క స్ప్రెడ్‌షీట్ సృష్టిస్తుంది. తొలగించిన రికార్డులు చేర్చబడవు.'),
('import_records_note', 'Enter loans your business already had before it came onto MANA LINE. If any row is wrong, nothing is imported — fix the sheet and upload it again.', 'మానా లైన్‌కు రాకముందే మీ వ్యాపారంలో ఉన్న రుణాలను నమోదు చేయండి. ఏదైనా వరుస తప్పు అయితే, ఏదీ దిగుమతి కాదు — షీట్ సరిచేసి మళ్లీ అప్‌లోడ్ చేయండి.'),
('lending_rules', 'Lending Rules', 'రుణ నియమాలు'),
('less_than_the_instalment', 'Less Than The Instalment', 'వాయిదా కంటే తక్కువ'),
('loans_imported_note', '{count} loans imported.', '{count} రుణాలు దిగుమతి చేయబడ్డాయి.'),
('mana_chits_coming_soon', 'MANA Cheeti — coming soon — version 2', 'మానా చీటీ — త్వరలో — వెర్షన్ 2'),
('more_than_the_instalment', 'More Than The Instalment', 'వాయిదా కంటే ఎక్కువ'),
('no_business_linked_note', 'You''re not yet linked to a business. Create a new one, or contact the Owner if you''re expecting an existing invitation.', 'మీరు ఇంకా ఏ వ్యాపారంతో లింక్ కాలేదు. కొత్తది సృష్టించండి, లేదా ఇప్పటికే ఉన్న ఆహ్వానం ఆశిస్తుంటే యజమానిని సంప్రదించండి.'),
('no_collection', 'Didn''t Collect', 'వసూలు కాలేదు'),
('nothing_collected', 'Nothing Collected', 'ఏమీ వసూలు కాలేదు'),
('nothing_imported_note', 'Nothing was imported. {count} rows need fixing:', 'ఏదీ దిగుమతి కాలేదు. {count} వరుసలు సరిచేయాలి:'),
('paid_the_full_instalment', 'Paid The Full Instalment', 'పూర్తి వాయిదా చెల్లించారు'),
('payment', 'Payment', 'చెల్లింపు'),
('penalty_adds_to_balance_note', 'A penalty is added to what the customer owes.', 'జరిమానా ఖాతాదారు బాకీకి కలుపబడుతుంది.'),
('planned_prices_note', 'Nothing is being charged yet. These are the planned prices, shown so you can see which one fits your business.', 'ఇంకా ఏమీ వసూలు చేయడం లేదు. ఇవి ప్రణాళికాబద్ధ ధరలు, మీ వ్యాపారానికి ఏది సరిపోతుందో చూడటానికి చూపబడ్డాయి.'),
('register', 'Register', 'నమోదు చేయండి'),
('rows_ready_to_import', '{count} rows ready to import', '{count} వరుసలు దిగుమతికి సిద్ధం'),
('sorted_by', 'Sorted By', 'క్రమం'),
('tap_to_open', 'Tap To Open', 'తెరవడానికి నొక్కండి'),
('tap_to_open_their_record', 'Tap To Open Their Record And Fix It', 'వారి రికార్డు తెరిచి సరిచేయడానికి నొక్కండి'),
('transfer_business_note', 'They have to accept before anything moves. Settle your own agent cash and review any waiting settlements first.', 'ఏదైనా కదిలే ముందు వారు అంగీకరించాలి. ముందుగా మీ స్వంత ఏజెంట్ నగదును సెటిల్ చేసి, వేచి ఉన్న సెటిల్‌మెంట్లను సమీక్షించండి.'),
('truncated_sheets_note', 'Some sheets were too large and were cut to {rows} rows: {sheets}. This backup is incomplete.', 'కొన్ని షీట్‌లు చాలా పెద్దవి కావడంతో {rows} వరుసలకు కత్తిరించబడ్డాయి: {sheets}. ఈ బ్యాకప్ అసంపూర్ణం.'),
('use_other_pin_length', 'Use {digits}-digit PIN instead', 'బదులుగా {digits}-అంకెల పిన్ ఉపయోగించండి'),
('use_your_location_question', 'Use Your Location?', 'మీ స్థానాన్ని ఉపయోగించాలా?')
ON CONFLICT (translation_key) DO NOTHING;
