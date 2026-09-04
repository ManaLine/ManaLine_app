-- Step 5 of setup asks who works each area, and offered exactly one answer on
-- a new business: the Owner, who is created as its first Agent. There was no
-- way to reach anybody else, so "assign it to myself" was the only possible
-- reply and the true one -- "my agent is Ramesh" -- had to wait until after
-- setup finished, from Workforce Management.
--
-- The picker now ends with an add row that opens OW-014 with type=agent, which
-- already searches an existing person by MLID or name and registers a new one
-- when there is no match.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('search_or_register_agent_note',
 'Search for someone by MLID or name, or register a new agent.',
 'MLID లేదా పేరుతో వెతకండి, లేదా కొత్త ఏజెంట్‌ను నమోదు చేయండి.')
ON CONFLICT (translation_key) DO NOTHING;
