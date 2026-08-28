-- "Today Summary" described figures that are not today's. Customers Visited,
-- Pending Collections and the rest belong to the ACCOUNT the Agent is
-- working -- opened on one day, handed to the Owner on another -- and
-- counting only today reset them to zero every morning while the account
-- itself stayed open.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('account_summary', 'Account Summary', 'ఖాతా సారాంశం')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
