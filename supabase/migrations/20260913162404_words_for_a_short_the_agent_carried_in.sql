-- The agent stage of the one-by-one door says one thing and asks one number.
--
-- "Short" on its own is the field word and means nothing to somebody reading
-- it cold, so the sentence says what it is: money this agent still owes on the
-- day the book came across. The note also says what it is NOT -- salary and
-- sadar are settled history and are not being asked for -- because the
-- Owner's whole reason for dropping attendance was that entering settled
-- history is wasted work.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('agent_opening_short', 'Short Carried In',
 'తీసుకువచ్చిన లోటు'),
('agent_opening_short_note',
 'If this agent still owes money from before the book came across, enter it here. Salary and sadar already settled are not asked for.',
 'పుస్తకం రాకముందు నుండి ఈ ఏజెంట్ ఇంకా డబ్బు బాకీ ఉంటే, దాన్ని ఇక్కడ నమోదు చేయండి. అప్పటికే సెటిల్ అయిన జీతం మరియు సదర్ అడగబడవు.'),
('amount_owed', 'Amount Owed', 'బాకీ ఉన్న మొత్తం'),
('no_short_to_record', 'Nothing Owed', 'ఏమీ బాకీ లేదు'),
('save_short', 'Save Short', 'లోటును సేవ్ చేయండి'),
('short_recorded', 'Short recorded: {amount}', 'లోటు నమోదైంది: {amount}'),
('short_outstanding_since', 'Outstanding since {date}',
 '{date} నుండి బాకీ ఉంది'),
('mark_short_recovered', 'Mark Recovered', 'తిరిగి వచ్చినట్లు గుర్తించండి'),
('short_marked_recovered', 'Marked as recovered.', 'తిరిగి వచ్చినట్లు గుర్తించబడింది.'),
('short_recovered_on', 'Recovered on {date}', '{date}న తిరిగి వచ్చింది')
ON CONFLICT (translation_key) DO NOTHING;
