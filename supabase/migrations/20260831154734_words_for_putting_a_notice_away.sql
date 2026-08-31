-- Long-pressing a notification now offers View or Ignore.
--
-- "Ignore" rather than "Delete" or "Dismiss": nothing is destroyed, and the
-- note under it says so, because a person deciding whether to press it needs
-- to know they are not throwing anything away.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('ignore', 'Ignore', 'పట్టించుకోవద్దు'),
  ('ignore_notice_note',
   'Puts it away. Nothing is deleted.',
   'దీన్ని పక్కన పెడుతుంది. ఏదీ తొలగించబడదు.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
