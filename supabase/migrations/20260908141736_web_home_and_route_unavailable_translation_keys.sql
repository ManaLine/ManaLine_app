-- The website has two places that showed raw translation keys instead of
-- words: the Agent's "get the app" card on ManaWebHomeScreen (an Agent's
-- whole job is field work, so the web build has nothing else to offer
-- them -- this card IS the destination, not an apology), the same card's
-- secondary form on the other three roles, and the four-key error screen
-- manaWebRouter's errorBuilder shows for a bookmarked/typed URL that only
-- exists in the app (web_router.dart).
--
-- Three-column shape (translation_key, english, telugu), matching
-- 20260908062428_ledger_table_description_column_header.sql -- not the
-- five-column shape some earlier migrations use. Telugu is left NULL
-- rather than guessed, the same convention that migration documents: an
-- unlisted/NULL language column means "not supplied yet," and
-- TranslationCache falls back to English for it, never to a raw key.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('web_home_agent_app_title', 'Get MANA LINE On Your Phone', NULL),
('web_home_agent_app_body', 'Collections, routes and closing the day all happen in the MANA LINE app. Install it and sign in with your usual mobile number to get going.', NULL),
('web_home_secondary_app_title', 'Also Available On Mobile', NULL),
('web_home_secondary_app_body', 'Everything here works on your phone too, in the MANA LINE app. Install it whenever it suits you.', NULL),
('web_route_unavailable_title', 'This Screen Is In The App', NULL),
('web_route_unavailable_body', 'This page only exists in the MANA LINE app on your phone. Head back to your account here, or get the app to see everything.', NULL),
('web_route_unavailable_action', 'Get The App', NULL),
('web_route_unavailable_back', 'Back To Home', NULL)
ON CONFLICT (translation_key) DO NOTHING;
