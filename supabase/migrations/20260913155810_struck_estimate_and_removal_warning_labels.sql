-- Two sentences, both about not letting the app sound more certain than it is.
--
-- struck_is_estimated_note: a struck total worked out from collection history
-- is a FACT; one worked out from a loan's due date, because nothing has ever
-- been collected against it, is an ESTIMATE. They look identical on screen and
-- lead to the same doorstep, so the screen says which it is showing. Reading an
-- estimate as a fact is how somebody knocks on the wrong door.
--
-- owner_agent_removal_warning: an Owner removing their own Agent membership is
-- authorised and legitimate -- somebody who hires two agents and stops
-- collecting is an ordinary business, and business_members_owner_all already
-- permits it. So this warns rather than blocks. What it must not do is let the
-- Owner discover the consequence the next time they open a collection round.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('struck_is_estimated_note',
 'Estimated from loan dates — nothing has been collected against these in the app yet.',
 'రుణ తేదీల ఆధారంగా అంచనా — వీటిపై యాప్‌లో ఇంకా ఏమీ వసూలు కాలేదు.'),
('owner_agent_removal_warning',
 'You will no longer be able to collect for this business yourself. You can add yourself back as an agent at any time.',
 'మీరు ఇకపై ఈ వ్యాపారానికి స్వయంగా వసూలు చేయలేరు. మీరు ఎప్పుడైనా మిమ్మల్ని తిరిగి ఏజెంట్‌గా జోడించుకోవచ్చు.')
ON CONFLICT (translation_key) DO NOTHING;
