-- Bulk investor import attaches a person who is not an investor here yet.
--
-- WHY: app.bulk_import_investments looked the MLID up in `investors` JOIN
-- `business_members` for this business and rejected the row when it found
-- nothing — "No Investor in this business matches MLID". On a pre-existing
-- book that is EVERY row: the business is being migrated precisely because
-- none of its people are in MANA LINE yet, and step 3 of the bulk onboarding
-- wizard is where its investors are supposed to arrive. The only way through
-- was to attach each investor by hand in OW-003 first, with their first
-- investment, and then delete those rows from the sheet so they were not
-- counted twice — a manual step the wizard exists to remove, and one that
-- silently double-counts if the Owner forgets the deletion.
--
-- It now does what OW-003's own attach path does (app.
-- attach_investor_with_first_investment): reuse the Investor membership if
-- there is one, reactivate it if it was removed, create it if there is none,
-- then record the investment.
--
-- What it still refuses: an MLID that matches NO person. Minting a person from
-- an investor sheet is how a real human ends up with a second identity — the
-- identities sheet (step 1) is the only place people are created.
CREATE OR REPLACE FUNCTION app.bulk_import_investments(
  p_business_id uuid,
  p_rows json
) RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, app
AS $$
DECLARE
  v_locked        BOOLEAN;
  v_row           json;
  v_index         INT := 0;
  v_ok            INT := 0;
  v_attached      INT := 0;
  v_errors        json[] := '{}';
  v_msg           TEXT;
  v_mlid          TEXT;
  v_person_id     BIGINT;
  v_membership_id UUID;
  v_investor_id   UUID;
  v_investment_id UUID;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized to import records into this business'
      USING ERRCODE = '42501';
  END IF;

  SELECT migration_locked INTO v_locked FROM businesses WHERE business_id = p_business_id;
  IF v_locked IS NULL THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_locked THEN
    RAISE EXCEPTION 'Migration is closed for this business. Reopen it before importing.'
      USING ERRCODE = '23514';
  END IF;

  FOR v_row IN SELECT * FROM json_array_elements(p_rows) LOOP
    v_index := v_index + 1;
    BEGIN
      v_mlid := NULLIF(btrim(COALESCE(v_row ->> 'mlid', '')), '');
      IF v_mlid IS NULL THEN
        RAISE EXCEPTION 'This row has no MLID. Every investor row needs one so it can be matched to a person.';
      END IF;

      v_investor_id := NULL;
      SELECT i.investor_id INTO v_investor_id
        FROM investors i
        JOIN persons p ON p.person_id = i.person_id
        JOIN business_members bm ON bm.membership_id = i.membership_id
       WHERE p.mlid = v_mlid AND bm.business_id = p_business_id;

      IF v_investor_id IS NULL THEN
        -- Not an investor here yet. Attach them, but only if the MLID names
        -- a person who already exists — never create one from this sheet.
        SELECT person_id INTO v_person_id FROM persons WHERE mlid = v_mlid;
        IF v_person_id IS NULL THEN
          RAISE EXCEPTION 'No person carries MLID %. Add them on the Identities sheet first.', v_mlid;
        END IF;

        SELECT membership_id INTO v_membership_id
          FROM business_members
         WHERE business_id = p_business_id AND person_id = v_person_id AND role = 'Investor';

        IF v_membership_id IS NULL THEN
          INSERT INTO business_members (
            person_id, business_id, role, membership_status, verification_status,
            onboarding_method, invited_by_person_id, joined_at
          ) VALUES (
            v_person_id, p_business_id, 'Investor', 'Active', 'Not Required',
            app.onboarding_method_now(), app.current_person_id(), now()
          ) RETURNING membership_id INTO v_membership_id;
        ELSE
          UPDATE business_members
             SET membership_status = 'Active', removed_at = NULL,
                 joined_at = COALESCE(joined_at, now())
           WHERE membership_id = v_membership_id;
        END IF;

        SELECT investor_id INTO v_investor_id FROM investors WHERE membership_id = v_membership_id;
        IF v_investor_id IS NULL THEN
          INSERT INTO investors (membership_id, person_id)
          VALUES (v_membership_id, v_person_id)
          RETURNING investor_id INTO v_investor_id;
        END IF;

        v_attached := v_attached + 1;
      END IF;

      v_investment_id := app.record_investment(
        v_investor_id,
        (v_row ->> 'invested_amount')::NUMERIC,
        (v_row ->> 'roi')::NUMERIC,
        (v_row ->> 'interest_type')::investment_interest_type_enum,
        (v_row ->> 'invested_date')::DATE
      );

      -- Set on the investment, not the investor: app.profit_share_accrued
      -- multiplies WHOLE-business profit by this percent, so a sheet that
      -- repeats one person's share on each of their investments would claim
      -- a multiple of the profit. Left blank on the follow-on rows.
      IF NULLIF(v_row ->> 'profit_percent', '') IS NOT NULL THEN
        UPDATE investments
           SET profit_share_percent = (v_row ->> 'profit_percent')::NUMERIC,
               profit_share_effective_date = (v_row ->> 'invested_date')::DATE
         WHERE investment_id = v_investment_id;
      END IF;

      v_ok := v_ok + 1;
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
      v_errors := v_errors || json_build_object(
        'row', v_index, 'mlid', v_row ->> 'mlid', 'error', v_msg
      );
    END;
  END LOOP;

  IF array_length(v_errors, 1) > 0 THEN
    RAISE EXCEPTION 'IMPORT_REJECTED %', json_build_object(
      'imported', 0, 'failed', array_length(v_errors, 1), 'total', v_index,
      'errors', array_to_json(v_errors)
    )::text
    USING ERRCODE = '23514';
  END IF;

  RETURN json_build_object('imported', v_ok, 'attached', v_attached, 'total', v_index);
END;
$$;
