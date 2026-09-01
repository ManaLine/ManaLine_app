-- Sri Tirumala Finance has two operating areas and both were removed. Its
-- agents read "No areas enabled for you yet. Contact your Owner." and the
-- Owner, opening Operating Areas, saw an empty list with no explanation --
-- because removed areas are filtered out of it, correctly, but silently.
-- Neither screen explained the other.
--
-- A removed area is not resurrected: it is kept only because past account
-- periods point at it. The way back to work is a fresh area, which the form
-- directly above this line already offers.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('only_removed_areas_note',
   'None being worked. {count} removed area(s) are kept for their past accounts. Add one above to start collecting again.',
   'ఏదీ పని చేయబడటం లేదు. {count} తీసివేసిన ప్రాంతాలు వాటి గత ఖాతాల కోసం ఉంచబడ్డాయి. మళ్లీ వసూలు ప్రారంభించడానికి పైన ఒకటి జోడించండి.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
