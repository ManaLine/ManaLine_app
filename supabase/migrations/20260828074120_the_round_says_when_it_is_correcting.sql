-- A long press on a settled row opens the entry that is already there, so
-- the sheet has to say so: opened on a corrected row it otherwise looks
-- identical to a fresh collection, and an Agent who believes they are adding
-- one while they are replacing one finds out when the day is short.
--
-- 'already_collected_note' keeps its wording; what changed is that the dialog
-- carrying it no longer offers "Continue" -- there is no second entry to
-- continue to.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('update_amount', 'Update {amount}', '{amount} నవీకరించండి'),
  ('correcting_receipt',
   'Correcting receipt {receipt}. This replaces the entry; it does not add one.',
   'రసీదు {receipt} సవరించబడుతోంది. ఇది ఉన్న నమోదును మారుస్తుంది, కొత్తది చేర్చదు.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
