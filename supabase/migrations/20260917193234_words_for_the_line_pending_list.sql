-- The Line Pending List (design document 2.6.1.1) and its four filters.
--
-- PENDING IS COUNTED IN THE LOAN'S OWN UNIT, so the overdue figure is written
-- with a placeholder for the unit rather than as "{n} weeks" -- two of the
-- live loans are Monthly and two are Daily, and calling a Daily loan 205 weeks
-- behind would be wrong by a factor of seven.
--
-- 'never_paid' is its own string rather than an empty cell. A customer who has
-- never paid anything is the most serious row on the list, and a blank reads
-- as missing data.
--
-- 'total_outstanding' and 'all_dates' already existed; ON CONFLICT DO NOTHING
-- keeps the older wording, which is right -- one word per concept.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('line_pending_list',   'Line Pending List',    'లైన్ పెండింగ్ జాబితా'),
('min_balance',         'Min. Balance',         'కనీస నిల్వ'),
('pending_periods',     'Pending',              'పెండింగ్'),
('any_amount',          'Any Amount',           'ఏ మొత్తమైనా'),
('any_age',             'Any',                  'ఏదైనా'),
('date_range',          'Date Range',           'తేదీ పరిధి'),
('all_dates',           'All Dates',            'అన్ని తేదీలు'),
('sort_newest',         'Newest First',         'కొత్తవి ముందు'),
('sort_oldest',         'Oldest First',         'పాతవి ముందు'),
('sort_last_paid',      'Longest Unpaid',       'ఎక్కువ కాలం చెల్లించనివి'),
('sort_amount',         'Highest Balance',      'అత్యధిక నిల్వ'),
('sort_village_pin',    'Village & PIN',        'గ్రామం & పిన్'),
('last_paid',           'Last Paid',            'చివరిగా చెల్లించినది'),
('never_paid',          'Never Paid',           'ఎప్పుడూ చెల్లించలేదు'),
('periods_overdue',     '{n} {unit} pending',   '{n} {unit} పెండింగ్'),
('unit_days',           'days',                 'రోజులు'),
('unit_weeks',          'weeks',                'వారాలు'),
('unit_months',         'months',               'నెలలు'),
('nothing_pending',     'Nothing pending. Every loan on this book is settled.',
 'పెండింగ్ ఏమీ లేదు. ఈ పుస్తకంలోని ప్రతి అప్పు తీరిపోయింది.'),
('no_rows_for_filters', 'No loans match these filters.',
 'ఈ వడపోతలకు సరిపోయే అప్పులు లేవు.'),
('total_outstanding',   'Total Outstanding',    'మొత్తం బకాయి')
ON CONFLICT (translation_key) DO NOTHING;
