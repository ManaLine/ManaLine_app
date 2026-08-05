-- admin_deletion_log.deleted_by was NOT NULL with a FK to persons, which
-- assumes every deletion has a human behind it. The automatic 90-day purge has
-- none: it runs from pg_cron.
--
-- The person's own id is not a substitute. For a hard delete their persons row
-- is removed moments later, and the FK is RESTRICT, so the log entry would
-- block the very deletion it is recording.
--
-- NULL now means "the system did this, on a schedule" — which is exactly what
-- happened, and is more honest than attributing it to an administrator who was
-- not involved. `reason` carries the explanation either way.
ALTER TABLE admin_deletion_log ALTER COLUMN deleted_by DROP NOT NULL;

COMMENT ON COLUMN admin_deletion_log.deleted_by IS
  'The Platform Admin who performed the deletion. NULL for automatic actions '
  'such as app.purge_due_accounts(), which runs on a schedule with no actor.';

-- NOTE, found while doing this and deliberately NOT fixed here: an admin
-- deleting THEIR OWN account through app.admin_delete_person would insert a
-- log row pointing at themselves and then try to delete that person, which the
-- RESTRICT foreign key would refuse. Pre-existing, unrelated to the purge, and
-- worth its own fix rather than being bundled into this one.
