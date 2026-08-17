-- CW-004 now names the agent who carries the loan. A key that exists only in
-- the test fixture renders as a RAW KEY on a real handset, so it is added here
-- too.
INSERT INTO public.ui_translations (translation_key, english, telugu)
VALUES ('loan_given_by', 'Loan Given By', 'రుణం ఇచ్చినవారు')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
