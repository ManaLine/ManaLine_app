-- Adding one person as two things, said in words that separate the two.
--
-- role_must_accept_note sits on the Agent and Investor rows of the picker,
-- not only in the message afterwards. An Owner ticking Agent is choosing to
-- SEND A REQUEST, and that is worth knowing before pressing Add rather than
-- discovering it in a snackbar.
--
-- added_as_roles_note and request_sent_as_roles_note are deliberately two
-- sentences rather than one. A Customer is in immediately; an Agent or
-- Investor sits at Pending Invitation until they answer. Reporting both as
-- "added" would tell an Owner their agent is on the book when that agent has
-- not replied, and they would find out by wondering why nothing was collected.
--
-- search_again_for_other_roles_note is an honest limit, not a feature. OW-014
-- registers a person and does not hand back who it made, so a second role
-- cannot be attached to them from here. Guessing which of several search
-- results is the person just created -- in a village where three people share
-- a name -- is how the wrong record gets a membership. Searching again and
-- adding is two taps and is never wrong.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('role_must_accept_note', 'They must accept before this starts',
 'ఇది ప్రారంభం కావడానికి ముందు వారు అంగీకరించాలి'),
('added_as_roles_note', 'Added as {roles}.', '{roles}గా జోడించబడింది.'),
('request_sent_as_roles_note', 'Request sent as {roles}.',
 '{roles}గా అభ్యర్థన పంపబడింది.'),
('search_again_for_other_roles_note',
 'Search for them again to add the other roles.',
 'ఇతర పాత్రలను జోడించడానికి వారిని మళ్లీ వెతకండి.')
ON CONFLICT (translation_key) DO NOTHING;
