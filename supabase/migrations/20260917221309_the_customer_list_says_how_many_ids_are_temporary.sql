-- The way into the Temporary IDs screen, from both customer lists.
--
-- A banner rather than another action in the app bar. Both of those bars were
-- deliberately stripped of duplicate entry points -- OW-004's comments record
-- three add-paths being removed from it, and AG-004's record a button that did
-- nothing at all -- so adding an icon back would undo somebody's work. A
-- banner also does what an icon cannot: it states the size of the job, and it
-- disappears when there is none.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('temporary_ids_pending', '{n} still have a temporary ID',
 '{n} మందికి ఇంకా తాత్కాలిక ID ఉంది')
ON CONFLICT (translation_key) DO NOTHING;
