-- The outbox, in words an agent standing at a door can read.
--
-- collection_queued_note is the sentence that replaces "Something went wrong."
-- The collection is NOT lost -- it is on the phone, it will go when there is a
-- signal, and the customer's money is accounted for. Saying "went wrong" about
-- that would send an agent back to a customer to collect twice.
--
-- outbox_sending_locked_note explains a restriction rather than just imposing
-- it. While an attempt is in flight nobody can tell "never arrived" from
-- "arrived, reply lost", and a change made in that window could reach the
-- server under a key it has already answered -- which would return the old
-- answer and silently discard the correction. Buttons that simply vanish read
-- as a bug; a sentence reads as a reason.
--
-- discard_queued_collection_note names the customer and the amount, because
-- deleting a queued entry means that payment is recorded nowhere and the agent
-- is the only person who knows it happened.
--
-- nothing_waiting_to_be_saved is phrased as good news. An empty outbox is the
-- normal state and should not read as an absence or an error.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('waiting_to_be_saved', 'Waiting to be Saved',
 'సేవ్ కావడానికి వేచి ఉంది'),
('nothing_waiting_to_be_saved', 'Everything has been saved.',
 'అంతా సేవ్ చేయబడింది.'),
('collection_queued_note',
 'Saved on this phone. It will go through when you are back online.',
 'ఈ ఫోన్‌లో సేవ్ చేయబడింది. మీరు మళ్లీ ఆన్‌లైన్‌కు వచ్చినప్పుడు ఇది వెళ్తుంది.'),
('outbox_waiting', 'Waiting', 'వేచి ఉంది'),
('outbox_sending', 'Sending', 'పంపుతోంది'),
('outbox_refused', 'Not saved', 'సేవ్ కాలేదు'),
('outbox_stuck', 'Still trying', 'ఇంకా ప్రయత్నిస్తోంది'),
('outbox_sending_locked_note',
 'Being sent now — it can be changed again if it does not go through.',
 'ఇప్పుడు పంపబడుతోంది — అది వెళ్లకపోతే మళ్లీ మార్చవచ్చు.'),
('discard_queued_collection', 'Discard This Collection?',
 'ఈ వసూలును తొలగించాలా?'),
('discard_queued_collection_note',
 '{amount} from {name} will not be recorded anywhere.',
 '{name} నుండి {amount} ఎక్కడా నమోదు కాదు.'),
('discard', 'Discard', 'తొలగించండి'),
('collected_amount_field', 'Collected Amount', 'వసూలు చేసిన మొత్తం')
ON CONFLICT (translation_key) DO NOTHING;
