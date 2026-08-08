-- Keys for the header/drawer rework and LR-012's two-line welcome block.
--
-- 'welcome' is new. The rest already exist as keys used by the Owner
-- dashboard's old overflow menu; they are re-asserted here because the same
-- labels are now drawer rows in all four workspaces, and ON CONFLICT DO
-- NOTHING makes that a no-op wherever they are already present.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('welcome', 'Welcome', 'స్వాగతం'),
('profile', 'Profile', 'ప్రొఫైల్'),
('settings', 'Settings', 'సెట్టింగ్‌లు'),
('logout', 'Logout', 'లాగ్ అవుట్'),
('switch_workspace', 'Switch Workspace', 'వర్క్‌స్పేస్ మార్చండి'),
('switch_role', 'Switch Role', 'పాత్ర మార్చండి'),
('business_management', 'Business Management', 'వ్యాపార నిర్వహణ'),
('report_hub', 'Report Hub', 'నివేదిక కేంద్రం')
ON CONFLICT (translation_key) DO NOTHING;
