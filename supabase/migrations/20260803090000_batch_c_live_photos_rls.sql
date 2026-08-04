-- =============================================================================
-- BATCH C (1/3) — live-photos: path-aware INSERT + missing UPDATE (#14)
-- =============================================================================
-- WHAT THIS FILE DOES:
--   The INSERT policy on live-photos was deliberately loose at launch time
--   (any authenticated user could upload to any prefix), flagged as a
--   "storage-quota/pollution risk, not a data-confidentiality one." It also
--   lacked an UPDATE policy, which means the client's `upsert: true`
--   (loan_wizard_state uploads the same photo twice on re-capture) silently
--   fails when the row already exists.
--
--   Both problems are fixed by making the policies path-aware (the same
--   `business_id`-from-first-path-segment check the SELECT policy already
--   uses). Registration photos are unaffected: they go to the self-scoped
--   `profile-photos` bucket (0040), not to `live-photos`.
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS live_photos_authenticated_insert ON storage.objects;

CREATE POLICY live_photos_business_member_insert ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'live-photos'
    AND EXISTS (
      SELECT 1 FROM business_members bm
      WHERE bm.business_id::TEXT = (storage.foldername(name))[1]
        AND bm.person_id = app.current_person_id()
        AND bm.membership_status = 'Active'
    )
  );

COMMENT ON POLICY live_photos_business_member_insert ON storage.objects IS
  'M14 fix: only an active member of the business in the path prefix can upload there — closes the cross-tenant write path the original policy left open.';

-- New UPDATE policy so upsert:true (loan re-captures, retries) works.
CREATE POLICY live_photos_business_member_update ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'live-photos'
    AND EXISTS (
      SELECT 1 FROM business_members bm
      WHERE bm.business_id::TEXT = (storage.foldername(name))[1]
        AND bm.person_id = app.current_person_id()
        AND bm.membership_status = 'Active'
    )
  );

COMMENT ON POLICY live_photos_business_member_update ON storage.objects IS
  'M14 fix: allows upsert:true (loan re-capture) without error. Same gate as the INSERT policy.';
