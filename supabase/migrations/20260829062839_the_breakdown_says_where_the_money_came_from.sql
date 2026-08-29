-- Words for the settlement breakdown.
--
-- transfers_in/out are agent-to-agent cash movements; they are rare, and the
-- line is hidden when zero, but an agent who has passed money to a colleague
-- must see it leave rather than watch the total drop unexplained.
--
-- earned_not_held_note carries the awkward part in one sentence: interest and
-- fee are money the business made, not money the agent is carrying. It sits
-- below the total precisely so it cannot be read as part of it.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('transfers_in',  'Received From Agents', 'ఏజెంట్ల నుండి అందినది'),
  ('transfers_out', 'Given To Agents',      'ఏజెంట్లకు ఇచ్చినది'),
  ('earned_not_held_note',
   'Interest {interest} and processing fee {fees} are already earned at disbursement — not part of the cash you hold.',
   'వడ్డీ {interest} మరియు ప్రాసెసింగ్ ఫీజు {fees} రుణం ఇచ్చినప్పుడే ఆర్జించబడ్డాయి — మీ వద్ద ఉన్న నగదులో భాగం కాదు.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
