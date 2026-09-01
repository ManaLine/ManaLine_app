-- Seven rows in this database were each a working link to a private file,
-- good for a year, usable by anyone who ever saw them.
--
-- The upload helpers signed their URLs for 60*60*24*365 seconds and the whole
-- signed URL was stored: loans.live_photo_url, persons.profile_photo_url,
-- businesses.logo_url, customer_documents.file_url. A Supabase signed URL
-- carries its own authorisation -- no login, no RLS, no revocation short of
-- deleting the object. The live photos are pictures of people's faces taken
-- as fraud evidence at their own doorstep, and customer_documents holds
-- identity documents.
--
-- The app stores the object PATH now, which authorises nothing on its own,
-- and mints a link lasting minutes when a screen actually needs to show the
-- image. This converts what is already there.
--
-- The path is recoverable from the URL: Supabase signs as
--   /storage/v1/object/sign/<bucket>/<path>?token=...
-- so everything after the bucket segment, minus the query, is the path.
-- Deterministic, which is why this is a data fix and not a re-upload.
--
-- 'migrated:pre-existing-loan:no-live-photo' is left exactly as it is: it is a
-- sentinel for loans imported from the paper book where no photo was ever
-- taken, not a link to anything.
--
-- The tokens in those URLs stay valid until they expire on their own -- this
-- cannot recall a link somebody already copied. What it stops is the app
-- handing out new ones, and it takes the standing copies out of the database.
UPDATE loans
   SET live_photo_url = split_part(
         substring(live_photo_url from '/object/sign/[^/]+/(.*)$'), '?', 1)
 WHERE live_photo_url LIKE 'http%'
   AND live_photo_url LIKE '%/object/sign/%';

UPDATE persons
   SET profile_photo_url = split_part(
         substring(profile_photo_url from '/object/sign/[^/]+/(.*)$'), '?', 1)
 WHERE profile_photo_url LIKE 'http%'
   AND profile_photo_url LIKE '%/object/sign/%';

UPDATE businesses
   SET logo_url = split_part(
         substring(logo_url from '/object/sign/[^/]+/(.*)$'), '?', 1)
 WHERE logo_url LIKE 'http%'
   AND logo_url LIKE '%/object/sign/%';

UPDATE customer_documents
   SET file_url = split_part(
         substring(file_url from '/object/sign/[^/]+/(.*)$'), '?', 1)
 WHERE file_url LIKE 'http%'
   AND file_url LIKE '%/object/sign/%';

COMMENT ON COLUMN loans.live_photo_url IS
  'Object path inside the live-photos bucket, NOT a URL. A link is signed on '
  'demand and expires in minutes -- see ManaStoredFile. May also hold the '
  'sentinel migrated:pre-existing-loan:no-live-photo for imported loans.';
COMMENT ON COLUMN persons.profile_photo_url IS
  'Object path inside the profile-photos bucket, NOT a URL. See '
  'loans.live_photo_url.';
COMMENT ON COLUMN businesses.logo_url IS
  'Object path inside the business-logos bucket, NOT a URL. See '
  'loans.live_photo_url.';
COMMENT ON COLUMN customer_documents.file_url IS
  'Object path inside the customer-documents bucket, NOT a URL. See '
  'loans.live_photo_url.';
