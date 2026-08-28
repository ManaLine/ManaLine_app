-- Adding a customer and lending to them are two decisions, and the second
-- follows the first closely enough that the screen should carry it. One
-- button meant an Agent standing in front of a new borrower had to add them,
-- leave, find them again in a list of fifty-six, and start the loan there.
--
-- The header's + adds a customer now rather than an expense, at the Owner's
-- instruction: a round produces new borrowers far more often than receipts to
-- file. Recording an expense moved to the drawer, where it is still one tap
-- from wherever somebody is standing.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('add_only', 'Add Only', 'జోడించండి మాత్రమే'),
  ('add_and_issue_loan', 'Add & Issue Loan', 'జోడించి రుణం ఇవ్వండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
