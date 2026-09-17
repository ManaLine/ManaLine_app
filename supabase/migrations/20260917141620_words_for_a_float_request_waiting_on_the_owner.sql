-- The words a BF request needs now that it is a decision rather than a
-- notice.
--
-- asked_for_float_note carries the CONSEQUENCE, not just the ask. An Owner
-- reading "asked for Rs 9,800" has to work out for themselves what happens
-- if they do nothing. An agent at zero float cannot issue a single loan, and
-- that is the fact which decides how urgent this is -- the notification
-- already said so and the action card was saying less than the notification.
--
-- float_requests_waiting sits with the other money decisions, above
-- invitations: an Agent waiting for float is standing in a village unable to
-- lend, which is a harder stop than anything below it.
--
-- 'grant' rather than 'approve', which the two cards above it use. Approving
-- a settlement accepts money that has already moved; granting float MOVES
-- money, out of the Owner's till and into somebody's hand. Two different acts
-- should not share a verb on the same screen.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('asked_for_float_note',
 'Asked for {amount} of float. They cannot issue any loan until it is granted.',
 '{amount} ఫ్లోట్ కోసం అడిగారు. అది మంజూరు అయ్యే వరకు వారు ఏ రుణమూ ఇవ్వలేరు.'),
('float_requests_waiting', 'Float Requests Waiting', 'ఫ్లోట్ అభ్యర్థనలు వేచి ఉన్నాయి'),
('grant', 'Grant', 'మంజూరు చేయండి')
ON CONFLICT (translation_key) DO NOTHING;
