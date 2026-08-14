-- Keys for the split name fields and the Aadhaar notice at LR-004.
--
-- The notice says "can lead to", not "leads to": suspension is the outcome of
-- a human comparing the name to the document, not something the app does on
-- its own, and a threat the system does not carry out teaches people to skip
-- reading it.
insert into ui_translations (translation_key, english, telugu) values
  ('surname_field',
   'Surname (House Name) *',
   'ఇంటి పేరు *'),
  ('surname_helper',
   'The house name that comes first on your Aadhaar.',
   'మీ ఆధార్‌లో మొదట ఉండే ఇంటి పేరు.'),
  ('name_field',
   'Name *',
   'పేరు *'),
  ('will_be_saved_as',
   'Will be saved as:',
   'ఇలా సేవ్ అవుతుంది:'),
  ('name_in_telugu_optional_field',
   'Name in Telugu (optional)',
   'తెలుగులో పేరు (ఐచ్ఛికం)'),
  ('name_in_telugu_helper',
   'Shown in the app only. Your Aadhaar name above stays on official records.',
   'యాప్‌లో మాత్రమే కనిపిస్తుంది. అధికారిక రికార్డులలో పైన ఉన్న ఆధార్ పేరే ఉంటుంది.'),
  ('aadhaar_name_notice',
   'Enter your name exactly as printed on your Aadhaar. A mismatch can lead to your account being suspended.',
   'మీ ఆధార్‌లో ముద్రించి ఉన్నట్టుగానే మీ పేరు నమోదు చేయండి. తేడా ఉంటే మీ ఖాతా నిలిపివేయబడవచ్చు.')
on conflict (translation_key) do nothing;
