-- Dropping the LGD code columns before the import, for space.
--
-- This project is on the 500 MB tier, and the codes buy nothing here. The
-- lookup is pincode → village → mandal/district/state; no code is ever read,
-- joined on, or displayed. Removing them also collapses ~10,000 further
-- duplicate rows that differed only by code, taking the import from 778,833 to
-- 768,529.
--
-- What is given up: if LGD renames a village, there is no stable key to
-- re-match on. Rebuildable from the source workbook, which is kept outside the
-- repo, so nothing is lost permanently.
ALTER TABLE lgd_villages
  DROP COLUMN village_code,
  DROP COLUMN subdistrict_code,
  DROP COLUMN district_code,
  DROP COLUMN state_code;
