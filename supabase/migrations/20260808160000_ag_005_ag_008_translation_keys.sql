-- Applied via MCP; see ag_005_ag_008_translation_keys migration.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('draft_transactions', 'Draft Transactions', 'ముసాయిదా లావాదేవీలు'),
('no_open_drafts_note', 'No open drafts. Interrupted entries you Save Draft on will show up here.', 'తెరిచిన ముసాయిదాలు లేవు. మీరు ముసాయిదాగా సేవ్ చేసిన అంతరాయ ఎంట్రీలు ఇక్కడ కనిపిస్తాయి.'),
('created_note', 'Created {when}', '{when}న సృష్టించబడింది'),
('continue_draft', 'Continue Draft', 'ముసాయిదా కొనసాగించండి'),
('submit_label', 'Submit', 'సమర్పించండి'),
('discard', 'Discard', 'విస్మరించండి'),
('draft_submitted_note', 'Draft submitted.', 'ముసాయిదా సమర్పించబడింది.'),
('discard_draft', 'Discard Draft', 'ముసాయిదా విస్మరించండి'),
('discard_draft_note', 'This draft will be permanently removed. This cannot be undone.', 'ఈ ముసాయిదా శాశ్వతంగా తీసివేయబడుతుంది. దీన్ని రద్దు చేయలేరు.'),
('clear_all_notifications_question', 'Clear All Notifications?', 'అన్ని నోటిఫికేషన్‌లు క్లియర్ చేయాలా?'),
('clear_all_notifications_note', 'They will be removed from this list. Your loans, collections and settlements are not affected.', 'అవి ఈ జాబితా నుండి తీసివేయబడతాయి. మీ రుణాలు, వసూళ్లు మరియు సెటిల్‌మెంట్లపై ప్రభావం ఉండదు.'),
('clear_all', 'Clear All', 'అన్నీ క్లియర్ చేయండి'),
('open_target_not_available', 'Open target not available in this build yet.', 'ఈ బిల్డ్‌లో ఓపెన్ టార్గెట్ ఇంకా అందుబాటులో లేదు.'),
('notifications', 'Notifications', 'నోటిఫికేషన్‌లు'),
('mark_all_read', 'Mark All Read', 'అన్నీ చదివినట్లు గుర్తించండి'),
('unread_count_note', 'Unread ({count})', 'చదవనివి ({count})'),
('no_notifications', 'No notifications.', 'నోటిఫికేషన్‌లు లేవు.'),
('unread', 'Unread', 'చదవనివి'),
('open_label', 'Open', 'తెరవండి'),
('mark_read', 'Mark Read', 'చదివినట్లు గుర్తించండి')
ON CONFLICT (translation_key) DO NOTHING;
