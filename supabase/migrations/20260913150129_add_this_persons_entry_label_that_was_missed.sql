-- The investor stage's own button has been rendering a RAW KEY since it was
-- built, and shipped that way in build 10.
--
-- add_this_persons_entry came out of Plan 6's own table of labels, was used in
-- the Task 2 screen, and the migration for it was never written. ref.t() falls
-- back to the key when there is no row, so the button read
-- "add_this_persons_entry" on a real handset.
--
-- This is the exact failure that put "use_my_location" in front of live users:
-- a key that exists only in Dart. It was caught this time by a test that scans
-- the door's ref.t() calls against the migrations, rather than by somebody
-- opening the screen -- which is the only reliable way, since noticing one raw
-- key among dozens of correct ones is not something a person reliably does.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('add_this_persons_entry', 'Add This Person''s Entry',
 'ఈ వ్యక్తి నమోదును జోడించండి')
ON CONFLICT (translation_key) DO NOTHING;
