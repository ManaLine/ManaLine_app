-- P4: put a ceiling on the storage buckets.
--
-- Every bucket had file_size_limit = NULL and allowed_mime_types = NULL, which
-- means "anything, any size". Loan photos are permanent and one accumulates
-- per loan, so that was the cost the subscription tiers are priced against,
-- running unbounded.
--
-- These limits are a BACKSTOP, not the mechanism. The client compresses first
-- (lib/shared/photo_compression.dart: 1024px/JPEG 75 for loan photos,
-- 800px/JPEG 70 for profile) and refuses anything it cannot bring under these
-- numbers, so a user gets "take it again" rather than a storage error. This is
-- what stops a future screen that forgets to compress from quietly undoing
-- that.
--
-- The limits deliberately match ManaPhotoPreset.hardLimitBytes exactly, and
-- test/photo_compression_test.dart asserts the same numbers. If they drift
-- apart, the client starts accepting photos the server rejects, and the
-- failure surfaces as an upload error with no useful message.
UPDATE storage.buckets
   SET file_size_limit = 1048576,                 -- 1 MB, = ManaPhotoPreset.loan
       allowed_mime_types = ARRAY['image/jpeg']
 WHERE id = 'live-photos';

UPDATE storage.buckets
   SET file_size_limit = 524288,                  -- 512 KB, = ManaPhotoPreset.profile
       allowed_mime_types = ARRAY['image/jpeg']
 WHERE id = 'profile-photos';

-- business-logos is uploaded once per business and displayed in the header. It
-- is not on the accumulating path, but it had no ceiling either, and a logo is
-- the one image a user is most likely to pick from their gallery at full
-- resolution. PNG is allowed here where it is not for photos: logos legitimately
-- have flat colour and transparency, which is what PNG is for.
UPDATE storage.buckets
   SET file_size_limit = 524288,                  -- 512 KB
       allowed_mime_types = ARRAY['image/jpeg', 'image/png']
 WHERE id = 'business-logos';

-- member-documents and dispute-documents are left unbounded ON PURPOSE.
-- They hold KYC and dispute evidence, which can legitimately be a multi-page
-- PDF, and the pricing model's answer for documents is to stop uploading them
-- at all -- storing a received/tick-mark flag instead. Capping them now would
-- break the current flow to save a cost that is about to be designed away.
