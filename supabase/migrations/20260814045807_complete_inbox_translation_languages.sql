-- The shared Notifications inbox reads fifteen keys. All fifteen existed, but
-- four of them carried English and Telugu only — they predate this project's
-- five-language rule, and on a Hindi, Tamil or Kannada handset the inbox's
-- two decision buttons would have fallen back to English.
--
-- "Approve" and "Reject" on a membership request are exactly the wrong place
-- to fall back: the person deciding is the Owner, and the words are the whole
-- interaction.
--
-- WIDER PROBLEM THIS EXPOSED, recorded here because it is not fixable in one
-- migration: of 1,439 translation keys, 1,284 have NO Hindi, Tamil or Kannada
-- at all. Telugu is complete; the other three sit at roughly 11% coverage. The
-- app is effectively English + Telugu, not five languages. Filling that is
-- ~3,850 translations and needs native speakers, not a migration written here.
UPDATE ui_translations SET
  hindi = 'सूचनाएँ', tamil = 'அறிவிப்புகள்', kannada = 'ಅಧಿಸೂಚನೆಗಳು'
WHERE translation_key = 'notifications';

UPDATE ui_translations SET
  hindi = 'स्वीकृत करें', tamil = 'ஒப்புதல்', kannada = 'ಅನುಮೋದಿಸಿ'
WHERE translation_key = 'approve';

UPDATE ui_translations SET
  hindi = 'अस्वीकार करें', tamil = 'நிராகரி', kannada = 'ತಿರಸ್ಕರಿಸಿ'
WHERE translation_key = 'reject';

UPDATE ui_translations SET
  hindi = 'सभी को पढ़ा हुआ चिह्नित करें', tamil = 'அனைத்தையும் படித்ததாகக் குறி',
  kannada = 'ಎಲ್ಲವನ್ನೂ ಓದಿದಂತೆ ಗುರುತಿಸಿ'
WHERE translation_key = 'mark_all_read';
