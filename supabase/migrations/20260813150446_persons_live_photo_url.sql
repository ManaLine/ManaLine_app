-- =============================================================================
-- persons.live_photo_url — the registration capture, kept separate
-- =============================================================================
-- WHY A SECOND COLUMN: profile_photo_url held the live capture taken at
-- registration AND was the only photo column, so letting someone upload a
-- profile picture would have overwritten the live photo with no copy left.
-- For a lending app that is the wrong thing to lose: the live capture is
-- evidence of who actually registered, taken under camera-only conditions
-- (BR-036), while a profile picture is decoration the person chooses.
--
-- The two now mean different things and are written by different code:
--   live_photo_url    written ONCE by LR-007 First Login, never again
--   profile_photo_url the picture shown around the app; defaults to the live
--                     capture and is what an upload replaces
--
-- No CHECK enforces write-once — RLS on persons is self-update and cannot
-- express "this column only if currently null" without a trigger. The
-- guarantee here is that exactly one place writes it. If that stops being
-- true, add the trigger.
ALTER TABLE persons ADD COLUMN IF NOT EXISTS live_photo_url TEXT;

COMMENT ON COLUMN persons.live_photo_url IS
  'Live camera capture from registration (BR-036). Written once at first login, never overwritten. profile_photo_url may diverge from this when the person uploads their own picture.';

-- Backfill. Today profile_photo_url IS the live capture for every row that
-- has one — uploads do not exist yet, so there is nothing to mistake for a
-- user-chosen picture. 4 of 37 rows affected; verified 0 diverged after.
UPDATE persons
SET live_photo_url = profile_photo_url
WHERE live_photo_url IS NULL
  AND profile_photo_url IS NOT NULL;

-- Second source, for anyone whose live capture reached identity_documents
-- but not persons: the document row is written in the same block as the
-- profile_photo_url update in LR-007, so this only catches a partial failure
-- between the two. Zero rows today; harmless and correct if that changes.
UPDATE persons p
SET live_photo_url = d.file_url
FROM identity_documents d
WHERE d.person_id = p.person_id
  AND d.document_type = 'Photo'
  AND NOT d.is_archived
  AND p.live_photo_url IS NULL;
