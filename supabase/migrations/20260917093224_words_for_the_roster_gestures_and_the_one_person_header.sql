-- Words for tranche B: the roster's two gestures, and the header on the
-- one-person entry screen.
--
-- members_gesture_hint is the whole of the discoverability budget for item 5.
-- Taking the three-dot button off every member row was asked for and is
-- right -- taking somebody off a book should not sit one tap from finishing
-- their entry -- but it also removed the only thing on screen that said
-- suspend and remove exist. One line above the list, rather than an
-- affordance drawn two hundred times.
--
-- entry_closed_note and entry_needs_mlid_note are the two reasons a tap has
-- nowhere to go, kept apart because they mean different things: a locked
-- migration is the BOOK being finished, and a missing MLID is one PERSON's
-- record being incomplete. A tap that does nothing at all reads as a broken
-- row, which is the state this pair exists to prevent.
--
-- care_of is left as "C/o" in both languages on purpose. It is what is
-- printed on the ration card, the Aadhaar letter and the paper ledger these
-- books are copied from, and a translated expansion would be a phrase nobody
-- in the village reads on a form.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('members_gesture_hint',
 'Tap a person to add their entry. Press and hold to suspend or remove.',
 'నమోదు జోడించడానికి వ్యక్తిని తాకండి. సస్పెండ్ చేయడానికి లేదా తీసివేయడానికి నొక్కి ఉంచండి.'),
('entry_closed_note',
 'This book''s pre-existing entry is finished, so there is nothing left to add here.',
 'ఈ పుస్తకం ముందస్తు నమోదు పూర్తయింది, కాబట్టి ఇక్కడ జోడించడానికి ఏమీ లేదు.'),
('entry_needs_mlid_note',
 'This person has no MLID yet, so their entry cannot be opened.',
 'ఈ వ్యక్తికి ఇంకా MLID లేదు, కాబట్టి వారి నమోదును తెరవలేము.'),
('care_of', 'C/o', 'C/o')
ON CONFLICT (translation_key) DO NOTHING;
