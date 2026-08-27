insert into ui_translations (translation_key, english, telugu) values
  ('grace_period', 'Grace Period', 'గ్రేస్ పీరియడ్'),
  ('grace_stops_future_penalties_note',
   'Grace stops future penalties. A penalty already applied stays on the balance -- use Waive / Reduce Penalty to remove one.',
   'గ్రేస్ భవిష్యత్ జరిమానాలను ఆపుతుంది. ఇప్పటికే వర్తింపజేసిన జరిమానా నిల్వలోనే ఉంటుంది -- దాన్ని తీసివేయడానికి జరిమానా మాఫీ / తగ్గింపు వాడండి.'),
  ('grace_resolves_to_note', 'Saved as {days} days', '{days} రోజులుగా సేవ్ చేయబడుతుంది'),
  ('days', 'Days', 'రోజులు'),
  ('weeks', 'Weeks', 'వారాలు'),
  ('months', 'Months', 'నెలలు')
on conflict (translation_key) do nothing;
