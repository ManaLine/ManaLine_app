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
