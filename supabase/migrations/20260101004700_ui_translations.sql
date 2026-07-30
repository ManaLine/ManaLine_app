-- MANA LINE — 0047_ui_translations.sql
--
-- DB-editable UI translations, per explicit request: editing a word
-- should mean editing a row in Supabase Table Editor, not a code change
-- + redeploy + rebuild cycle. Falls back to English (or the raw key) if
-- a cell is empty, so nothing ever breaks from a missing translation.
--
-- HONEST NOTE: the Telugu/Hindi/Tamil/Kannada values seeded below are
-- AI-generated using standard, common terminology — not reviewed by a
-- native speaker for this specific project's tone or regional dialect
-- preferences. You said you'll refine wording during testing; that's
-- exactly what this table is for. Nothing here is meant to be final.
--
-- SCOPE: first pass covers LR-001 through LR-013 (full login/registration
-- flow) and the 4 workspace home dashboards' top-level labels — not
-- exhaustive coverage of every string in the whole app. Extend by adding
-- more rows + wiring more screens' widgets to use t('new_key').

CREATE TABLE ui_translations (
  translation_key   TEXT PRIMARY KEY,
  english           TEXT NOT NULL,
  telugu            TEXT,
  hindi             TEXT,
  tamil             TEXT,
  kannada           TEXT
);

ALTER TABLE ui_translations ENABLE ROW LEVEL SECURITY;

-- Public read — must work on LR-002 (workspace choice) and LR-003
-- (login/register choice), both reachable before any login exists.
CREATE POLICY ui_translations_public_select ON ui_translations
  FOR SELECT USING (true);

-- No client write policy — edited only via Supabase Table Editor / SQL
-- Editor directly, by you, matching the explicit "I'll do it while
-- testing" requirement. Not meant to be editable in-app.

INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada) VALUES
-- LR-001 / LR-002 (splash, workspace choice)
('app_name', 'MANA LINE', 'మన లైన్', 'माणा लाइन', 'மன லைன்', 'ಮನ ಲೈನ್'),
('choose_workspace', 'Choose Workspace', 'వర్క్‌స్పేస్ ఎంచుకోండి', 'वर्कस्पेस चुनें', 'பணியிடத்தைத் தேர்ந்தெடுக்கவும்', 'ಕಾರ್ಯಸ್ಥಳವನ್ನು ಆಯ್ಕೆಮಾಡಿ'),
('coming_soon', 'Coming Soon', 'త్వరలో వస్తుంది', 'जल्द आ रहा है', 'விரைவில் வருகிறது', 'ಶೀಘ್ರದಲ್ಲೇ ಬರಲಿದೆ'),

-- LR-003 (login/register choice)
('login_or_register_title', 'Get Started', 'ప్రారంభించండి', 'शुरू करें', 'தொடங்குங்கள்', 'ಪ್ರಾರಂಭಿಸಿ'),
('im_new_register', 'I''m new — Register', 'నేను కొత్త — నమోదు చేయండి', 'मैं नया हूँ — पंजीकरण करें', 'நான் புதியவன் — பதிவு செய்யவும்', 'ನಾನು ಹೊಸಬ — ನೋಂದಣಿ ಮಾಡಿ'),
('im_registered_login', 'I''m registered — Login', 'నేను నమోదు చేసుకున్నాను — లాగిన్', 'मैं पंजीकृत हूँ — लॉगिन करें', 'நான் பதிவு செய்துள்ளேன் — உள்நுழையவும்', 'ನಾನು ನೋಂದಾಯಿಸಿದ್ದೇನೆ — ಲಾಗಿನ್'),
('already_registered_q', 'Already registered?', 'ఇప్పటికే నమోదు అయ్యారా?', 'पहले से पंजीकृत हैं?', 'ஏற்கனவே பதிவு செய்துள்ளீர்களா?', 'ಈಗಾಗಲೇ ನೋಂದಾಯಿಸಿದ್ದೀರಾ?'),
('yes_im_registered', 'Yes, I''m registered', 'అవును, నేను నమోదు అయ్యాను', 'हां, मैं पंजीकृत हूं', 'ஆம், நான் பதிவு செய்துள்ளேன்', 'ಹೌದು, ನಾನು ನೋಂದಾಯಿಸಿದ್ದೇನೆ'),
('no_im_new', 'No, I''m new', 'లేదు, నేను కొత్తవాడిని', 'नहीं, मैं नया हूं', 'இல்லை, நான் புதியவன்', 'ಇಲ್ಲ, ನಾನು ಹೊಸಬ'),

-- LR-004 (registration form)
('create_your_account', 'Create Your Account', 'మీ ఖాతాను సృష్టించండి', 'अपना खाता बनाएं', 'உங்கள் கணக்கை உருவாக்கவும்', 'ನಿಮ್ಮ ಖಾತೆಯನ್ನು ರಚಿಸಿ'),
('full_name', 'Full Name', 'పూర్తి పేరు', 'पूरा नाम', 'முழுப் பெயர்', 'ಪೂರ್ಣ ಹೆಸರು'),
('father_husband_name', 'Father / Husband Name', 'తండ్రి / భర్త పేరు', 'पिता / पति का नाम', 'தந்தை / கணவர் பெயர்', 'ತಂದೆ / ಗಂಡನ ಹೆಸರು'),
('gender', 'Gender', 'లింగం', 'लिंग', 'பாலினம்', 'ಲಿಂಗ'),
('mobile_number', 'Mobile Number', 'మొబైల్ నంబర్', 'मोबाइल नंबर', 'மொபைல் எண்', 'ಮೊಬೈಲ್ ಸಂಖ್ಯೆ'),
('password', 'Password', 'పాస్‌వర్డ్', 'पासवर्ड', 'கடவுச்சொல்', 'ಪಾಸ್‌ವರ್ಡ್'),
('confirm_password', 'Confirm Password', 'పాస్‌వర్డ్ నిర్ధారించండి', 'पासवर्ड की पुष्टि करें', 'கடவுச்சொல்லை உறுதிப்படுத்தவும்', 'ಪಾಸ್‌ವರ್ಡ್ ದೃಢೀಕರಿಸಿ'),
('door_house_no', 'Door / House No', 'ఇంటి నంబర్', 'घर नंबर', 'கதவு / வீட்டு எண்', 'ಮನೆ ಸಂಖ್ಯೆ'),
('pin_code', 'PIN Code', 'పిన్ కోడ్', 'पिन कोड', 'பின் குறியீடு', 'ಪಿನ್ ಕೋಡ್'),
('search_village_town', 'Search Village/Town', 'గ్రామం/పట్టణం వెతకండి', 'गांव/शहर खोजें', 'கிராமம்/நகரம் தேடுங்கள்', 'ಗ್ರಾಮ/ಪಟ್ಟಣ ಹುಡುಕಿ'),
('aadhaar_number', 'Aadhaar Number', 'ఆధార్ నంబర్', 'आधार नंबर', 'ஆதார் எண்', 'ಆಧಾರ್ ಸಂಖ್ಯೆ'),
('register_button', 'Register', 'నమోదు చేయండి', 'पंजीकरण करें', 'பதிவு செய்யவும்', 'ನೋಂದಣಿ ಮಾಡಿ'),

-- LR-005 (OTP)
('enter_otp_title', 'Enter the OTP sent to verify your number', 'మీ నంబర్‌ను ధృవీకరించడానికి పంపిన OTP నమోదు చేయండి', 'अपना नंबर सत्यापित करने के लिए भेजा गया OTP दर्ज करें', 'உங்கள் எண்ணை உறுதிப்படுத்த அனுப்பப்பட்ட OTP-ஐ உள்ளிடவும்', 'ನಿಮ್ಮ ಸಂಖ್ಯೆಯನ್ನು ಪರಿಶೀಲಿಸಲು ಕಳುಹಿಸಿದ OTP ನಮೂದಿಸಿ'),
('resend_otp', 'Resend OTP', 'OTP మళ్లీ పంపండి', 'OTP पुनः भेजें', 'OTP-ஐ மீண்டும் அனுப்பவும்', 'OTP ಮರುಕಳುಹಿಸಿ'),
('verify_button', 'Verify', 'ధృవీకరించండి', 'सत्यापित करें', 'சரிபார்க்கவும்', 'ಪರಿಶೀಲಿಸಿ'),

-- LR-007 / LR-009 (login screens)
('login_button', 'Login', 'లాగిన్', 'लॉगिन', 'உள்நுழைய', 'ಲಾಗಿನ್'),
('forgot_pin', 'Forgot PIN?', 'పిన్ మర్చిపోయారా?', 'पिन भूल गए?', 'பின்னை மறந்துவிட்டீர்களா?', 'ಪಿನ್ ಮರೆತಿದ್ದೀರಾ?'),
('forgot_password', 'Forgot Password?', 'పాస్‌వర్డ్ మర్చిపోయారా?', 'पासवर्ड भूल गए?', 'கடவுச்சொல்லை மறந்துவிட்டீர்களா?', 'ಪಾಸ್‌ವರ್ಡ್ ಮರೆತಿದ್ದೀರಾ?'),

-- LR-008 / LR-011 (PIN)
('create_pin', 'Create PIN', 'పిన్ సృష్టించండి', 'पिन बनाएं', 'பின்னை உருவாக்கவும்', 'ಪಿನ್ ರಚಿಸಿ'),
('enter_pin', 'Enter PIN', 'పిన్ నమోదు చేయండి', 'पिन दर्ज करें', 'பின்னை உள்ளிடவும்', 'ಪಿನ್ ನಮೂದಿಸಿ'),

-- LR-012 (business selector)
('select_business', 'Select Business', 'వ్యాపారాన్ని ఎంచుకోండి', 'व्यवसाय चुनें', 'வணிகத்தைத் தேர்ந்தெடுக்கவும்', 'ವ್ಯಾಪಾರವನ್ನು ಆಯ್ಕೆಮಾಡಿ'),
('no_business_linked', 'No Business Linked', 'ఏ వ్యాపారం లింక్ చేయబడలేదు', 'कोई व्यवसाय लिंक नहीं है', 'எந்த வணிகமும் இணைக்கப்படவில்லை', 'ಯಾವುದೇ ವ್ಯಾಪಾರ ಲಿಂಕ್ ಆಗಿಲ್ಲ'),
('create_new_business', 'Create New Business', 'కొత్త వ్యాపారాన్ని సృష్టించండి', 'नया व्यवसाय बनाएं', 'புதிய வணிகத்தை உருவாக்கவும்', 'ಹೊಸ ವ್ಯಾಪಾರ ರಚಿಸಿ'),
('contact_owner', 'Contact Owner', 'యజమానిని సంప్రదించండి', 'मालिक से संपर्क करें', 'உரிமையாளரைத் தொடர்பு கொள்ளவும்', 'ಮಾಲೀಕರನ್ನು ಸಂಪರ್ಕಿಸಿ'),
('pending_requests', 'Pending Requests', 'పెండింగ్‌లో ఉన్న అభ్యర్థనలు', 'लंबित अनुरोध', 'நிலுவையிலுள்ள கோரிக்கைகள்', 'ಬಾಕಿ ಇರುವ ವಿನಂತಿಗಳು'),
('accept', 'Accept', 'అంగీకరించండి', 'स्वीकार करें', 'ஏற்கவும்', 'ಸ್ವೀಕರಿಸಿ'),
('decline', 'Decline', 'తిరస్కరించండి', 'अस्वीकार करें', 'நிராகரிக்கவும்', 'ನಿರಾಕರಿಸಿ'),
('request_join_business', 'Request to Join a Business', 'వ్యాపారంలో చేరడానికి అభ్యర్థించండి', 'व्यवसाय में शामिल होने का अनुरोध करें', 'ஒரு வணிகத்தில் சேர கோரிக்கை', 'ವ್ಯಾಪಾರಕ್ಕೆ ಸೇರಲು ವಿನಂತಿಸಿ'),

-- LR-013 (role selector)
('select_role', 'Select Role', 'పాత్రను ఎంచుకోండి', 'भूमिका चुनें', 'பங்கைத் தேர்ந்தெடுக்கவும்', 'ಪಾತ್ರವನ್ನು ಆಯ್ಕೆಮಾಡಿ'),

-- Common actions used across many screens
('logout', 'Logout', 'లాగ్ అవుట్', 'लॉगआउट', 'வெளியேறு', 'ಲಾಗ್ ಔಟ್'),
('cancel', 'Cancel', 'రద్దు చేయండి', 'रद्द करें', 'ரத்து செய்', 'ರದ್ದುಗೊಳಿಸಿ'),
('save', 'Save', 'సేవ్ చేయండి', 'सहेजें', 'சேமி', 'ಉಳಿಸಿ'),
('continue_button', 'Continue', 'కొనసాగించండి', 'जारी रखें', 'தொடரவும்', 'ಮುಂದುವರಿಸಿ'),
('back', 'Back', 'వెనుకకు', 'वापस', 'பின்செல்', 'ಹಿಂದೆ'),

-- Workspace home dashboards (top-level labels)
('home', 'Home', 'హోమ్', 'होम', 'முகப்பு', 'ಮುಖಪುಟ'),
('customers', 'Customers', 'కస్టమర్లు', 'ग्राहक', 'வாடிக்கையாளர்கள்', 'ಗ್ರಾಹಕರು'),
('collections', 'Collections', 'వసూళ్లు', 'संग्रह', 'வசூல்', 'ಸಂಗ್ರಹಣೆಗಳು'),
('history', 'History', 'చరిత్ర', 'इतिहास', 'வரலாறு', 'ಇತಿಹಾಸ'),
('settings', 'Settings', 'సెట్టింగ్‌లు', 'सेटिंग्स', 'அமைப்புகள்', 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು'),
('profile', 'Profile', 'ప్రొఫైల్', 'प्रोफ़ाइल', 'சுயவிவரம்', 'ಪ್ರೊಫೈಲ್'),
('switch_workspace', 'Switch Workspace', 'వర్క్‌స్పేస్ మార్చండి', 'वर्कस्पेस बदलें', 'பணியிடத்தை மாற்று', 'ಕಾರ್ಯಸ್ಥಳ ಬದಲಿಸಿ'),
('switch_role', 'Switch Role', 'పాత్ర మార్చండి', 'भूमिका बदलें', 'பங்கை மாற்று', 'ಪಾತ್ರ ಬದಲಿಸಿ'),
('todays_business_summary', 'Today''s Business Summary', 'నేటి వ్యాపార సారాంశం', 'आज का व्यापार सारांश', 'இன்றைய வணிக சுருக்கம்', 'ಇಂದಿನ ವ್ಯಾಪಾರ ಸಾರಾಂಶ'),
('quick_actions', 'Quick Actions', 'త్వరిత చర్యలు', 'त्वरित कार्य', 'விரைவு செயல்கள்', 'ತ್ವರಿತ ಕ್ರಿಯೆಗಳು'),
('my_investments', 'My Investments', 'నా పెట్టుబడులు', 'मेरे निवेश', 'எனது முதலீடுகள்', 'ನನ್ನ ಹೂಡಿಕೆಗಳು'),
('my_loans', 'My Loans', 'నా రుణాలు', 'मेरे ऋण', 'எனது கடன்கள்', 'ನನ್ನ ಸಾಲಗಳು'),
('find_a_business', 'Find A Business', 'వ్యాపారాన్ని కనుగొనండి', 'व्यवसाय खोजें', 'வணிகத்தைக் கண்டறியவும்', 'ವ್ಯಾಪಾರವನ್ನು ಹುಡುಕಿ');
