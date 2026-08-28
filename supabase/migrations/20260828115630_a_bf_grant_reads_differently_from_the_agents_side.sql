-- "BF Given To Karri Siri Manikanta Reddy", in Karri Siri Manikanta Reddy's
-- own history, drawn grey with a sideways arrow.
--
-- The event is the business's: cash moving from the Owner's pocket to an
-- Agent's, a transfer that changes no total -- which is exactly right in the
-- Owner's ledger. Read from inside the Agent's own book it is the opposite:
-- money arriving, and it should be green like every other thing that arrives.
-- It also named the Agent to themselves.
--
-- No counterparty on this one: the label says what happened, and the only
-- other party is the business the Agent is already inside.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('bf_received', 'BF Received', 'BF అందింది')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
