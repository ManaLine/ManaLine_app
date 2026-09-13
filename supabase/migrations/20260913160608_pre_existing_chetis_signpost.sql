-- A cheti already running when the book comes across had no signpost.
--
-- I had told the Owner chetis had "no door at all", from searching the
-- migration path and finding nothing. Wrong: OW-019 has done this all along.
-- The chetis table carries opening_instalments_paid, opening_amount_paid and
-- availed_pre_migration -- columns that exist for precisely this case, the same
-- shape as businesses.opening_bf_declared_amount -- and the create screen
-- already collects all three, validates that opening instalments cannot exceed
-- the total, and requires an amount when the cheti was already availed.
--
-- app.record_cheti_payment composes with it correctly:
--   v_opening_paid + COUNT(cheti_payments) >= total  ->  fully paid
-- so the stated opening and later payments ADD rather than double count. And
-- paying an instalment deducts from owner_bf_balance, which is why the opening
-- figure rightly does not: those instalments left the till before the app
-- existed, and BF is cash that actually moved.
--
-- So the gap was never a feature. It was that an Owner migrating a book has no
-- reason to know the cheti screen is where their two running chetis go. One
-- link, from the screen they are already on.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('chetis_you_are_already_paying', 'Chetis You Are Already Paying',
 'మీరు ఇప్పటికే చెల్లిస్తున్న చీటీలు'),
('pre_existing_cheti_note',
 'Add a cheti that was already running, with the instalments paid so far — and whether it has been availed.',
 'ఇప్పటికే నడుస్తున్న చీటీని ఇప్పటివరకు చెల్లించిన వాయిదాలతో జోడించండి — మరియు అది తీసుకోబడిందా అనేది కూడా.')
ON CONFLICT (translation_key) DO NOTHING;
