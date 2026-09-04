-- Step 3 of setup navigates to OW-018 with the business id. Step 1 creates the
-- business, so a null id should be unreachable -- but a dead tap with no
-- explanation is how the old SnackBar behaved, and replacing one silent
-- non-action with another would be no fix at all.
--
-- Inserted idempotently: this row was first written by a direct statement
-- rather than a migration, which left the ledger and the repo disagreeing about
-- whether it existed. ON CONFLICT DO NOTHING makes re-applying harmless and
-- puts the two back in step.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('create_the_business_first',
 'Create the business first — step 1.',
 'ముందుగా వ్యాపారాన్ని సృష్టించండి — దశ 1.')
ON CONFLICT (translation_key) DO NOTHING;
