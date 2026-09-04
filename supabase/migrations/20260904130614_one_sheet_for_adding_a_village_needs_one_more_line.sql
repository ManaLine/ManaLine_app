-- The Add New Village sheet replaces seven inline forms. Every other string it
-- needs already exists; this is the one that does not -- it names the PIN the
-- village is being added under, so somebody cannot add a village to the wrong
-- postal area while looking at a sheet that never says which one it is.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('add_village_for_pin_note',
 'The directory has no match at PIN {pin}. Add it, and mandal and district will come from the PIN.',
 'పిన్ {pin} వద్ద డైరెక్టరీలో సరిపోలిక లేదు. దాన్ని జోడించండి, మండలం మరియు జిల్లా పిన్ నుండి వస్తాయి.')
ON CONFLICT (translation_key) DO NOTHING;
