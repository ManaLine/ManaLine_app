-- OW-013's BF panel called four rows "Owner BF" when two of the figures
-- were the Owner's own pot, one was what the agents were carrying, and one
-- was neither. Read beside the dashboard's business-cash total the panel
-- looked broken -- Rs 30 against Rs 2,69,220 -- when both were correct and
-- simply measured different pockets. These keys name the pocket.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('business_cash', 'Business Cash', 'వ్యాపార నగదు'),
  ('owner_cash_in_hand', 'Owner Cash In Hand', 'యజమాని వద్ద నగదు'),
  ('held_by_agents', 'Held By Agents', 'ఏజెంట్ల వద్ద ఉన్నది'),
  ('business_cash_total', 'Business Cash Total', 'మొత్తం వ్యాపార నగదు'),
  ('returning_already_counted_note',
   'Already counted above until the Owner approves each account.',
   'ప్రతి ఖాతాను యజమాని ఆమోదించే వరకు ఇది పైన లెక్కించబడి ఉంటుంది.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english, telugu = EXCLUDED.telugu;
