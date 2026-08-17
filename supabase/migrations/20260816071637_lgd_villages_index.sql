-- One index, built after the 768,529-row import rather than before it.
--
-- ONLY on pincode, and that is deliberate. Every village lookup in the app is
-- already scoped to a pincode the Owner has typed, so this narrows to about 45
-- rows on average and 358 at the worst pincode in the data. Filtering those by
-- village name, mandal or district costs nothing, so:
--
--   * no trigram index on `village` — it would be 80–150 MB, larger than the
--     table itself, to speed up a scan of 45 rows;
--   * no composite on (pincode, mandal, district) — it starts with the same
--     column, adds no selectivity over this one, and costs ~35 MB.
--
-- This project is on the 500 MB tier. An index that earns nothing is not free.
CREATE INDEX lgd_villages_pincode_idx ON lgd_villages (pincode);

ANALYZE lgd_villages;
