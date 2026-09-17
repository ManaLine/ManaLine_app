-- Six sentences a form already knew and had no way to say.
--
-- Add Customer's two endings were disabled whenever the form was incomplete,
-- and _canCreateNew was a bool -- so the screen knew perfectly well which of
-- six conditions had failed and could only grey a button out. At a doorstep
-- a disabled button is indistinguishable from a broken one, and here more so:
-- the secondary button kept its full brand-blue border in the disabled state,
-- because outlinedButtonTheme was never given disabled colours while the
-- elevated theme beside it always had them. Fixed app-wide this pass.
--
-- Reported from a handset: "add & issue loan & add only - both on tap not
-- working, not showing any error why it's not happening. either it should
-- work or it should show any error."
--
-- The checks are unchanged. They are ordered the way the form is read, top to
-- bottom, so the first thing named is the first thing missing rather than the
-- last rule written.
--
-- villages_this_business_works heads the shortlist of the book's OWN villages,
-- offered above the national register with each PIN beside its name. A book
-- works a dozen out of 768,529 and the customer being added almost always
-- lives in one of them, so the common case becomes a tap; and two villages of
-- the same name in one district is ordinary, which is what the PIN settles.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('full_name_required', 'Enter the full name.', 'పూర్తి పేరు నమోదు చేయండి.'),
('father_husband_name_required', 'Enter the father or husband name.',
 'తండ్రి లేదా భర్త పేరు నమోదు చేయండి.'),
('gender_required', 'Choose a gender.', 'లింగం ఎంచుకోండి.'),
('village_required', 'Choose a village.', 'గ్రామం ఎంచుకోండి.'),
('mobile_must_be_ten_digits', 'A mobile number is 10 digits.',
 'మొబైల్ నంబర్ 10 అంకెలు ఉండాలి.'),
('aadhaar_must_be_twelve_digits', 'An Aadhaar number is 12 digits.',
 'ఆధార్ నంబర్ 12 అంకెలు ఉండాలి.'),
('pick_a_person_first', 'Choose a person from the list first.',
 'ముందుగా జాబితా నుండి ఒక వ్యక్తిని ఎంచుకోండి.'),
('villages_this_business_works', 'Villages This Business Works',
 'ఈ వ్యాపారం పనిచేసే గ్రామాలు')
ON CONFLICT (translation_key) DO NOTHING;
