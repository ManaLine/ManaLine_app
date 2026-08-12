-- Keys introduced by the field-UX batch that were never given a migration.
--
-- These were added to test/support/mana_translations_fixture.dart so the
-- layout tests measured real translated widths, but the fixture is vendored
-- test data — it does not reach the database. The result was that the app
-- rendered the raw key: the registration form's address section literally
-- showed "use_my_location". Caught on device, not by any test, because the
-- tests read the fixture and therefore always found a value.
--
-- English + Telugu only, matching the rest of this table (768/768 rows have
-- Telugu; Hindi/Tamil/Kannada are populated for 87). ref.t() falls back to
-- English for a missing language, so the other three degrade to English
-- rather than to a raw key.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
-- Address forms (LR-004, OW-004, OW-018)
('use_my_location', 'Use My Location', 'నా స్థానాన్ని ఉపయోగించండి'),
-- OW-001 Quick Actions
('register_customer', 'Register Customer', 'కస్టమర్‌ను నమోదు చేయండి'),
-- Merged login screen (LR-009)
('login_with_pin', 'Login With PIN', 'పిన్‌తో లాగిన్ చేయండి'),
('exit app', 'Exit App', 'యాప్‌ను మూసివేయండి'),
('exit', 'Exit', 'నిష్క్రమించండి'),
('are you sure you want to close mana line?', 'Are You Sure You Want To Close MANA LINE?', 'మీరు ఖచ్చితంగా మన లైన్‌ను మూసివేయాలనుకుంటున్నారా?'),
-- OW-018 one-at-a-time migration form
('existing customer', 'Existing Customer', 'ఇప్పటికే ఉన్న కస్టమర్'),
('new person', 'New Person', 'కొత్త వ్యక్తి'),
('save and add another', 'Save And Add Another', 'సేవ్ చేసి మరొకటి జోడించండి'),
('add a customer', 'Add A Customer', 'కస్టమర్‌ను జోడించండి'),
-- Pre-dates this batch: OW-018's own AppBar has always shown this raw.
('pre-existing business', 'Pre-Existing Business', 'ముందుగా ఉన్న వ్యాపారం')
ON CONFLICT (translation_key) DO NOTHING;
