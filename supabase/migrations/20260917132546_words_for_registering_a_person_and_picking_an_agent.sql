-- The words "Minimum Information" left behind, and the one the agent picker
-- needs when there is nobody to pick.
--
-- register_new_person replaces the heading on OW-014's not-found step. That
-- form asked for three things and could not save any of them: auth-register
-- validates address.village_id and a six-digit pin_code, and the form
-- collected a village as FREE TEXT -- so every Save was a 400, and had been
-- since it was written. It also hardcoded gender '0' against a NOT NULL
-- column, in a comment that said so.
--
-- The note under it says why the form is as long as it is. An Owner who has
-- just searched and found nobody is about to create a person, and the fields
-- are the ones a person record cannot be made without -- the same set Add
-- Customer settled on, because it is the same act. The role is attached
-- afterwards.
--
-- no_other_agents_note is an honest empty state rather than a disabled
-- dropdown. A one-agent business has nobody to hand cash to, and that is a
-- fact about the book rather than a fault.
--
-- others, for the gender picker: gender_digit has had three values since
-- Others was added, and a picker offering two would quietly make somebody
-- choose wrong. minimum_information and to_agent_id_field are left in the
-- table -- a key nothing asks for costs nothing, and deleting rows other
-- migrations inserted is how a rebuild comes up short.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('register_new_person', 'Register This Person', 'ఈ వ్యక్తిని నమోదు చేయండి'),
('register_new_person_note',
 'Nobody on file matches. These are the details a person record cannot be created without.',
 'సరిపోలే వ్యక్తి ఎవరూ లేరు. వ్యక్తి రికార్డు సృష్టించడానికి ఈ వివరాలు తప్పనిసరి.'),
('no_other_agents_note',
 'There is no other agent on this business to send cash to.',
 'ఈ వ్యాపారంలో నగదు పంపడానికి మరో ఏజెంట్ లేరు.'),
('others', 'Others', 'ఇతరులు'),
('gender_field', 'Gender *', 'లింగం *')
ON CONFLICT (translation_key) DO NOTHING;
