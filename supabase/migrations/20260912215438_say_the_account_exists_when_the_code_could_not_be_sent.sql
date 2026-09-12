-- "Am I registered or not?" is the question that made a duplicate person.
--
-- Two Karri Priyanka rows were created 2m14s apart on 2026-09-03 with
-- DIFFERENT mobile numbers -- the second attempt deliberately used other
-- details, because the first had given no sign it worked. The cause was fixed
-- the next day (d79b3dd: registration never sent the OTP, and LR-005 blamed a
-- page refresh on a handset that has no page to refresh), and the happy path
-- now ends on LR-006 showing the new MANA LINE ID.
--
-- One window is still open. When the OTP SEND fails, LR-004 still goes to
-- LR-005 -- correctly, because the account exists by then and going back would
-- register the same person twice. But the screen looks like an ordinary OTP
-- screen waiting for a code that will never arrive, and the explanation only
-- appears AFTER the person types six digits they never received. Nothing
-- anywhere says the account was created.
--
-- That is the same ambiguity that produced the duplicate, so it is answered on
-- arrival now, and it answers the question the person is actually asking: yes,
-- you are registered, here is your ID, the code is what failed.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('account_created_code_not_sent_note',
 'Your account is created — your MANA LINE ID is {mlid}. Do not register again. We could not send your code; tap Resend Otp.',
 'మీ ఖాతా సృష్టించబడింది — మీ మన లైన్ ఐడీ {mlid}. మళ్లీ నమోదు చేయవద్దు. మేము మీ కోడ్‌ను పంపలేకపోయాము; రీసెండ్ Otp నొక్కండి.')
ON CONFLICT (translation_key) DO NOTHING;
