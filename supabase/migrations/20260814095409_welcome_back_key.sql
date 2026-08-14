-- LR-009's header was the hardcoded English string 'Welcome back' guarding an
-- always-empty _personName. The name is gone (a lock screen should not name
-- the person whose handset it is), and the greeting is now translated.
insert into ui_translations (translation_key, english, telugu) values
  ('welcome_back', 'Welcome Back', 'మళ్ళీ స్వాగతం')
on conflict (translation_key) do nothing;
