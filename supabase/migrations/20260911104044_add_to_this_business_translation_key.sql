-- The action that closes the global search dead end.
--
-- A search that found a real person holding no role in this business printed
-- "Not a member of this business." and offered nothing. The Add button showed
-- only when the search found NOBODY, so the app offered to create a new
-- person and offered nothing for the person already on screen.
--
-- Everything else that button needs was already here: select_role, customer,
-- agent and investor all exist with Telugu. This is the one missing string.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('add_to_this_business', 'Add To This Business', 'ఈ వ్యాపారానికి జోడించండి')
ON CONFLICT (translation_key) DO NOTHING;
