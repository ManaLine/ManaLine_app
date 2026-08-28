-- The settlement screen asked the Agent to count their physical cash, tally
-- their cheques, and write remarks, then kept Submit disabled until the
-- arithmetic agreed -- for a figure the app already knows. One number now:
-- everything they are holding, in whatever form it arrived.
--
-- And the Owner can open an agent's ledger before the account is settled.
-- They could see the figure an agent held and nothing behind it, so "where
-- did that come from" had no answer until the settlement arrived with totals.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('total_amount', 'Total Amount', 'మొత్తం సొమ్ము'),
  ('total_amount_note',
   'Everything you are holding — cash, UPI, bank and cheque. Submitting hands it to the Owner; the money moves when they approve.',
   'మీ వద్ద ఉన్న మొత్తం — నగదు, UPI, బ్యాంక్, చెక్. సమర్పిస్తే యజమానికి వెళ్తుంది; వారు ఆమోదించినప్పుడు సొమ్ము బదిలీ అవుతుంది.'),
  ('view_transactions', 'View Transactions', 'లావాదేవీలు చూడండి')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
