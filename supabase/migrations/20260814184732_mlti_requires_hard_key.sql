-- P1 of the identity spec: a temporary identity must carry at least one key
-- that cannot be duplicated.
--
-- WHY: persons has exactly three unique columns — mlid, aadhaar_number and
-- mobile_number. The last two are nullable, and full_name has no index of any
-- kind, so a person holding neither Aadhaar nor mobile is held together by
-- free text that nothing ever compares. That is the whole duplicate exposure,
-- and it is the cheapest half of it to close.
--
-- MLTI only. MLPI is the permanent, Aadhaar-verified identity and already
-- cannot reach this state. Self-registration at LR-004 has required Aadhaar
-- since the Global Rules addendum of 2026-07-20; what this constrains is the
-- Owner-only pre-existing path at OW-014 and bulk onboarding, which skip
-- Aadhaar on purpose because they record people who predate the app.
--
-- Deleted accounts are exempt, and that exemption is load-bearing rather than
-- tidy: app.anonymise_person sets mobile_number and aadhaar_number to NULL by
-- design. Without this carve-out, anonymising an MLTI person would fail the
-- constraint and the right-to-erasure path would break.
--
-- All 37 persons on record satisfy this today, MLTI included, so it validates
-- without a backfill.
ALTER TABLE persons
  ADD CONSTRAINT persons_mlti_needs_hard_key CHECK (
    mlid_type <> 'MLTI'
    OR account_status = 'Deleted'
    OR aadhaar_number IS NOT NULL
    OR mobile_number IS NOT NULL
  );
