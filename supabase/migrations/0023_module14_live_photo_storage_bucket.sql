-- =============================================================================
-- 0023 — Module 14: Live Photo Storage Bucket
-- =============================================================================
-- Closes a gap found while wiring OW-005's live photo step: no Supabase
-- Storage bucket exists anywhere in the schema, and even LR-004's own live
-- photo (persons.profile_photo_url) is captured client-side but never
-- actually uploaded — the field blocks Register but the bytes go nowhere.
-- This creates the one shared bucket both flows need.
--
-- Bucket is PRIVATE (not public) — these are fraud-prevention photos of
-- real people, not general-purpose assets. Path convention:
--   {business_id}/loans/{loan_id_placeholder_or_temp_id}.jpg   (loan photos)
--   {business_id}/persons/{person_id}.jpg                       (registration —
--     NOTE: at registration time the person doesn't have a business_id yet
--     in the Owner/Agent/Investor case, and Customers may register without
--     one too — see the "no business_id available at capture time" flag
--     below, not fully resolved here.)

INSERT INTO storage.buckets (id, name, public)
VALUES ('live-photos', 'live-photos', false)
ON CONFLICT (id) DO NOTHING;

-- Any authenticated user may INSERT (upload) into this bucket — path-level
-- ownership is NOT enforced by this policy (see caveat below), only that
-- the uploader is a genuine authenticated app user, not anonymous.
CREATE POLICY live_photos_authenticated_insert ON storage.objects
  FOR INSERT
  WITH CHECK (bucket_id = 'live-photos' AND auth.role() = 'authenticated');

-- Read access: any authenticated user with a business membership can read
-- any object under that business_id's prefix. This trusts the path prefix
-- (storage.foldername(name)[1]) as the business_id, matched against the
-- caller's own active memberships.
CREATE POLICY live_photos_business_member_select ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'live-photos'
    AND EXISTS (
      SELECT 1 FROM business_members bm
      WHERE bm.business_id::TEXT = (storage.foldername(name))[1]
        AND bm.person_id = app.current_person_id()
        AND bm.membership_status = 'Active'
    )
  );

-- CAVEAT (flagged, not resolved here): the INSERT policy above does NOT
-- verify the uploaded path's business_id prefix actually matches a
-- business the uploader belongs to — it only checks they're authenticated.
-- A malicious authenticated user could upload to another business's path
-- prefix (they still could not READ it back per the SELECT policy above,
-- and could not attach it to any loans/persons row they don't already have
-- write access to via the existing RLS on those tables — so this is a
-- storage-quota/pollution risk, not a data-confidentiality one). A fully
-- strict version would issue signed upload URLs via a SECURITY DEFINER
-- Edge Function instead of a client-side direct upload — out of scope for
-- this pass; flagged for a future hardening migration if this matters at
-- your actual usage scale.

-- REGISTRATION PATH GAP (flagged, not resolved here): at LR-004 registration
-- time, an Owner/Agent/Investor registrant has no business_id yet (they
-- create/join a business AFTER registering), so the {business_id}/persons/
-- {person_id}.jpg convention above doesn't cleanly apply to the
-- registration photo. This migration does not change auth_api_service's
-- register() Edge Function (out of reach from a Postgres migration) — that
-- Edge Function still needs its own update to accept and store the photo.
-- Not attempted here; flagged as a separate, pre-existing gap independent
-- of the loan-wizard fix this migration was written to support.
