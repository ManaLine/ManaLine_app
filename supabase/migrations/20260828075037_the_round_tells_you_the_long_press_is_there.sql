-- Correcting an entry is a long press on a settled row. A gesture nobody is
-- told about is a gesture nobody uses, so the row says so -- and a long press
-- on a door recorded as "no collection", which has a visit but no entry to
-- change, says that rather than doing nothing.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('long_press_to_correct', 'Long press to correct this entry',
   'ఈ నమోదును సవరించడానికి నొక్కి పట్టుకోండి'),
  ('nothing_to_correct', 'There is no collection entry here to correct.',
   'ఇక్కడ సవరించడానికి వసూలు నమోదు ఏదీ లేదు.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
