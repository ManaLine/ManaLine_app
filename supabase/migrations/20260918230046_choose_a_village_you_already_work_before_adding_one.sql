-- Adding a person started with a blank village search, and that is where the
-- duplicates come from.
--
-- The Owner, 2026-09-18: "Add a customer or user - first ask to select
-- village (show added village list to choose & option to add - search and add
-- via pin/name) - search (already added list) or add (new) - this reduces
-- duplicates registration of user and villages both."
--
-- The evidence was on their own screen: "Panagal" and "Panagallu (Rural)" for
-- one place, and Srikalahasti filed under two districts. Every entry point
-- offered a free search over the whole LGD reference with no sign of which
-- villages this business already works, so the second person to type a name
-- typed a different one and got a second village.
--
-- The fix is an ORDER, not a validation: show what is already there first,
-- and make adding a new one the second choice rather than the only one.

INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('village_choose_existing', 'Choose a village', 'గ్రామాన్ని ఎంచుకోండి'),
  ('village_choose_existing_note',
   'The villages this business already works. Pick one so the same place is not added twice.',
   'ఈ వ్యాపారం ఇప్పటికే పనిచేసే గ్రామాలు. ఒకే ప్రాంతం రెండుసార్లు జోడించకుండా ఒకదాన్ని ఎంచుకోండి.'),
  ('village_add_another', 'Not listed — add a village', 'జాబితాలో లేదు — గ్రామం జోడించండి'),
  ('village_back_to_list', 'Back to the list', 'జాబితాకు తిరిగి వెళ్లండి'),
  ('village_none_yet',
   'No villages yet. Add the first one below.',
   'ఇంకా గ్రామాలు లేవు. మొదటిదాన్ని క్రింద జోడించండి.'),
  ('add_customer_here', 'Add a customer here', 'ఇక్కడ కస్టమర్‌ను జోడించండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key IN ('village_choose_existing','village_choose_existing_note',
                             'village_add_another','village_back_to_list',
                             'village_none_yet','add_customer_here')
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 6 THEN
    RAISE EXCEPTION 'expected 6 translated keys, found %', v_n;
  END IF;
END $$;
