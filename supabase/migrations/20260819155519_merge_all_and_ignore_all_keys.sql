-- Bulk actions on the identity duplicate review. One chip pair per flagged
-- row is fine for three rows; the live book flagged 55, which is where an
-- Owner gives up or mis-taps.
INSERT INTO ui_translations (translation_key, english, telugu)
VALUES
  ('merge_all',  'Merge All (Skip)',      'అన్నీ విలీనం (దాటవేయి)'),
  ('ignore_all', 'Ignore All (Import)',   'అన్నీ పట్టించుకోవద్దు (దిగుమతి)')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english,
  telugu  = EXCLUDED.telugu;
