-- Keys for the Owner's Trash screen. english + telugu, matching the table:
-- every row carries those two and only 174 carry the other three.
insert into ui_translations (translation_key, english, telugu) values
  ('trash', 'Trash', 'ట్రాష్'),
  ('delete_forever', 'Delete Forever', 'శాశ్వతంగా తొలగించండి'),
  ('delete_forever_count_note',
   'Delete {count} records forever? This cannot be undone.',
   '{count} రికార్డులను శాశ్వతంగా తొలగించాలా? దీన్ని రద్దు చేయలేరు.'),
  ('delete_forever_loan_note',
   'A loan takes its collections, schedule and penalties with it.',
   'రుణంతో పాటు దాని వసూళ్లు, షెడ్యూల్ మరియు జరిమానాలు కూడా తొలగించబడతాయి.'),
  ('n_selected', '{count} Selected', '{count} ఎంచుకోబడ్డాయి'),
  ('n_of_m_selected', '{count} of {total} selected', '{total}లో {count} ఎంచుకోబడ్డాయి'),
  ('select_all', 'Select All', 'అన్నీ ఎంచుకోండి'),
  ('clear_selection', 'Clear', 'క్లియర్ చేయండి'),
  ('days_left_note', '{days} days left', '{days} రోజులు మిగిలి ఉన్నాయి'),
  ('nothing_has_been_deleted', 'Nothing has been deleted.', 'ఏదీ తొలగించబడలేదు.'),
  ('could_not_load_deleted_records',
   'Could not load deleted records: {error}',
   'తొలగించిన రికార్డులను లోడ్ చేయలేకపోయాము: {error}')
on conflict (translation_key) do nothing;
