-- Six keys the roster/inbox rewrite introduced in code but never in the table.
-- A key with no row renders as the raw key on screen, so this is a visible bug,
-- not housekeeping. English and Telugu only: the other three languages are
-- deferred to v2 and stay NULL rather than being filled with English.
insert into ui_translations (translation_key, english, telugu) values
  ('add_agent',             'Add Agent',    'ఏజెంట్ జోడించండి'),
  ('add_investor',          'Add Investor', 'పెట్టుబడిదారుని జోడించండి'),
  ('roi',                   'ROI',          'ROI'),
  ('continue_label',        'Continue',     'కొనసాగించండి'),
  ('amount_required_field', 'Amount *',     'మొత్తం *'),
  ('full_name_field',       'Full Name *',  'పూర్తి పేరు *')
on conflict (translation_key) do nothing;
