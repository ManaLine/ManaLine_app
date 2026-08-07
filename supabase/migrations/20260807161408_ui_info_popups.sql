-- The (i) info-popup glossary feature: double-tap a word to see a plain
-- explanation, OK to dismiss. Same public-read, DB-editable pattern as
-- ui_translations (0047) — editing an explanation is a Table Editor edit,
-- not a code change. Only words with a row here show anything; most words
-- don't need one.
--
-- HONEST NOTE: Telugu is an AI draft, unreviewed by a native speaker —
-- same caveat as every other Telugu column in this app so far.
--
-- Seeded first pass: the genuinely confusing domain/money vocabulary
-- (BR-locked terms from docs/01_Global_Rules_Guide.md and the money
-- conventions in CLAUDE.md), not generic UI chrome like "Cancel" or
-- "Save" — those don't need an explanation.
CREATE TABLE ui_info_popups (
  info_key      TEXT PRIMARY KEY,
  telugu_label  TEXT,
  english_info  TEXT NOT NULL,
  telugu_info   TEXT
);

ALTER TABLE ui_info_popups ENABLE ROW LEVEL SECURITY;

CREATE POLICY ui_info_popups_public_select ON ui_info_popups
  FOR SELECT USING (true);

INSERT INTO ui_info_popups (info_key, telugu_label, english_info, telugu_info) VALUES
('bf', 'BF',
 'Brought Forward — the cash actually in hand, carried over from the previous business day. Only money that really moved counts here.',
 'బ్రాట్ ఫార్వర్డ్ — మునుపటి వ్యాపార దినం నుండి మిగిలిన నగదు. నిజంగా చేతిలో ఉన్న డబ్బు మాత్రమే ఇందులో లెక్కిస్తారు.'),
('cheti', 'చేతి',
 'A Cheti is an asset, not an expense — instalments paid into it come back later as one lump sum, so it always counts as money you still have.',
 'చేతి అనేది ఒక ఆస్తి, ఖర్చు కాదు — అందులో చెల్లించిన వాయిదాలు తర్వాత ఒకేసారి తిరిగి వస్తాయి, కాబట్టి అది ఎప్పుడూ మీ వద్ద ఉన్న సొమ్ముగానే లెక్కించబడుతుంది.'),
('roi', 'ROI',
 'The interest rate here is rupees per ₹100 per month — not a yearly percentage. A ROI of 2 means ₹2 interest per ₹100 borrowed, every month.',
 'ఇక్కడ వడ్డీ రేటు నెలకు ప్రతి ₹100కి రూపాయలలో ఉంటుంది — వార్షిక శాతం కాదు. ROI 2 అంటే ప్రతి నెలా అప్పు తీసుకున్న ప్రతి ₹100కి ₹2 వడ్డీ.'),
('mlid', 'MLID',
 'MANA LINE ID — a person''s permanent ID in this app. Search for anyone, anywhere, using this instead of remembering their name.',
 'మానా లైన్ ఐడి — ఈ యాప్‌లో ఒక వ్యక్తి యొక్క శాశ్వత గుర్తింపు. పేరు గుర్తుంచుకోకుండా దీని ద్వారా ఎవరినైనా ఎక్కడైనా వెతకవచ్చు.'),
('grace_period', 'గ్రేస్ పీరియడ్',
 'Extra days after the due date before an instalment counts as overdue. No penalty applies while a loan is still inside its Grace Period.',
 'వాయిదా గడువు తర్వాత అది మీద పడిన బకాయిగా లెక్కించే ముందు ఇచ్చే అదనపు రోజులు. రుణం గ్రేస్ పీరియడ్‌లో ఉన్నంత వరకు జరిమానా వర్తించదు.'),
('verification_ring', 'వెరిఫికేషన్ రింగ్',
 'The colored ring around a profile photo: green means this person''s identity is verified, red means it is not yet.',
 'ప్రొఫైల్ ఫోటో చుట్టూ ఉన్న రంగు వలయం: ఆకుపచ్చ అంటే ఈ వ్యక్తి గుర్తింపు ధృవీకరించబడింది, ఎరుపు అంటే ఇంకా ధృవీకరించలేదు.'),
('otp', 'OTP',
 'A one-time code sent to a phone number, used to prove that number really belongs to the person entering it.',
 'ఒక ఫోన్ నంబర్‌కు పంపే ఒక్కసారి వాడే కోడ్, ఆ నంబర్ నిజంగా దాన్ని నమోదు చేస్తున్న వ్యక్తిదేనని నిర్ధారించడానికి వాడతారు.'),
('pin', 'పిన్',
 'A short numeric code for signing back in quickly, instead of typing the full password every time.',
 'ప్రతిసారీ పూర్తి పాస్‌వర్డ్ టైప్ చేయకుండా వేగంగా లాగిన్ అవ్వడానికి ఉపయోగించే చిన్న సంఖ్యా కోడ్.'),
('day_closure', 'దిన ముగింపు',
 'The official end-of-day step that locks that day''s figures and opens the next business day. Cannot be undone without an Owner Reopen.',
 'ఆ రోజు లెక్కలను లాక్ చేసి తదుపరి వ్యాపార దినాన్ని తెరిచే అధికారిక దిన ముగింపు అడుగు. యజమాని తిరిగి తెరవందే దీన్ని రద్దు చేయలేరు.'),
('difference', 'తేడా',
 'The gap between what the system expected in cash/UPI/bank and what was actually counted during Day Closure.',
 'దిన ముగింపు సమయంలో నగదు/UPI/బ్యాంక్‌లో సిస్టమ్ ఆశించినదానికి మరియు నిజంగా లెక్కించినదానికి మధ్య ఉన్న తేడా.'),
('amount_given', 'ఇచ్చిన మొత్తం',
 'What actually left the till when the loan was disbursed — the repayment amount minus interest and fee already withheld upfront.',
 'రుణం ఇచ్చినప్పుడు నిజంగా చేతి నుండి వెళ్లిన మొత్తం — ముందుగానే మినహాయించిన వడ్డీ మరియు ఫీజును తీసివేసిన తర్వాత మిగిలిన మొత్తం.'),
('remaining_balance', 'మిగిలిన బ్యాలెన్స్',
 'How much of the repayment amount is still unpaid on this loan.',
 'ఈ రుణంపై తిరిగి చెల్లించాల్సిన మొత్తంలో ఇంకా చెల్లించని మొత్తం ఎంత అనేది.'),
('business_date', 'వ్యాపార తేదీ',
 'The date this activity is recorded against — not always today''s calendar date. A very late-night entry can still belong to yesterday''s business day.',
 'ఈ కార్యకలాపం నమోదు చేయబడిన తేదీ — ఇది ఎల్లప్పుడూ నేటి క్యాలెండర్ తేదీ కాకపోవచ్చు. చాలా అర్ధరాత్రి నమోదు అయినా అది నిన్నటి వ్యాపార దినానికే చెందవచ్చు.'),
('yearly_compound', 'వార్షిక చక్రవడ్డీ',
 'Interest calculated using the actual number of days in the year (365, or 366 in a leap year) — not a flat 360-day approximation.',
 'ఏడాదిలో నిజమైన రోజుల సంఖ్య (365, లీపు సంవత్సరంలో 366) ఆధారంగా లెక్కించే వడ్డీ — 360 రోజుల స్థిర అంచనా కాదు.')
ON CONFLICT (info_key) DO NOTHING;
