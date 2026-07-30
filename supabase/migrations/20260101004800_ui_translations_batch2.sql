-- MANA LINE — 0048_ui_translations_batch2.sql
-- Additional keys for LR-005, 007-011, 013, and the 4 workspace homes.
-- Separate migration from 0047 (which may already be applied) — same
-- table, just more rows.

INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada) VALUES
-- LR-008 (Create PIN)
('use_alt_pin_digit', 'Use {n}-digit PIN instead', '{n}-అంకెల పిన్ ఉపయోగించండి', '{n}-अंकों का पिन उपयोग करें', '{n}-இலக்க பின்னைப் பயன்படுத்தவும்', '{n}-ಅಂಕಿಯ ಪಿನ್ ಬಳಸಿ'),
('enable_biometric_q', 'Enable biometric login?', 'బయోమెట్రిక్ లాగిన్ ప్రారంభించాలా?', 'बायोमेट्रिक लॉगिन सक्षम करें?', 'பயோமெட்ரிக் உள்நுழைவை இயக்கவா?', 'ಬಯೋಮೆಟ್ರಿಕ್ ಲಾಗಿನ್ ಸಕ್ರಿಯಗೊಳಿಸುವುದೇ?'),
('yes_enable', 'Yes, Enable', 'అవును, ప్రారంభించండి', 'हां, सक्षम करें', 'ஆம், இயக்கு', 'ಹೌದು, ಸಕ್ರಿಯಗೊಳಿಸಿ'),
('not_now', 'Not Now', 'ఇప్పుడు కాదు', 'अभी नहीं', 'இப்போது வேண்டாம்', 'ಈಗ ಬೇಡ'),

-- LR-009 (Daily Login)
('login_with_password', 'Login with Password', 'పాస్‌వర్డ్‌తో లాగిన్ చేయండి', 'पासवर्ड से लॉगिन करें', 'கடவுச்சொல்லுடன் உள்நுழையவும்', 'ಪಾಸ್‌ವರ್ಡ್‌ನೊಂದಿಗೆ ಲಾಗಿನ್'),

-- LR-010 (Forgot Password)
('forgot_password_title', 'Forgot Password', 'పాస్‌వర్డ్ మర్చిపోయారు', 'पासवर्ड भूल गए', 'கடவுச்சொல்லை மறந்துவிட்டீர்கள்', 'ಪಾಸ್‌ವರ್ಡ್ ಮರೆತಿದ್ದೀರಿ'),
('send_otp', 'Send OTP', 'OTP పంపండి', 'OTP भेजें', 'OTP அனுப்பவும்', 'OTP ಕಳುಹಿಸಿ'),
('max_resend_attempts', 'Maximum resend attempts reached', 'గరిష్ట పునఃపంపే ప్రయత్నాలు చేరుకున్నాయి', 'अधिकतम पुनः भेजने के प्रयास पूरे हुए', 'அதிகபட்ச மறு அனுப்பும் முயற்சிகள் எட்டப்பட்டது', 'ಗರಿಷ್ಠ ಮರುಕಳುಹಿಸುವಿಕೆ ಪ್ರಯತ್ನಗಳು ತಲುಪಿದೆ'),
('reset_password', 'Reset Password', 'పాస్‌వర్డ్ రీసెట్ చేయండి', 'पासवर्ड रीसेट करें', 'கடவுச்சொல்லை மீட்டமைக்கவும்', 'ಪಾಸ್‌ವರ್ಡ್ ಮರುಹೊಂದಿಸಿ'),

-- LR-011 (Forgot PIN)
('forgot_pin_title', 'Forgot PIN', 'పిన్ మర్చిపోయారు', 'पिन भूल गए', 'பின்னை மறந்துவிட்டீர்கள்', 'ಪಿನ್ ಮರೆತಿದ್ದೀರಿ'),
('verify_password', 'Verify Password', 'పాస్‌వర్డ్ ధృవీకరించండి', 'पासवर्ड सत्यापित करें', 'கடவுச்சொல்லைச் சரிபார்க்கவும்', 'ಪಾಸ್‌ವರ್ಡ್ ಪರಿಶೀಲಿಸಿ'),

-- Workspace homes — additional labels
('todays_collections', 'Today''s Collections', 'నేటి వసూళ్లు', 'आज का संग्रह', 'இன்றைய வசூல்', 'ಇಂದಿನ ಸಂಗ್ರಹಣೆ'),
('todays_loan_distribution', 'Today''s Loan Distribution', 'నేటి రుణ పంపిణీ', 'आज का ऋण वितरण', 'இன்றைய கடன் விநியோகம்', 'ಇಂದಿನ ಸಾಲ ವಿತರಣೆ'),
('opening_balance', 'Opening Balance', 'ప్రారంభ నిల్వ', 'प्रारंभिक शेष', 'தொடக்க இருப்பு', 'ಆರಂಭಿಕ ಬಾಕಿ'),
('closing_balance', 'Live Closing Balance', 'ప్రస్తుత ముగింపు నిల్వ', 'वर्तमान समापन शेष', 'நேரடி இறுதி இருப்பு', 'ಲೈವ್ ಮುಕ್ತಾಯ ಬಾಕಿ'),
('workforce_management', 'Workforce Management', 'శ్రామిక నిర్వహణ', 'कार्यबल प्रबंधन', 'பணியாளர் மேலாண்மை', 'ಕಾರ್ಮಿಕ ನಿರ್ವಹಣೆ'),
('investor_management', 'Investor Management', 'పెట్టుబడిదారుల నిర్వహణ', 'निवेशक प्रबंधन', 'முதலீட்டாளர் மேலாண்மை', 'ಹೂಡಿಕೆದಾರರ ನಿರ್ವಹಣೆ'),
('customer_management', 'Customer Management', 'కస్టమర్ నిర్వహణ', 'ग्राहक प्रबंधन', 'வாடிக்கையாளர் மேலாண்மை', 'ಗ್ರಾಹಕ ನಿರ್ವಹಣೆ'),
('business_management', 'Business Management', 'వ్యాపార నిర్వహణ', 'व्यवसाय प्रबंधन', 'வணிக மேலாண்மை', 'ವ್ಯಾಪಾರ ನಿರ್ವಹಣೆ'),
('report_hub', 'Report Hub', 'నివేదిక కేంద్రం', 'रिपोर्ट हब', 'அறிக்கை மையம்', 'ವರದಿ ಕೇಂದ್ರ'),
('active', 'Active', 'యాక్టివ్', 'सक्रिय', 'செயலில்', 'ಸಕ್ರಿಯ'),
('pending_invitation', 'Pending Invitation', 'పెండింగ్ ఆహ్వానం', 'लंबित निमंत्रण', 'நிலுவையிலுள்ள அழைப்பு', 'ಬಾಕಿ ಆಹ್ವಾನ'),
('collection_mode', 'Collection Mode', 'వసూలు మోడ్', 'संग्रह मोड', 'வசூல் முறை', 'ಸಂಗ್ರಹಣಾ ಮೋಡ್'),
('request_new_loan', 'Request New Loan', 'కొత్త రుణం అభ్యర్థించండి', 'नया ऋण अनुरोध करें', 'புதிய கடன் கோரவும்', 'ಹೊಸ ಸಾಲ ವಿನಂತಿಸಿ'),
('make_a_payment', 'Make A Payment', 'చెల్లింపు చేయండి', 'भुगतान करें', 'கட்டணம் செலுத்தவும்', 'ಪಾವತಿ ಮಾಡಿ'),
('my_profile_memberships', 'My Profile / Memberships', 'నా ప్రొఫైల్ / సభ్యత్వాలు', 'मेरी प्रोफ़ाइल / सदस्यताएं', 'எனது சுயவிவரம் / உறுப்பினர்', 'ನನ್ನ ಪ್ರೊಫೈಲ್ / ಸದಸ್ಯತ್ವಗಳು'),
('request_withdrawal', 'Request Withdrawal', 'ఉపసంహరణ అభ్యర్థించండి', 'निकासी अनुरोध करें', 'திரும்பப் பெறக் கோரவும்', 'ಹಿಂಪಡೆಯುವಿಕೆ ವಿನಂತಿಸಿ'),
('agent_dashboard', 'Agent Dashboard', 'ఏజెంట్ డాష్‌బోర్డ్', 'एजेंट डैशबोर्ड', 'முகவர் டாஷ்போர்டு', 'ಏಜೆಂಟ್ ಡ್ಯಾಶ್‌ಬೋರ್ಡ್'),
('customer_dashboard', 'Customer Dashboard', 'కస్టమర్ డాష్‌బోర్డ్', 'ग्राहक डैशबोर्ड', 'வாடிக்கையாளர் டாஷ்போர்டு', 'ಗ್ರಾಹಕ ಡ್ಯಾಶ್‌ಬೋರ್ಡ್'),
('investor_dashboard', 'Investor Dashboard', 'పెట్టుబడిదారు డాష్‌బోర్డ్', 'निवेशक डैशबोर्ड', 'முதலீட்டாளர் டாஷ்போர்டு', 'ಹೂಡಿಕೆದಾರ ಡ್ಯಾಶ್‌ಬೋರ್ಡ್')
ON CONFLICT (translation_key) DO NOTHING;
