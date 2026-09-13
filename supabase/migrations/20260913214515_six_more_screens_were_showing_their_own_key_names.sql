-- Found by the widened guard, not by anybody opening the screens.
--
-- The Owner reported four raw keys on the village search. Sweeping every
-- ref.t() in lib/ against ui_translations -- 1,336 keys, which is the check
-- that should have existed all along -- turned up six more already live:
--
--   about                       the About screen's own title
--   account                     the Account & Closure screen's own title
--   appearance                  the Appearance screen's own title
--   restore                     the button that brings a deleted record back
--   village_needs_pin_note      why the PIN box is there when adding a village
--   add_village_for_place_note  the cascade half of the add-village sheet
--
-- Three of them are SCREEN TITLES, which is the part worth saying out loud:
-- these are not buried notes, they are the words in the app bar, and nobody
-- opening Settings had reported them. That is the whole argument for the
-- guard. Noticing one raw key among dozens of correct ones is not something
-- a person does reliably, and three of these have been sitting in plain sight.
--
-- add_village_for_place_note takes {district} and {state}, matching the shape
-- of add_village_for_pin_note beside it, which does have a row.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('about', 'About', 'గురించి'),
('account', 'Account', 'ఖాతా'),
('appearance', 'Appearance', 'రూపం'),
('restore', 'Restore', 'పునరుద్ధరించండి'),
('village_needs_pin_note',
 'A village needs a PIN code so it can be found again later.',
 'తర్వాత మళ్లీ కనుగొనడానికి గ్రామానికి పిన్ కోడ్ అవసరం.'),
('add_village_for_place_note',
 'Add a village in {district}, {state}.',
 '{state}లోని {district}లో ఒక గ్రామాన్ని జోడించండి.')
ON CONFLICT (translation_key) DO NOTHING;
