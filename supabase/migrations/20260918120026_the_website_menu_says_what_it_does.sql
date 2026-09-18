-- The website's bulk-onboarding menu says what it does, in both languages.
--
-- The handset's signpost (2026-09-18) promises "login - menu showing bulk
-- onboarding - allowing customers to download fill upload their sheets". This
-- is the copy for that menu.
--
-- TELUGU IS FILLED IN HERE, not left for later. docs/DEPLOY.md already records
-- that the web_home_* keys shipped English-only and that a Telugu visitor to
-- /app/ therefore reads English on those specific strings. Adding a second set
-- of half-translated web keys would turn a noted exception into the pattern --
-- and this screen is now the ONLY place bulk onboarding exists, so an Owner
-- who reads Telugu has nowhere else to go.
--
-- NO NEW KEY FOR A WORD ALREADY HERE. investors, customers, agents, finish,
-- open, withdrawals and get_template already carry English and Telugu, and
-- ManaBulkPage.titleKey points at those rather than minting
-- bulk_step_investors beside an investors that says the same word.

INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('bulk_menu_lead', 'Download the sheets your book needs, fill them in at your own pace, then bring them back one step at a time.', 'మీ పుస్తకానికి కావలసిన షీట్లను డౌన్‌లోడ్ చేసుకోండి, మీ వీలు ప్రకారం నింపండి, తర్వాత ఒక్కో దశగా తిరిగి తీసుకురండి.'),
  ('bulk_menu_cutoff', 'Cut-Off Date', 'కట్-ఆఫ్ తేదీ'),
  ('bulk_menu_no_cutoff', 'Not Chosen Yet', 'ఇంకా ఎంచుకోలేదు'),
  ('bulk_menu_start_title', 'Start With Your Book', 'మీ పుస్తకంతో ప్రారంభించండి'),
  ('bulk_menu_start_body', 'Tell us what your book has, and we will ask only for those sheets.', 'మీ పుస్తకంలో ఏముందో చెప్పండి, ఆ షీట్లను మాత్రమే అడుగుతాం.'),
  ('bulk_menu_sheets', 'Get Your Sheets', 'మీ షీట్లను తీసుకోండి'),
  ('bulk_menu_sheets_note', 'Download them all now. Nothing is saved until you bring a filled sheet back.', 'ఇప్పుడే అన్నీ డౌన్‌లోడ్ చేసుకోండి. నింపిన షీట్ తిరిగి ఇచ్చేవరకు ఏదీ సేవ్ కాదు.'),
  ('bulk_menu_steps', 'Bring Them Back', 'వాటిని తిరిగి తీసుకురండి'),
  ('bulk_menu_steps_note', 'In this order. Identities come first, because everything else in the book points at a person.', 'ఈ క్రమంలోనే. ముందుగా వ్యక్తుల వివరాలు — పుస్తకంలోని మిగతా అన్నీ ఒక వ్యక్తిని సూచిస్తాయి.'),
  ('bulk_menu_change_plan', 'Change What Your Book Has', 'మీ పుస్తకంలో ఏముందో మార్చండి'),
  ('bulk_menu_sheet_failed', 'That sheet could not be built. Try again.', 'ఆ షీట్ తయారు కాలేదు. మళ్ళీ ప్రయత్నించండి.'),
  ('bulk_step_plan', 'What Your Book Has', 'మీ పుస్తకంలో ఏముంది'),
  ('bulk_step_identities', 'Identities', 'వ్యక్తుల వివరాలు'),
  ('bulk_step_snapshot', 'Opening Snapshot', 'ప్రారంభ స్థితి'),
  ('bulk_step_weekly', 'Weekly Account', 'వారపు ఖాతా'),
  ('bulk_sheet_shares', 'Profit Shares', 'లాభ వాటాలు'),
  ('bulk_sheet_attendance', 'Agent Attendance', 'ఏజెంటు హాజరు')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key LIKE 'bulk_menu_%'
      OR translation_key LIKE 'bulk_step_%'
      OR translation_key LIKE 'bulk_sheet_%';
  IF v_n <> 17 THEN
    RAISE EXCEPTION 'expected 17 bulk-menu keys, found %', v_n;
  END IF;

  -- Every one of them must have Telugu, which is the whole point of the
  -- note above. An empty string counts as missing.
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE (translation_key LIKE 'bulk_menu_%'
       OR translation_key LIKE 'bulk_step_%'
       OR translation_key LIKE 'bulk_sheet_%')
     AND COALESCE(telugu, '') = '';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '% bulk-menu keys have no Telugu', v_n;
  END IF;
END $$;
