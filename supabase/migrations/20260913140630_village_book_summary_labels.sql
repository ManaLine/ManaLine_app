-- Reconciling a village against the paper book it came from.
--
-- The Owner enters a pre-existing book village by village -- 200 customers is
-- not a 200-screen wall, it is a dozen villages of about seventeen -- and after
-- each village checks these three figures against the page in front of them.
--
-- RUNNING and STRUCK are the Owner's own words and their own split. Running is
-- money still moving; struck is money nobody has paid in the chosen span, and
-- the two always add to the total. struck_customers_note names them rather than
-- counting them, because a figure an Owner cannot act on is one they will
-- ignore.
--
-- not_in_any_operating_area is the group that stops somebody disappearing. A
-- customer whose village is not one this business works would otherwise be
-- absent from every village group with nothing to say so, which with two
-- hundred of them is how a person goes missing from their own book. It is also
-- the app telling the Owner an operating area is missing.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('village_book', 'Village Book', 'గ్రామ పుస్తకం'),
('total_balance', 'Total Balance', 'మొత్తం బ్యాలెన్స్'),
('running_amount', 'Running', 'నడుస్తున్నది'),
('struck_amount', 'Struck', 'ఆగిపోయినది'),
('struck_customers_note', '{count} customers', '{count} కస్టమర్లు'),
('not_in_any_operating_area', 'Not in any operating area',
 'ఏ ఆపరేటింగ్ ప్రాంతంలోనూ లేదు'),
('customers_in_village', '{count} customers', '{count} కస్టమర్లు'),
('not_recovered_since', 'Not recovered since', 'నుండి వసూలు కాలేదు'),
('last_n_months', 'Last {n} months', 'గత {n} నెలలు'),
('choose_a_date', 'Choose a date', 'తేదీని ఎంచుకోండి'),
('nothing_entered_for_this_village_yet',
 'Nothing entered for this village yet.', 'ఈ గ్రామానికి ఇంకా ఏమీ నమోదు కాలేదు.')
ON CONFLICT (translation_key) DO NOTHING;
