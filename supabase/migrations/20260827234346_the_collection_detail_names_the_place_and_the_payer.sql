-- Two labels for the collection detail sheet: where the money was taken, and
-- who handed it over when it was not the customer.
insert into ui_translations (translation_key, english, telugu) values
  ('location', 'Location', 'ప్రదేశం'),
  ('paid_by', 'Paid By', 'చెల్లించినవారు')
on conflict (translation_key) do nothing;
