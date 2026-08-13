-- Telugu spelled the product two ways: చేతి in the older keys, చీటీ in the
-- newer ones. Confirmed with the Owner (a Telugu speaker) that చీటీ is
-- correct, so the older keys are normalised to match.
--
-- SCOPED to rows whose ENGLISH mentions cheeti, deliberately. చేతి on its own
-- also means "hand" in Telugu, so a blanket replace across ui_translations
-- would corrupt unrelated strings. Restricting by the English column means
-- only the product's own keys are touched.
UPDATE ui_translations
SET telugu = replace(telugu, 'చేతి', 'చీటీ')
WHERE english ILIKE '%cheeti%'
  AND telugu LIKE '%చేతి%';
