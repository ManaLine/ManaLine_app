-- The visit reasons the round offered were not the reasons the database
-- accepts. Of the four in the dropdown, exactly one -- Other -- was a real
-- value of no_collection_reason_enum. Saving a visit failed with
--
--   invalid input value for enum no_collection_reason_enum: "Customer Refused"
--
-- on three of the four choices, which is to say Save Visit worked only if
-- the Agent happened to pick the last option in the list.
--
-- The list is now the enum. These are the keys for the eight values that had
-- no translation; house_locked, shifted_village and other already did.
insert into ui_translations (translation_key, english, telugu) values
  ('customer_not_home', 'Customer Not Home', 'కస్టమర్ ఇంట్లో లేరు'),
  ('customer_out_of_village', 'Customer Out Of Village', 'కస్టమర్ ఊరిలో లేరు'),
  ('requested_extension', 'Requested Extension', 'గడువు పొడిగింపు కోరారు'),
  ('medical_emergency', 'Medical Emergency', 'వైద్య అత్యవసరం'),
  ('festival', 'Festival', 'పండుగ'),
  ('natural_disaster', 'Natural Disaster', 'ప్రకృతి వైపరీత్యం'),
  ('phone_call_not_answered', 'Phone Call Not Answered', 'ఫోన్ కాల్‌కు స్పందించలేదు'),
  ('refused_payment', 'Refused Payment', 'చెల్లింపు నిరాకరించారు')
on conflict (translation_key) do nothing;
