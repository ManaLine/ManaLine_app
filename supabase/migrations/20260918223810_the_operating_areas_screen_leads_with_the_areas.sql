-- Operating Areas opened with a form and buried the areas below it.
--
-- The Owner, 2026-09-18: "operating areas - change the screen display looks
-- outdated ... remove area name & village selection show operating areas (if
-- any) and add area option opposite to 'current operating areas'".
--
-- The screen's first two thirds were an empty Area Name box and a village
-- search, so the thing an Owner came to look at -- the rounds they actually
-- run -- started below the fold. Creating an area is the rarer act and it
-- moves into a sheet; the list leads.
--
-- AREA NAME DEFAULTS TO THE VILLAGE, because the Owner said "here village &
-- area both are same". That was already true in code (the old form fell back
-- to the village name when the box was left empty) and invisible: an empty
-- box does not tell anybody what it will do. The sheet fills it in instead,
-- and it stays editable for the day a second village joins the round.

INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('add_area_title', 'Add an Area', 'ఏరియా జోడించండి'),
  ('add_area_step_village',
   'Which village does this round start from?',
   'ఈ రౌండ్ ఏ గ్రామం నుంచి మొదలవుతుంది?'),
  ('add_area_name_hint',
   'Named after the village. Change it if the round covers more than one.',
   'గ్రామం పేరు పెట్టబడింది. రౌండ్‌లో ఒకటి కంటే ఎక్కువ ఉంటే మార్చండి.'),
  ('no_agent_assigned_short', 'No agent assigned', 'ఏజెంట్ కేటాయించలేదు')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key IN ('add_area_title','add_area_step_village',
                             'add_area_name_hint','no_agent_assigned_short')
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 4 THEN
    RAISE EXCEPTION 'expected 4 translated keys, found %', v_n;
  END IF;
END $$;
