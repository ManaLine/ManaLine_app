-- Reopening a migration asked for a free-text reason and nothing else.
--
-- The reason goes into the audit log, so it is the only record of WHY a
-- started business was unlocked to take pre-existing records again. A blank
-- box in a hurry produces "correction" and "mistake", which audits to nothing.
--
-- Six choices plus Other, each one a thing the migration actually captures --
-- investors, agents, customers with their loans, BF and line balance. Other
-- keeps the free-text box, because a list that cannot say "none of these"
-- pushes people into picking the nearest wrong answer.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('reopen_reason_label', 'Reason for reopening', 'తిరిగి తెరవడానికి కారణం'),
('reopen_reason_missed_entry', 'A customer or loan from the old book was missed',
 'పాత పుస్తకంలోని కస్టమర్ లేదా రుణం మిస్ అయ్యింది'),
('reopen_reason_wrong_amount', 'A loan amount or repayment figure was entered wrong',
 'రుణ మొత్తం లేదా తిరిగి చెల్లింపు సంఖ్య తప్పుగా నమోదైంది'),
('reopen_reason_investor_principal', 'An investor''s opening principal was wrong or missing',
 'పెట్టుబడిదారు ప్రారంభ అసలు మొత్తం తప్పు లేదా లేదు'),
('reopen_reason_agent', 'An agent was missed or assigned to the wrong area',
 'ఏజెంట్ మిస్ అయ్యారు లేదా తప్పు ప్రాంతానికి కేటాయించబడ్డారు'),
('reopen_reason_started_early', 'Business was started before entry was finished',
 'నమోదు పూర్తి కాకముందే వ్యాపారం ప్రారంభించబడింది'),
('reopen_reason_duplicate', 'A duplicate entry needs correcting',
 'నకిలీ నమోదును సరిచేయాలి'),
('reopen_reason_other', 'Other', 'ఇతర')
ON CONFLICT (translation_key) DO NOTHING;
