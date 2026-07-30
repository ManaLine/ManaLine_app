-- MANA LINE — 0040_preferred_language_and_business_logos.sql
--
-- Part 1: persons.preferred_language — never actually existed. The
-- ManaLanguageSelector widget's own doc comment claimed persistence to
-- "the locked schema's preferred_language_enum," but neither the column
-- nor the enum was ever created — Settings' language selector has been
-- session-scoped only until now. All 5 already-defined UI languages
-- (English/Telugu/Hindi/Tamil/Kannada — ManaLanguage enum) made available
-- for live testing, per explicit instruction.
--
-- Part 2: business-logos bucket — businesses.logo_url column already
-- existed and is already displayed (ow_012's business list avatars), but
-- no upload path was ever built. New private bucket, Owner-only
-- read/write scoped to businesses they own.

CREATE TYPE preferred_language_enum AS ENUM ('English', 'Telugu', 'Hindi', 'Tamil', 'Kannada');

ALTER TABLE persons ADD COLUMN preferred_language preferred_language_enum NOT NULL DEFAULT 'English';

COMMENT ON COLUMN persons.preferred_language IS
  'All 5 UI languages available for live testing. Set via Settings screen (self-update, persons_self_update RLS) — no separate RPC needed, an authenticated person may freely update their own row.';

-- --- business-logos bucket ---------------------------------------------

INSERT INTO storage.buckets (id, name, public)
VALUES ('business-logos', 'business-logos', false)
ON CONFLICT (id) DO NOTHING;

-- Owner may upload/update a logo for a business they own. Path convention:
-- '<business_id>/logo.jpg' (or .png) — enforced by path prefix, not by
-- verifying business_id format itself (storage.foldername parses text).
CREATE POLICY business_logos_owner_write ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'business-logos'
    AND EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.business_id::TEXT = (storage.foldername(name))[1]
        AND b.owner_person_id = app.current_person_id()
    )
  );

CREATE POLICY business_logos_owner_update ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'business-logos'
    AND EXISTS (
      SELECT 1 FROM businesses b
      WHERE b.business_id::TEXT = (storage.foldername(name))[1]
        AND b.owner_person_id = app.current_person_id()
    )
  );

-- Read: any active member of the business (not just the Owner) can see
-- its own logo — matches how live-photos' read policy is scoped.
CREATE POLICY business_logos_member_select ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'business-logos'
    AND EXISTS (
      SELECT 1 FROM business_members bm
      WHERE bm.business_id::TEXT = (storage.foldername(name))[1]
        AND bm.person_id = app.current_person_id()
        AND bm.membership_status = 'Active'
    )
  );

-- --- profile-photos bucket -----------------------------------------------
-- For LR-004's registration-captured photo -> persons.profile_photo_url.
-- Path convention: '<person_id>/photo.jpg'. Self-scoped only (a person's
-- own profile photo) — deliberately narrower than business-logos, no
-- "business partner can view" case needed for a personal photo.

INSERT INTO storage.buckets (id, name, public)
VALUES ('profile-photos', 'profile-photos', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY profile_photos_self_write ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'profile-photos'
    AND (storage.foldername(name))[1] = app.current_person_id()::TEXT
  );

CREATE POLICY profile_photos_self_update ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'profile-photos'
    AND (storage.foldername(name))[1] = app.current_person_id()::TEXT
  );

CREATE POLICY profile_photos_self_select ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'profile-photos'
    AND (storage.foldername(name))[1] = app.current_person_id()::TEXT
  );
