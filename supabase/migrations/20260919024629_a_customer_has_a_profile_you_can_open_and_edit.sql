-- A customer's own details had nowhere to be looked at.
--
-- The Owner, 2026-09-18: "collections - customer - tap & hold - open profile
-- of customer with option to edit on top - user clicks edit leads to customer
-- profile allows to edit customer personal details" — and, on the conflict
-- with the existing long-press: "identity - now opens to add aadhar, dob,
-- live photo - make it to open profile as described."
--
-- Nothing in the app showed a customer's details after registration. The
-- identity badge on the collection row opened the MLTI upgrade sheet, which
-- asks for three things and is for converting a temporary ID; there was no
-- way to simply LOOK at somebody, and no way to correct a mobile number.
--
-- WHAT IS EDITABLE IS DECIDED BY WHAT HAS AN RPC. Mobile, date of birth,
-- Aadhaar and photo go through app.owner_update_member_identity; door number,
-- PIN and village through app.owner_update_customer_address. Both already
-- existed and both COALESCE, so a partial edit leaves the rest alone.
--
-- NAME, CARE-OF AND GENDER ARE READ-ONLY, and that is not an oversight.
-- There is no RPC that changes them, and gender is not free to change at all:
-- an MLID carries the gender digit, so editing it would leave an ID that no
-- longer describes its owner. Inventing a write path for identity fields is
-- the kind of thing that belongs in a migration with a CHECK behind it, not
-- in a form.

INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('customer_profile', 'Customer Profile', 'కస్టమర్ ప్రొఫైల్'),
  ('profile_identity_section', 'Identity', 'గుర్తింపు'),
  ('profile_contact_section', 'Contact', 'సంప్రదింపు'),
  ('profile_address_section', 'Address', 'చిరునామా'),
  ('profile_not_on_file', 'Not on file', 'నమోదు కాలేదు'),
  ('profile_edit', 'Edit', 'సవరించండి'),
  ('profile_save', 'Save changes', 'మార్పులను సేవ్ చేయండి'),
  ('profile_saved', 'Saved', 'సేవ్ అయ్యింది'),
  ('profile_readonly_note',
   'Name, care-of and gender cannot be changed here. The MLID is built from the gender, so changing it would leave an ID that no longer matches this person.',
   'పేరు, సంరక్షకుడు, లింగం ఇక్కడ మార్చలేరు. MLID లింగం నుంచి తయారవుతుంది, కాబట్టి మార్చితే ID ఈ వ్యక్తికి సరిపోదు.'),
  ('profile_aadhaar_locked',
   'Aadhaar is locked once a permanent ID has been issued from it.',
   'దాని నుంచి శాశ్వత ID జారీ అయ్యాక ఆధార్ లాక్ అవుతుంది.'),
  ('profile_aadhaar_on_file', 'Aadhaar on file', 'ఆధార్ నమోదైంది'),
  ('profile_dob', 'Date of birth', 'పుట్టిన తేదీ'),
  ('profile_could_not_load', 'This customer could not be loaded.', 'ఈ కస్టమర్‌ను లోడ్ చేయలేకపోయాం.')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key LIKE 'profile_%' AND COALESCE(telugu,'') = '';
  IF v_n <> 0 THEN
    RAISE EXCEPTION '% profile keys have no Telugu', v_n;
  END IF;
END $$;
