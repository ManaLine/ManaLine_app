-- =============================================================================
-- change_user translation key
-- =============================================================================
-- LR-009 Daily Login showed the remembered person's name and a PIN pad with no
-- way out: no "change user" and no "register". If the wrong person was
-- remembered, or someone else picked up the phone, the screen was a dead end —
-- the only escape was clearing app data.
--
-- `register_button` already existed; `change_user` did not. Added here rather
-- than hardcoding an English string in the widget, so it follows the same
-- ui_translations path as every other label on that screen.
--
-- TRANSLATION NOTE: the four non-English values below are my own, matching the
-- house style already in this table (existing rows render "Switch" as
-- "ಬದಲಿಸಿ" / "बदलें", so "Change User" follows that rather than introducing a
-- second verb). They are ordinary UI vocabulary, but they have NOT been checked
-- by a native speaker — worth a review pass in the Supabase Table Editor, which
-- is the intended workflow for wording changes per translation_service.dart.
-- -----------------------------------------------------------------------------

INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada)
VALUES (
  'change_user',
  'Change User',
  'వినియోగదారుని మార్చండి',
  'उपयोगकर्ता बदलें',
  'பயனரை மாற்று',
  'ಬಳಕೆದಾರರನ್ನು ಬದಲಿಸಿ'
)
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english,
  telugu  = EXCLUDED.telugu,
  hindi   = EXCLUDED.hindi,
  tamil   = EXCLUDED.tamil,
  kannada = EXCLUDED.kannada;
