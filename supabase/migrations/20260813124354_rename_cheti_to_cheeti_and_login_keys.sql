-- =============================================================================
-- "Cheti" -> "Cheeti" in the UI, plus the new login/workspace keys
-- =============================================================================
-- The product is spelled Cheeti. The app said "Cheti" in fifteen English
-- strings and "MANA Chits" on the workspace chooser — three spellings for one
-- thing, one tap apart.
--
-- ENGLISH ONLY here. The Telugu/Hindi/Tamil/Kannada values are in native
-- script and already render the sound; "Cheeti" is a romanisation choice, not
-- a translation of one. (Telugu is normalised separately in
-- 20260813134721, after the Owner confirmed చీటీ is the correct form.)
--
-- The DATABASE keeps `cheti`: tables chetis/cheti_payments, the cheti_* enums,
-- day_ledger.cheti_paid/cheti_received, and app.ledger_history's event types.
-- Renaming those for a spelling change would touch the ledger and the history
-- feed for no user-visible gain.
UPDATE ui_translations
SET english = replace(replace(replace(english, 'Chits', 'Cheeti'), 'Cheti', 'Cheeti'), 'cheti', 'cheeti')
WHERE english ILIKE '%cheti%' OR english ILIKE '%chit%';

-- New keys: the login screen's terms gate and the corrected add-member
-- actions on OW-014.
INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada) VALUES
  ('accept_terms_to_continue', 'I accept the Terms & Conditions and Privacy Policy',
   'నేను నిబంధనలు & షరతులు మరియు గోప్యతా విధానాన్ని అంగీకరిస్తున్నాను',
   'मैं नियम और शर्तें तथा गोपनीयता नीति स्वीकार करता हूँ',
   'நான் விதிமுறைகள் & நிபந்தனைகள் மற்றும் தனியுரிமைக் கொள்கையை ஏற்கிறேன்',
   'ನಾನು ನಿಯಮಗಳು ಮತ್ತು ಷರತ್ತುಗಳು ಹಾಗೂ ಗೌಪ್ಯತಾ ನೀತಿಯನ್ನು ಒಪ್ಪುತ್ತೇನೆ'),
  ('read_terms', 'Read', 'చదవండి', 'पढ़ें', 'படிக்க', 'ಓದಿ'),
  ('terms_and_conditions', 'Terms & Conditions', 'నిబంధనలు & షరతులు', 'नियम और शर्तें', 'விதிமுறைகள் & நிபந்தனைகள்', 'ನಿಯಮಗಳು ಮತ್ತು ಷರತ್ತುಗಳು'),
  ('accept_terms_first_note', 'Accept the Terms & Conditions to continue.',
   'కొనసాగించడానికి నిబంధనలు & షరతులను అంగీకరించండి.',
   'जारी रखने के लिए नियम और शर्तें स्वीकार करें।',
   'தொடர விதிமுறைகள் & நிபந்தனைகளை ஏற்கவும்.',
   'ಮುಂದುವರಿಸಲು ನಿಯಮಗಳು ಮತ್ತು ಷರತ್ತುಗಳನ್ನು ಒಪ್ಪಿಕೊಳ್ಳಿ.'),
  ('add_customer_to_business', 'Add Customer to Business', 'వ్యాపారానికి కస్టమర్‌ను జోడించండి', 'व्यवसाय में ग्राहक जोड़ें', 'வணிகத்தில் வாடிக்கையாளரைச் சேர்', 'ವ್ಯವಹಾರಕ್ಕೆ ಗ್ರಾಹಕರನ್ನು ಸೇರಿಸಿ'),
  ('add_agent_to_business', 'Add Agent to Business', 'వ్యాపారానికి ఏజెంట్‌ను జోడించండి', 'व्यवसाय में एजेंट जोड़ें', 'வணிகத்தில் முகவரைச் சேர்', 'ವ್ಯವಹಾರಕ್ಕೆ ಏಜೆಂಟ್ ಸೇರಿಸಿ'),
  ('member_added_note', '{name} added to this business.', '{name} ఈ వ్యాపారానికి జోడించబడ్డారు.', '{name} इस व्यवसाय में जोड़े गए।', '{name} இந்த வணிகத்தில் சேர்க்கப்பட்டார்.', '{name} ಈ ವ್ಯವಹಾರಕ್ಕೆ ಸೇರಿಸಲಾಗಿದೆ.')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english, telugu = EXCLUDED.telugu,
  hindi = EXCLUDED.hindi, tamil = EXCLUDED.tamil, kannada = EXCLUDED.kannada;
