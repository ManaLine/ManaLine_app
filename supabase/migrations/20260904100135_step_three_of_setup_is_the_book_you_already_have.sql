-- Step 3 of first-business setup pointed at OW-014 (pre-existing MEMBER
-- migration) and, on tap, showed a SnackBar reading "OW-014 Global Workflow --
-- not yet built in this pass." That text was stale twice over: OW-014 is built
-- and reachable at /ow-014, and it is not what belongs in this step anyway.
--
-- The Owner's decision: step 3 is the pre-existing BUSINESS migration, OW-018 --
-- the weekly-ledger import that brought the sri satyanarayana book across. A
-- business being set up that already exists on paper needs its book, not a
-- member-by-member walk.
--
-- Keys are new rather than edits to start_pre_existing_migration and
-- launches_global_workflow_note, because those two still describe OW-014
-- correctly and are used from OW-002 and OW-003.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('migrate_existing_book',
 'Bring Your Existing Book Across',
 'మీ ప్రస్తుత పుస్తకాన్ని తీసుకురండి'),
('migrate_existing_book_note',
 'Import the weeks you already have on paper — opening balance, collections, expenses and investors.',
 'మీ వద్ద కాగితంపై ఉన్న వారాలను దిగుమతి చేయండి — ప్రారంభ నిల్వ, వసూళ్లు, ఖర్చులు మరియు పెట్టుబడిదారులు.'),
('migrate_existing_book_step_note',
 'Optional. If this business already runs on paper, bring its book across now. Skip if it is starting fresh.',
 'ఐచ్ఛికం. ఈ వ్యాపారం ఇప్పటికే కాగితంపై నడుస్తుంటే, దాని పుస్తకాన్ని ఇప్పుడు తీసుకురండి. కొత్తగా ప్రారంభిస్తే దాటవేయండి.')
ON CONFLICT (translation_key) DO NOTHING;
