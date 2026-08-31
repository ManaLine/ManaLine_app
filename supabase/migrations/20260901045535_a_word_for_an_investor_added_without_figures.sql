-- An existing person can now be added as an Investor before the amount and
-- ROI are known. The confirmation has to say what is still outstanding,
-- otherwise "Added" reads as finished and an investor sits on the roster with
-- no money against them and nobody wondering why.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('investor_added_record_investment_note',
   '{name} was added. Open their profile to record the investment.',
   '{name} జోడించబడ్డారు. పెట్టుబడిని నమోదు చేయడానికి వారి ప్రొఫైల్ తెరవండి.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
