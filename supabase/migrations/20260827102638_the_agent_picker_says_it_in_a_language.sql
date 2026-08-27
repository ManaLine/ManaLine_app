-- agent_picker_sheet.dart calls ref.t() on two keys that were never added to
-- ui_translations, so both rendered as the raw key -- an Agent choosing who to
-- hand a customer to saw "transfer_to_agent" as the sheet's title.
--
-- english + telugu only, matching the table: all 1487 rows carry those two,
-- and only 174 carry hindi/tamil/kannada.
insert into ui_translations (translation_key, english, telugu) values
  ('transfer_to_agent', 'Transfer To Agent', 'ఏజెంట్‌కు బదిలీ చేయండి'),
  ('no_other_active_agent_note',
   'No other active agent to transfer to.',
   'బదిలీ చేయడానికి మరో యాక్టివ్ ఏజెంట్ లేరు.')
on conflict (translation_key) do nothing;
