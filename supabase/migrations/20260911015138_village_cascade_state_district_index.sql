-- @target: production
-- The village cascade (state -> district -> >=3 letters of village) has no
-- index to run on: lgd_villages carries only a pincode index across 767,191
-- rows. Measured: state+district+village-prefix filter runs as a Parallel
-- Seq Scan, ~1.5-2.3s, removing 383,588 rows by filter. On a rural Android
-- keystroke that is unusable.
--
-- Tested hypothesis: a btree on (state, district) alone, with no index on
-- village, is enough -- narrowing to one district leaves at most ~8,500
-- rows and an ILIKE scan over that is cheap. Confirmed: with the index,
-- the same query runs as an Index Scan on idx_lgd_villages_state_district
-- with a Filter on village, in ~15ms. No trigram/GIN index was added.
create index if not exists idx_lgd_villages_state_district
  on lgd_villages (state, district);
