-- The second header line -- sort order, village, sort by, status -- on the
-- two screens that filter the same book. Sort ORDER is new: the round has
-- always sorted one way per mode, and "smallest first" is a real question at
-- the end of a day when what is left is the small ones.
--
-- Named by what they do rather than asc/desc: an Agent sorting by amount due
-- wants "highest first", not an arrow whose direction has to be decoded.
--
-- search_this_round is deliberately not 'search'. The header's magnifier
-- opens Universal Search across the whole business; this one narrows the list
-- underneath it. Two questions, two names, and no shared glyph.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('sort_order', 'Order', 'క్రమం'),
  ('highest_first', 'Highest First', 'ఎక్కువ మొదట'),
  ('lowest_first', 'Lowest First', 'తక్కువ మొదట'),
  ('search_this_round', 'Search This List', 'ఈ జాబితాలో వెతకండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
