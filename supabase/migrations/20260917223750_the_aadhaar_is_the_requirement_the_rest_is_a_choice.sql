-- The Owner, correcting the conversion form: "MLPI generates once Aadhar
-- number (only) provided, along with that other profile or kyc update is
-- user's choice."
--
-- Which restores the rule the database already had. app.mint_person_mlid
-- issues an MLPI from a gender digit and an Aadhaar and asks for nothing else,
-- and app.convert_customer_to_mlpi already defaults dob and live_photo_url to
-- NULL and COALESCEs them so a blank never erases what is there. The form was
-- the only thing demanding more, and it was demanding more than the app asks
-- of the 34 people who already hold a permanent ID -- 30 of whom have no date
-- of birth and 28 no photograph.
--
-- So the two 'required' strings are retired rather than rewritten. They are
-- left in the table rather than deleted: a translation key costs nothing to
-- carry, and a DELETE here would be a destructive migration run to tidy up
-- two rows nothing reads.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('optional', 'Optional', 'ఐచ్ఛికం')
ON CONFLICT (translation_key) DO NOTHING;
