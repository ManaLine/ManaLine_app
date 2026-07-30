-- MANA LINE — Test Data Cleanup Script (not a numbered migration — run
-- manually, on demand, during testing only. NEVER run this against
-- production.)
--
-- WHY TRUNCATE CASCADE INSTEAD OF MANUAL ORDERED DELETES: persons has
-- 30+ tables transitively referencing it (business_members -> customers/
-- agents/investors -> loans -> collections/loan_schedule -> ... and
-- deeper). Hand-ordering that many DELETE statements by dependency depth
-- is exactly the kind of thing that's easy to get subtly wrong — miss one
-- table, hit an FK violation, or worse, get the order wrong silently in a
-- way that doesn't error but leaves orphaned rows. Postgres's own
-- TRUNCATE ... CASCADE walks the real FK graph itself, guaranteed
-- correct regardless of how deep it goes — every table with a foreign
-- key pointing at `persons` (directly or transitively through
-- businesses/business_members/customers/agents/etc.) gets emptied
-- automatically, in the right order, in one atomic operation.
--
-- WHAT THIS DOES NOT TOUCH: `locations` (village/pincode master data —
-- has no FK relationship to persons at all, so CASCADE never reaches it;
-- your seeded/imported village data is completely safe).
--
-- WHAT THIS DOES TOUCH: literally everyone and everything — every person,
-- every business, every loan, every collection, every OTP record, every
-- platform_admin row. This is a full wipe, not selective. If you want to
-- KEEP a specific admin account (e.g. yourself), re-run the admin-insert
-- script AFTER this, not before.

BEGIN;

TRUNCATE TABLE persons, businesses RESTART IDENTITY CASCADE;

COMMIT;

-- Verify it's actually empty:
-- SELECT count(*) FROM persons;      -- should be 0
-- SELECT count(*) FROM businesses;   -- should be 0
-- SELECT count(*) FROM locations;    -- should be unchanged (your seed data)
