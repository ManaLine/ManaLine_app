-- Shown when Create New is stopped because somebody already on file looks
-- like the same person.
--
-- persons.mobile_number is UNIQUE, so two people cannot share one. But the
-- column is NULLABLE and Postgres allows unlimited NULLs in a unique column,
-- while the Add Customer sheet permits an empty mobile -- so two people with
-- the same name, father's name, gender and village and no phone between them
-- were two persons rows with an MLID each, and nothing objected.
--
-- The sentence has to carry the way out as well as the refusal: an Owner
-- standing in front of a genuine namesake must not be stuck, and the mobile
-- number is exactly what distinguishes them.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('duplicate_person_note',
 'Somebody with this name and father''s or husband''s name is already registered. Choose them below, or add a mobile number if this is a different person.',
 'ఈ పేరు మరియు తండ్రి లేదా భర్త పేరుతో ఇప్పటికే ఒకరు నమోదై ఉన్నారు. కింద వారిని ఎంచుకోండి, లేదా ఇది వేరే వ్యక్తి అయితే మొబైల్ నంబర్ జోడించండి.')
ON CONFLICT (translation_key) DO NOTHING;
