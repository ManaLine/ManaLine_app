-- Universal Search read business_members without selecting membership_status
-- at all, so EVERY row became a live role.
--
-- An Agent whose invitation is still Pending Invitation looked exactly like an
-- Agent who had accepted: same tappable row, same chevron. Send a request,
-- search the person again, and the app told you they were already in -- so the
-- honest thing to do next was send it again.
--
-- Removed is the sharper half of the same bug. Somebody taken off the business
-- still rendered as an Agent, which is the app saying a person has reach into
-- a book they were deliberately removed from.
--
-- Three states, three different sentences now: Active is a role you can open,
-- a pending one says what was asked and that it is still waiting, and anything
-- ended (Removed, Suspended, Temporarily Disabled) is not a membership and is
-- not drawn as one. Every label read out of membership_status_enum:
-- ('Pending Invitation','Pending Acceptance','Active','Temporarily Disabled',
--  'Suspended','Removed','Pending Approval').
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('request_sent_as', 'Request sent as {role} — waiting for them to accept.',
 'అభ్యర్థన {role}గా పంపబడింది — వారు అంగీకరించడానికి వేచి ఉంది.')
ON CONFLICT (translation_key) DO NOTHING;
