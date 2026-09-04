-- LR-005 told everybody their page had been refreshed.
--
-- auth-register answers `otp_id: null` on purpose -- identity creation is kept
-- decoupled from the SMS gateway -- and expects the caller to make the
-- auth-otp-send call. LR-004 never did, so LR-005 always found no pending OTP
-- and showed a message about refreshing the page, which cannot happen on a
-- handset. Two different failures wore one message, and it named the rarer.
--
-- Split in two. The recoverable case keeps the personId, so Resend works.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('otp_not_sent_tap_resend',
 'We could not send your code. Tap Resend Otp to try again.',
 'మేము మీ కోడ్‌ను పంపలేకపోయాము. మళ్లీ ప్రయత్నించడానికి "ఓటీపీ మళ్లీ పంపు" నొక్కండి.'),
('verification_session_lost',
 'Your verification session was lost. Please go back and start again from the beginning.',
 'మీ ధృవీకరణ సెషన్ కోల్పోయింది. దయచేసి వెనక్కి వెళ్లి మొదటి నుండి మళ్లీ ప్రారంభించండి.')
ON CONFLICT (translation_key) DO NOTHING;
