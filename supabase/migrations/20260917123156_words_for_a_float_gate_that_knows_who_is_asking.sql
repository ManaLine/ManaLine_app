-- The float gate's words, in three versions, because there are three
-- different people in front of it.
--
-- WHAT THERE WAS: one sentence, the Agent's -- "Ask the Owner to add BF" --
-- shown to everybody, including the Owner. On the Stf book the Owner was also
-- the collecting agent, so the app invited them to send themselves a request.
-- They called it a blunder and they are right: a request needs somebody else
-- to grant it.
--
-- top_up_agent_bf is the Owner's remedy when the business HAS the cash: move
-- it into the collecting agent's hand, which is what app.grant_agent_bf does
-- and has always done. It was reachable from Workforce Management and never
-- from the place an Owner actually discovers they need it.
--
-- business_bf_empty_note is the Owner's answer when it does NOT. There is
-- nobody to ask -- they are the top of the book -- so the honest thing is to
-- name where cash enters one. Deliberately three routes and not a button: an
-- investor deposit, a collection, and the opening BF are three different
-- decisions and none of them belongs on a loan screen.
--
-- agent_not_set_up_note is a different sentence from an empty float on
-- purpose. An agent with no agent_bf_assignments row has never been given an
-- opening figure; they have not spent anything. Both cases are live on the
-- Stf book -- one agent of each -- which is why the RPC returns
-- has_assignment separately.
--
-- loan_needs_note replaces the red "Something went wrong. Please try again."
-- that a float refusal used to raise. Nothing went wrong. The till is empty,
-- which is a requirement that is not met, and those are not the same thing.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('loan_needs_note', 'This loan needs {needed}. {name} has {available}.',
 'ఈ రుణానికి {needed} అవసరం. {name} వద్ద {available} ఉంది.'),
('top_up_agent_bf', 'Top Up Their BF', 'వారి BF పెంచండి'),
('top_up_agent_bf_note',
 'Move cash from the business to {name} and carry on with this loan.',
 'వ్యాపారం నుండి {name}కి నగదు బదిలీ చేసి ఈ రుణాన్ని కొనసాగించండి.'),
('business_bf_empty_headline', 'The Business Has No Cash To Give',
 'ఇవ్వడానికి వ్యాపారం వద్ద నగదు లేదు'),
('business_bf_empty_note',
 'Business BF is {available}. Cash enters a book through an investor deposit, a collection, or the opening BF declared when the book was created.',
 'వ్యాపార BF {available}. పెట్టుబడిదారు డిపాజిట్, వసూలు, లేదా పుస్తకం సృష్టించినప్పుడు ప్రకటించిన ప్రారంభ BF ద్వారా నగదు పుస్తకంలోకి వస్తుంది.'),
('agent_not_set_up_note',
 '{name} has no opening BF yet. Give them one and they can start.',
 '{name}కి ఇంకా ప్రారంభ BF లేదు. ఒకటి ఇస్తే వారు ప్రారంభించవచ్చు.'),
('drafts', 'Drafts', 'డ్రాఫ్ట్‌లు')
ON CONFLICT (translation_key) DO NOTHING;
