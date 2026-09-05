-- 80.2% of the 31,705 Andhra Pradesh rows in lgd_villages are duplicates of one
-- another: 10,705 village+pincode combinations listed under two or more district
-- names, because the 2022 reorganisation left every affected village carried
-- under both its old district and its new one. A. Veeravaram at 533354 appears
-- under three.
--
-- That is what makes a picker offer the same village twice, and what made the
-- mandal/district dropdown show four options for 517536 when there are two
-- places.
--
-- THIS MIGRATION DOES THE HALF THAT IS MECHANICAL, and deliberately stops
-- there.
--
-- 1. Two spellings of a district that does exist:
--      'Ntr'           -> 'NTR District'
--      'Y.S.R. Kadapa' -> 'YSR Kadapa'
--    Pure naming. No village changes district.
--
-- 2. Two districts that are not among the 26: Markapuram and Polavaram were
--    proposed in the reorganisation and never constituted. 1,338 rows. Checked
--    first: every village carried under them is ALSO carried under a real
--    district, so no village loses its only row (measured: 0).
--
-- WHAT IT DOES NOT DO, on purpose. 10,241 place-keys remain under two or more
-- CURRENTLY VALID districts -- A.Channamambapuram at 516107 in Pullampeta is
-- listed under Annamayya, Tirupati AND YSR Kadapa, all three real today. The
-- data cannot say which it is in now, and district is not decoration here: it
-- feeds the address, the address feeds the village, the village feeds the
-- operating area, and the operating area decides whose round reaches that
-- customer. A wrong district is a customer nobody collects from.
--
-- A plausible rule -- "prefer the newest", "prefer the one with more villages
-- at that PIN" -- would look right and be wrong at scale. The authority is the
-- LGD bulk export, which carries the current district per village. Until that
-- is loaded, app.suggest_similar_villages dedupes on display (DISTINCT ON) so
-- the duplication is invisible in a picker even though it is still in the data.
--
-- Verified before applying: no FK references lgd_villages, and no `locations`
-- row uses any of the four district values touched here.
--
-- Verified after: 30,367 rows, exactly 26 districts, all 26 present, none
-- outside the list, and 19,992 distinct (village, mandal) pairs -- unchanged,
-- so no village coverage was lost.

UPDATE lgd_villages SET district = 'NTR District'
 WHERE state = 'Andhra Pradesh' AND district = 'Ntr';

UPDATE lgd_villages SET district = 'YSR Kadapa'
 WHERE state = 'Andhra Pradesh' AND district = 'Y.S.R. Kadapa';

DELETE FROM lgd_villages
 WHERE state = 'Andhra Pradesh'
   AND district IN ('Markapuram', 'Polavaram');
