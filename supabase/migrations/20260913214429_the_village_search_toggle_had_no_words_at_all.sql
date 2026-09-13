-- Four keys that have been rendering as their own names on a live screen.
--
-- village_search_by_pin, village_search_by_state_district,
-- choose_state_to_continue and no_villages_found_for_search were written into
-- lib/shared/widgets/village_search_field.dart and no migration was ever
-- written for any of them. ref.t() falls back to the key, so an Owner adding
-- an operating area saw a two-option toggle reading
-- "village_search_by_pin" and "village_search_by_state_district", and under it
-- "choose_state_to_continue".
--
-- This is the FOURTH time raw keys have reached a handset -- use_my_location,
-- add_this_persons_entry, and now four at once on the same widget. The guard
-- built after the last one only watches the five files of the one-by-one door,
-- so it could not have seen these. It is being widened to all of lib/ in the
-- same change that adds these rows, because a key that exists only in Dart is
-- a defect the moment it is written, not the moment somebody notices it.
--
-- The labels are SHORT on purpose. "Search By State And District" wrapped to
-- two lines inside a SegmentedButton and pushed the control out of shape; what
-- the two options actually differ by is which handle you have -- the PIN code,
-- or the village's name.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('village_search_by_pin', 'PIN', 'పిన్'),
('village_search_by_state_district', 'Name', 'పేరు'),
('choose_state_to_continue', 'Choose a state to continue.',
 'కొనసాగించడానికి రాష్ట్రాన్ని ఎంచుకోండి.'),
('no_villages_found_for_search', 'No villages found by that name.',
 'ఆ పేరుతో గ్రామాలు కనిపించలేదు.')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english,
  telugu  = EXCLUDED.telugu;
