-- Approving from the bell is the fewest taps there are: it already names the
-- Agent and the amount, so the Owner approves the figure they are looking at.
-- Returning one is not offered there -- it needs a reason the Agent can act
-- on, and a reason box does not belong in a notification list.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('accounts_handed_to_you', 'Accounts Handed To You', 'మీకు అప్పగించిన ఖాతాలు'),
  ('handed_over_amount_note', 'Handing over {amount}. Approving moves it to you and closes their account.',
   '{amount} అప్పగిస్తున్నారు. ఆమోదిస్తే అది మీకు వస్తుంది, వారి ఖాతా మూసివేయబడుతుంది.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
