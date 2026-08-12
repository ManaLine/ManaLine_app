-- Translation keys for the rebuilt transaction history (OW-017, AG-010) and
-- the statement export. Real translations in all five languages, per the
-- standing convention — a key that falls back to English on four of five
-- screens is not wired, it is half-wired.
--
-- {count} placeholders are substituted client-side and must survive
-- translation intact. Verified after applying: 38 keys, 0 with a missing
-- language, 0 that lost a placeholder.
INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada) VALUES
  ('my_statements',        'My Statements',        'నా స్టేట్‌మెంట్‌లు',       'मेरे स्टेटमेंट',        'என் அறிக்கைகள்',        'ನನ್ನ ಹೇಳಿಕೆಗಳು'),
  ('search_transactions',  'Search Transactions',  'లావాదేవీలను వెతకండి',   'लेन-देन खोजें',        'பரிவர்த்தனைகளைத் தேடு', 'ವಹಿವಾಟುಗಳನ್ನು ಹುಡುಕಿ'),
  ('filters',              'Filters',              'ఫిల్టర్లు',                'फ़िल्टर',              'வடிகட்டிகள்',            'ಫಿಲ್ಟರ್‌ಗಳು'),
  ('apply',                'Apply',                'వర్తింపజేయండి',          'लागू करें',            'பயன்படுத்து',           'ಅನ್ವಯಿಸಿ'),
  ('categories',           'Categories',           'వర్గాలు',                 'श्रेणियाँ',             'வகைகள்',                'ವರ್ಗಗಳು'),
  ('date_range',           'Date Range',           'తేదీ పరిధి',              'तिथि सीमा',            'தேதி வரம்பு',           'ದಿನಾಂಕ ವ್ಯಾಪ್ತಿ'),
  ('all_dates',            'All Dates',            'అన్ని తేదీలు',            'सभी तिथियाँ',          'அனைத்து தேதிகள்',       'ಎಲ್ಲಾ ದಿನಾಂಕಗಳು'),
  ('day_net',              'Day Net',              'రోజు నికర',              'दिन का शुद्ध',         'நாள் நிகர',              'ದಿನದ ನಿವ್ವಳ'),
  ('money_received',       'Money Received',       'అందిన డబ్బు',            'प्राप्त धन',           'பெறப்பட்ட பணம்',        'ಸ್ವೀಕರಿಸಿದ ಹಣ'),
  ('money_spent',          'Money Spent',          'ఖర్చు చేసిన డబ్బు',       'खर्च किया धन',         'செலவழித்த பணம்',        'ಖರ್ಚು ಮಾಡಿದ ಹಣ'),
  ('collection_from',      'Collection From',      'వసూలు నుండి',            'वसूली से',             'வசூல் இவரிடமிருந்து',   'ಸಂಗ್ರಹ ಇವರಿಂದ'),
  ('loan_to',              'Loan To',              'రుణం ఇచ్చినది',          'ऋण दिया',              'கடன் வழங்கியது',        'ಸಾಲ ನೀಡಿದ್ದು'),
  ('expense_paid',         'Expense Paid',         'చెల్లించిన ఖర్చు',        'भुगतान किया खर्च',     'செலுத்திய செலவு',       'ಪಾವತಿಸಿದ ಖರ್ಚು'),
  ('deposit_from',         'Deposit From',         'జమ చేసినవారు',           'जमा किया',             'வைப்பு இவரிடமிருந்து',  'ಠೇವಣಿ ಇವರಿಂದ'),
  ('withdrawal_to',        'Withdrawal To',        'ఉపసంహరణ ఇచ్చినది',      'निकासी दी',            'திரும்பப் பெறுதல்',      'ಹಿಂಪಡೆಯುವಿಕೆ'),
  ('cheti_instalment_paid','Cheti Instalment Paid','చీటీ వాయిదా చెల్లింపు',   'चिटी किस्त भुगतान',    'சீட்டு தவணை செலுத்தப்பட்டது', 'ಚೀಟಿ ಕಂತು ಪಾವತಿ'),
  ('cheti_amount_availed', 'Cheti Amount Availed', 'చీటీ మొత్తం పొందారు',    'चिटी राशि प्राप्त',    'சீட்டுத் தொகை பெறப்பட்டது', 'ಚೀಟಿ ಮೊತ್ತ ಪಡೆದಿದೆ'),
  ('cheti_paid_label',     'Cheti Paid',           'చీటీ చెల్లింపు',          'चिटी भुगतान',          'சீட்டு செலுத்தியது',     'ಚೀಟಿ ಪಾವತಿ'),
  ('cheti_received_label', 'Cheti Received',       'చీటీ అందినది',           'चिटी प्राप्त',         'சீட்டு பெறப்பட்டது',     'ಚೀಟಿ ಸ್ವೀಕೃತ'),
  ('settlement_short',     'Settlement Short',     'సెటిల్‌మెంట్ తక్కువ',     'निपटान कम',            'தீர்வு குறைவு',          'ಇತ್ಯರ್ಥ ಕೊರತೆ'),
  ('settlement_excess',    'Settlement Excess',    'సెటిల్‌మెంట్ అధికం',      'निपटान अधिक',          'தீர்வு அதிகம்',          'ಇತ್ಯರ್ಥ ಹೆಚ್ಚುವರಿ'),
  ('could_not_load_history','Could Not Load History','చరిత్రను లోడ్ చేయలేకపోయాం','इतिहास लोड नहीं हो सका','வரலாற்றை ஏற்ற முடியவில்லை','ಇತಿಹಾಸ ಲೋಡ್ ಆಗಲಿಲ್ಲ'),
  ('no_transactions_match_filters','No Transactions Match These Filters','ఈ ఫిల్టర్లకు సరిపోయే లావాదేవీలు లేవు','इन फ़िल्टरों से मेल खाते लेन-देन नहीं','இந்த வடிகட்டிகளுக்கு பரிவர்த்தனைகள் இல்லை','ಈ ಫಿಲ್ಟರ್‌ಗಳಿಗೆ ಹೊಂದುವ ವಹಿವಾಟುಗಳಿಲ್ಲ'),
  ('month_totals_from_ledger_note','These totals come from the day ledger, not from the rows listed above.','ఈ మొత్తాలు పైన ఉన్న వరుసల నుండి కాదు, రోజు లెడ్జర్ నుండి వచ్చాయి.','ये कुल ऊपर दी गई पंक्तियों से नहीं, दिन के लेजर से आते हैं।','இந்தத் தொகைகள் மேலே உள்ள வரிசைகளிலிருந்து அல்ல, நாள் லெட்ஜரிலிருந்து வருகின்றன.','ಈ ಮೊತ್ತಗಳು ಮೇಲಿನ ಸಾಲುಗಳಿಂದಲ್ಲ, ದಿನದ ಲೆಡ್ಜರ್‌ನಿಂದ ಬರುತ್ತವೆ.'),
  ('your_activity_only_note','Your own activity on this business. Not the full business history.','ఈ వ్యాపారంలో మీ స్వంత కార్యకలాపాలు మాత్రమే. పూర్తి వ్యాపార చరిత్ర కాదు.','इस व्यवसाय पर आपकी अपनी गतिविधि। पूरा व्यवसाय इतिहास नहीं।','இந்த வணிகத்தில் உங்கள் சொந்த செயல்பாடு மட்டும். முழு வணிக வரலாறு அல்ல.','ಈ ವ್ಯವಹಾರದಲ್ಲಿ ನಿಮ್ಮ ಸ್ವಂತ ಚಟುವಟಿಕೆ ಮಾತ್ರ. ಪೂರ್ಣ ವ್ಯವಹಾರ ಇತಿಹಾಸವಲ್ಲ.'),
  ('you_collected',        'You Collected',        'మీరు వసూలు చేసినది',     'आपने वसूला',           'நீங்கள் வசூலித்தது',     'ನೀವು ಸಂಗ್ರಹಿಸಿದ್ದು'),
  ('date',                 'Date',                 'తేదీ',                    'तिथि',                 'தேதி',                   'ದಿನಾಂಕ'),
  ('time',                 'Time',                 'సమయం',                   'समय',                  'நேரம்',                  'ಸಮಯ'),
  ('reference',            'Reference',            'సూచన',                   'संदर्भ',               'குறிப்பு',               'ಉಲ್ಲೇಖ'),
  ('details',              'Details',              'వివరాలు',                 'विवरण',                'விவரங்கள்',              'ವಿವರಗಳು'),
  ('statement_period',     'Statement Period',     'స్టేట్‌మెంట్ కాలం',        'स्टेटमेंट अवधि',       'அறிக்கை காலம்',          'ಹೇಳಿಕೆ ಅವಧಿ'),
  ('range',                'Range',                'పరిధి',                   'सीमा',                 'வரம்பு',                 'ವ್ಯಾಪ್ತಿ'),
  ('financial_year',       'Financial Year',       'ఆర్థిక సంవత్సరం',         'वित्तीय वर्ष',         'நிதியாண்டு',             'ಆರ್ಥಿಕ ವರ್ಷ'),
  ('last_n_days',          'Last {count} Days',    'గత {count} రోజులు',       'पिछले {count} दिन',    'கடந்த {count} நாட்கள்',  'ಕಳೆದ {count} ದಿನಗಳು'),
  ('download_statement',   'Download Statement',   'స్టేట్‌మెంట్ డౌన్‌లోడ్ చేయండి','स्टेटमेंट डाउनलोड करें','அறிக்கையைப் பதிவிறக்கு','ಹೇಳಿಕೆ ಡೌನ್‌ಲೋಡ್ ಮಾಡಿ'),
  ('statement_excel_note', 'The statement downloads as an Excel file you can share.','స్టేట్‌మెంట్ మీరు షేర్ చేయగల ఎక్సెల్ ఫైల్‌గా డౌన్‌లోడ్ అవుతుంది.','स्टेटमेंट एक्सेल फ़ाइल के रूप में डाउनलोड होगा जिसे आप साझा कर सकते हैं।','அறிக்கை நீங்கள் பகிரக்கூடிய எக்செல் கோப்பாகப் பதிவிறங்கும்.','ಹೇಳಿಕೆಯು ನೀವು ಹಂಚಬಹುದಾದ ಎಕ್ಸೆಲ್ ಫೈಲ್ ಆಗಿ ಡೌನ್‌ಲೋಡ್ ಆಗುತ್ತದೆ.'),
  ('statement_has_no_transactions','No transactions in this period.','ఈ కాలంలో లావాదేవీలు లేవు.','इस अवधि में कोई लेन-देन नहीं।','இந்தக் காலத்தில் பரிவர்த்தனைகள் இல்லை.','ಈ ಅವಧಿಯಲ್ಲಿ ಯಾವುದೇ ವಹಿವಾಟುಗಳಿಲ್ಲ.'),
  ('statement_truncated_note','Statement capped at {count} rows. Narrow the period for a complete file.','స్టేట్‌మెంట్ {count} వరుసలకు పరిమితం. పూర్తి ఫైల్ కోసం కాలాన్ని తగ్గించండి.','स्टेटमेंट {count} पंक्तियों तक सीमित। पूरी फ़ाइल के लिए अवधि कम करें।','அறிக்கை {count} வரிசைகளுக்கு வரம்பிடப்பட்டது. முழுக் கோப்புக்குக் காலத்தைக் குறைக்கவும்.','ಹೇಳಿಕೆ {count} ಸಾಲುಗಳಿಗೆ ಸೀಮಿತ. ಪೂರ್ಣ ಫೈಲ್‌ಗಾಗಿ ಅವಧಿಯನ್ನು ಕಡಿಮೆ ಮಾಡಿ.')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english,
  telugu  = EXCLUDED.telugu,
  hindi   = EXCLUDED.hindi,
  tamil   = EXCLUDED.tamil,
  kannada = EXCLUDED.kannada;
