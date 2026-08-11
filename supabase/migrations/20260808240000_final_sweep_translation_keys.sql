-- Final sweep of the wiring pass: literals the per-screen passes missed.
-- admin_panel_screen.dart lives outside a screens/ directory, so the
-- "every screen" scan skipped it entirely; the rest were formatting
-- variants (a trailing style: arg, a different indent) that the
-- per-screen string replacements did not match.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('admin_panel', 'Admin Panel', 'అడ్మిన్ ప్యానెల్'),
('are_you_absolutely_sure', 'Are You Absolutely Sure?', 'మీరు ఖచ్చితంగా నిర్ధారించారా?'),
('mana_chits_coming_soon', 'MANA Chits — coming soon — version 2', 'మానా చిట్స్ — త్వరలో — వెర్షన్ 2'),
('close', 'Close', 'మూసివేయండి'),
('accept_terms_conditions', 'Accept Terms & Conditions *', 'నిబంధనలు & షరతులు అంగీకరించండి *'),
('accept_privacy_policy', 'Accept Privacy Policy *', 'గోప్యతా విధానం అంగీకరించండి *'),
('still_needed_to_register', 'Still Needed to Register', 'నమోదుకు ఇంకా అవసరం'),
('register', 'Register', 'నమోదు చేయండి'),
('use_your_location_question', 'Use Your Location?', 'మీ స్థానాన్ని ఉపయోగించాలా?'),
('not_now', 'Not Now', 'ఇప్పుడు కాదు'),
('allow', 'Allow', 'అనుమతించండి'),
('use_other_pin_length', 'Use {digits}-digit PIN instead', 'బదులుగా {digits}-అంకెల పిన్ ఉపయోగించండి'),
('rows_ready_to_import', '{count} rows ready to import', '{count} వరుసలు దిగుమతికి సిద్ధం')
ON CONFLICT (translation_key) DO NOTHING;
