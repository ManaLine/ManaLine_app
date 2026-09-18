-- The bulk onboarding wizard moves off the handset.
--
-- The Owner's judgement, 2026-09-18: "for an user onboarding wizard via app is
-- difficult and messy and may go wrong - so we remove it from app".
--
-- They are right, and the screen itself is the evidence: seven pages of
-- spreadsheet grids, 2,170 lines, the largest file in lib/. It asks somebody
-- to download a workbook, fill it in, and upload it again -- on a phone, where
-- there is no comfortable place to edit a spreadsheet at all. Every step that
-- goes wrong goes wrong against a real book being brought across once.
--
-- The wizard is NOT deleted. It already runs on the web build -- the route has
-- been in kManaWebAllowedRoutes all along -- where a laptop, a real keyboard
-- and Excel are. The handset keeps the route and shows the way there instead,
-- so an Owner who taps the old entry point is told where to go rather than
-- finding nothing.
--
-- 'bulk_onboarding_is_on_the_web_body' names the three things that actually
-- change: a bigger screen, a real spreadsheet program, and a file that does
-- not have to survive being edited on a phone. "Use the website" on its own
-- reads like an app that cannot do its job.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('bulk_onboarding',            'Bulk Onboarding',     'బల్క్ ఆన్‌బోర్డింగ్'),
('bulk_onboarding_is_on_the_web',
 'Bring your book across on the website',
 'మీ పుస్తకాన్ని వెబ్‌సైట్‌లో తీసుకురండి'),
('bulk_onboarding_is_on_the_web_body',
 'This step means downloading a spreadsheet, filling it in and uploading it back. That is work for a computer: a bigger screen, a real spreadsheet program, and a file that does not have to survive being edited on a phone.',
 'ఈ దశలో స్ప్రెడ్‌షీట్ డౌన్‌లోడ్ చేసి, పూరించి, తిరిగి అప్‌లోడ్ చేయాలి. ఇది కంప్యూటర్‌కు సరిపోయే పని: పెద్ద స్క్రీన్, నిజమైన స్ప్రెడ్‌షీట్ ప్రోగ్రామ్, మరియు ఫోన్‌లో ఎడిట్ చేయవలసిన అవసరం లేని ఫైల్.'),
('bulk_onboarding_web_steps',
 'Sign in with the same MLID and password, then choose Bulk Onboarding from the menu.',
 'అదే MLID మరియు పాస్‌వర్డ్‌తో సైన్ ఇన్ చేసి, మెనూ నుండి బల్క్ ఆన్‌బోర్డింగ్ ఎంచుకోండి.'),
('open_the_website',           'Open The Website',    'వెబ్‌సైట్ తెరవండి'),
('copy_link',                  'Copy Link',           'లింక్ కాపీ చేయండి'),
('no_browser_on_this_device',
 'No browser on this device. The address is {url}',
 'ఈ పరికరంలో బ్రౌజర్ లేదు. చిరునామా {url}'),
('one_by_one_still_works_here',
 'Adding people one at a time still works here, and is the better door for a handful.',
 'ఒక్కొక్కరిగా చేర్చడం ఇక్కడే పని చేస్తుంది, కొద్ది మందికి అదే మంచి మార్గం.')
ON CONFLICT (translation_key) DO NOTHING;
