-- A notification could be marked read and nothing else.
--
-- Read is not the same as dealt with. The bell kept every notice that had
-- ever arrived, so the list only grew, and the one gesture available -- tap
-- to mark read -- greyed a row without removing it. There was no way to say
-- "I have seen this, put it away", which is what people were reaching for
-- when they long-pressed and got nothing.
--
-- dismissed_at rather than a boolean: it records WHEN somebody put it away,
-- which is worth having when a person says they were never told something.
-- Nothing is deleted -- a dismissed notice is still there to be read back.
--
-- No RLS change. notifications_self_update_read already scopes UPDATE to
-- `recipient_person_id = app.current_person_id()` for both USING and WITH
-- CHECK, so a person can dismiss their own notices and no one else's.
ALTER TABLE notifications
  ADD COLUMN dismissed_at TIMESTAMP;

COMMENT ON COLUMN notifications.dismissed_at IS
  'Set when the recipient put this notice away. Read is not dealt with: a '
  'notice can be read and still waiting, or dismissed without being opened. '
  'Dismissed rows are hidden from the bell, never deleted.';

CREATE INDEX IF NOT EXISTS idx_notifications_live
  ON notifications (recipient_person_id, created_at DESC)
  WHERE dismissed_at IS NULL;
