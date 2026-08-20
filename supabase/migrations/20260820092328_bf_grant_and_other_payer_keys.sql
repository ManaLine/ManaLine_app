INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('bf_given',          'BF Given',           'బీఎఫ్ ఇచ్చారు'),
  ('bf_given_to',       'BF Given To',        'బీఎఫ్ ఇచ్చినది'),
  ('someone_else_paid', 'Someone Else Paid',  'వేరొకరు చెల్లించారు'),
  ('who_paid_optional', 'Who Paid (Optional)','ఎవరు చెల్లించారు (ఐచ్ఛికం)')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english, telugu = EXCLUDED.telugu;
