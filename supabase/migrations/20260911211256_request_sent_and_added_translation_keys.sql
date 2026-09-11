-- The Owner needs to see WHICH of the two things just happened.
--
-- Adding an Agent or an Investor now sends a request they must accept;
-- adding a Customer puts them in straight away. Saying "Added" for both
-- would tell the Owner an Agent is working for them when that Agent has not
-- answered yet.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('request_sent_note', 'Request sent. They will appear once they accept.',
 'అభ్యర్థన పంపబడింది. వారు అంగీకరించిన తర్వాత కనిపిస్తారు.'),
('added_to_business_note', 'Added to this business.',
 'ఈ వ్యాపారానికి జోడించబడింది.')
ON CONFLICT (translation_key) DO NOTHING;
