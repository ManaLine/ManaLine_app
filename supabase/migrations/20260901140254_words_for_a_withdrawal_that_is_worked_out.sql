-- A withdrawal is an amount now, and the split -- unpaid interest first, then
-- principal -- is worked out rather than chosen. Both screens have to say
-- what the amount will actually do, because that is what the investor and the
-- Owner used to be choosing wrongly.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('withdrawal_split_note',
   '{interest} from unpaid interest, {principal} from principal.',
   'చెల్లించని వడ్డీ నుండి {interest}, అసలు నుండి {principal}.'),
  ('pay_out_confirm_note',
   'Pay {amount}? It comes out of unpaid interest first, then principal.',
   '{amount} చెల్లించాలా? ఇది ముందుగా చెల్లించని వడ్డీ నుండి, ఆ తర్వాత అసలు నుండి తీసుకోబడుతుంది.'),
  ('withdrawals_waiting', 'Withdrawals Waiting On You',
   'మీ కోసం వేచి ఉన్న ఉపసంహరణలు'),
  ('wants_to_withdraw_note', 'Wants to withdraw {amount}',
   '{amount} ఉపసంహరించుకోవాలనుకుంటున్నారు')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
