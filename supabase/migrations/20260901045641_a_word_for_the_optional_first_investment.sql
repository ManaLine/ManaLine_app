-- The First Investment block on Add Existing Investor is optional now, and
-- the note under the heading says what happens if it is left blank. Without
-- it "Optional" raises the question it does not answer -- optional until
-- when?
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('first_investment_optional_note',
   'Leave blank to add them now and record the investment from their profile later.',
   'ఇప్పుడే జోడించి, పెట్టుబడిని తర్వాత వారి ప్రొఫైల్ నుండి నమోదు చేయడానికి ఖాళీగా వదిలేయండి.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
