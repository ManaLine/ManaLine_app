-- "replace word workforce with agents entirely".
--
-- The Owner's instruction, and they are right about the word: this app has
-- Agents. "Workforce" is a word from an org chart, and nobody working a
-- village book calls their collectors that. It appeared in three places an
-- Owner reads -- a drawer section, a screen title, and the sentence sending
-- somebody to that screen.
--
-- AN UPDATE, NOT AN INSERT, and the keys keep their names. A translation key
-- is not user-visible; renaming workforce_management to agent_management
-- would mean editing every call site AND every migration that inserted it,
-- to change nothing anybody sees. What matters is the string, and the string
-- is what moves. The name is left as a record of what it used to say.
--
-- 'role' and the filter it labels are new: OW-012's member list narrows by
-- role now, which is what let the C / A / I letters come off the rows. A
-- letter repeating what a dropdown above the list already states is two
-- answers to one question.
UPDATE ui_translations
   SET english = 'Agent Management',
       telugu  = 'ఏజెంట్ నిర్వహణ'
 WHERE translation_key = 'workforce_management';

UPDATE ui_translations
   SET english = 'Agents',
       telugu  = 'ఏజెంట్లు'
 WHERE translation_key = 'workforce';

UPDATE ui_translations
   SET english = 'No Active agents in this business yet — add one from Agent Management first. If you work this round yourself, add yourself as an agent.',
       telugu  = 'ఈ వ్యాపారంలో ఇంకా యాక్టివ్ ఏజెంట్లు లేరు — ముందుగా ఏజెంట్ నిర్వహణ నుండి ఒకరిని జోడించండి. ఈ రౌండ్‌ను మీరే చేస్తే, మిమ్మల్ని ఏజెంట్‌గా జోడించుకోండి.'
 WHERE translation_key = 'no_active_agents_note';

INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('role', 'Role', 'పాత్ర')
ON CONFLICT (translation_key) DO NOTHING;
