-- MANA LINE — 0042_dedupe_operating_areas_and_unique_constraint.sql
--
-- Confirmed via diagnostic: business 3dcf3578-7788-4226-ba2f-028619bee5e3
-- has "Panagallu (Rural)" added twice as separate operating_area rows
-- (6a261e42-9a24-4de2-a289-de40103169e5 and
-- 0d5624e5-cb59-412b-a69a-b2a3e7acff43), same location_id. Confirmed
-- neither has any dependent account_periods — safe to delete one outright,
-- no cascading/merge needed.
--
-- Root cause: operating_areas had no UNIQUE constraint on
-- (business_id, location_id) — nothing stopped the same village being
-- added twice to one business (most likely a double-click on "Add Area").
-- This migration both cleans up the one confirmed duplicate AND adds the
-- constraint so it can't happen again for anyone.

-- Delete the later-created duplicate, keep the original.
DELETE FROM operating_areas
WHERE operating_area_id = '0d5624e5-cb59-412b-a69a-b2a3e7acff43';

-- Prevent this from recurring, for any business, going forward.
ALTER TABLE operating_areas
  ADD CONSTRAINT uq_operating_areas_business_location UNIQUE (business_id, location_id);

COMMENT ON CONSTRAINT uq_operating_areas_business_location ON operating_areas IS
  'Added after finding the same village could be added twice to one business (no constraint existed). One village = one operating_area per business.';
