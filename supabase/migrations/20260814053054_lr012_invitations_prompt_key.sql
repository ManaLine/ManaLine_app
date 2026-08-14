-- Subtitle for LR-012's invitations prompt, which replaced that screen's own
-- Accept/Decline UI and routes to the shared Notifications inbox instead.
--
-- LR-012 is pre-workspace: no dashboard, so no notification bell. Someone
-- whose only membership is a pending invitation reaches "no business linked"
-- and this prompt is their only way into the app, which is why that screen
-- keeps an entry point rather than losing the invitation UI outright.
--
-- {count} is substituted client-side and must survive translation.
INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada) VALUES
  ('pending_invitations_count_note',
   '{count} waiting for your answer',
   'మీ సమాధానం కోసం {count} వేచి ఉన్నాయి',
   '{count} आपके उत्तर की प्रतीक्षा में',
   'உங்கள் பதிலுக்காக {count} காத்திருக்கிறது',
   'ನಿಮ್ಮ ಉತ್ತರಕ್ಕಾಗಿ {count} ಕಾಯುತ್ತಿವೆ')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english, telugu = EXCLUDED.telugu,
  hindi = EXCLUDED.hindi, tamil = EXCLUDED.tamil, kannada = EXCLUDED.kannada;
