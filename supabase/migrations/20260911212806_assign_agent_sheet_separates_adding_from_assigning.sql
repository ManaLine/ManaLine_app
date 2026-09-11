-- The area sheet was named for one errand and only offered the other.
--
-- "Add an Agent" was a bold grey LABEL with the assignable agents listed
-- under it. With every agent already on the round that list is empty and
-- agents.isEmpty is FALSE, so neither the rows nor the "no active agents"
-- note rendered: the words sat over a blank gap. That is what "add an agent
-- is not working" looked like on the handset.
--
-- Adding a new Agent to the business and assigning an existing one to this
-- round are two different things, so they are two labelled sections now.
--
-- no_active_agents_note is deliberately NOT reworded here even though its
-- advice ("add one from Workforce Management first") is now redundant beside
-- the link directly above it: OW-005 uses the same key in a SnackBar where
-- that advice is still the right thing to say.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('assign_to_this_round', 'Assign to This Round',
 'ఈ రౌండ్‌కు కేటాయించండి'),
('every_agent_already_on_this_round_note',
 'Every agent in this business is already on this round.',
 'ఈ వ్యాపారంలోని ప్రతి ఏజెంట్ ఇప్పటికే ఈ రౌండ్‌లో ఉన్నారు.')
ON CONFLICT (translation_key) DO NOTHING;
