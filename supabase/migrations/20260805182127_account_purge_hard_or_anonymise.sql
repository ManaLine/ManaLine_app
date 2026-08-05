-- P4 Security: execute the 90-day purge.
--
-- DECISION, agreed: hard-delete when the person has no financial ties,
-- anonymise when they do.
--
-- The reason this is not simply "delete" is that a Customer's loans and
-- collections are not their data alone -- they are the Owner's book. Deleting
-- them would make app.recompute_day_ledger rebuild every affected day without
-- those collections, and both BF pots would move. Someone leaving the platform
-- must not silently rewrite another person's money. So:
--
--   * No loans, no investments, no collections, no settlements  -> hard delete.
--     Nothing of theirs is load-bearing for anyone else, so nothing is kept.
--   * Otherwise                                                 -> anonymise.
--     Every identifying field is destroyed; the financial rows survive,
--     unlinkable to a real person. The Owner's totals do not move by one rupee.
--
-- Both outcomes are recorded in admin_deletion_log with a snapshot, the same
-- audit trail an admin deletion leaves.

-- ---------------------------------------------------------------------------
-- 1. Is this person load-bearing for someone else's books?
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.person_has_financial_ties(p_person_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT
    EXISTS (SELECT 1 FROM loans l
             JOIN customers c ON c.customer_id = l.customer_id
            WHERE c.person_id = p_person_id)
    OR EXISTS (SELECT 1 FROM investments i
                JOIN investors iv ON iv.investor_id = i.investor_id
               WHERE iv.person_id = p_person_id)
    OR EXISTS (SELECT 1 FROM collections co
                JOIN business_members bm ON bm.membership_id = co.collected_by_membership_id
               WHERE bm.person_id = p_person_id)
    OR EXISTS (SELECT 1 FROM account_settlements s
                JOIN agents a ON a.agent_id = s.agent_id
               WHERE a.person_id = p_person_id)
    OR EXISTS (SELECT 1 FROM expenses e
                JOIN business_members bm ON bm.membership_id = e.recorded_by_membership_id
               WHERE bm.person_id = p_person_id);
$function$;

-- ---------------------------------------------------------------------------
-- 2. Destroy every identifying field, keep the money rows.
--
-- MLID IS PII HERE. Per BR-181/182 it is "MLPI" + gender digit + the last 8
-- digits of the person's Aadhaar. Leaving it in place would mean an
-- "anonymised" row still carried most of an Aadhaar number, so it is replaced
-- rather than kept. It stays unique and non-null because other rows reference
-- this person and the column is NOT NULL.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.anonymise_person(p_person_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
BEGIN
  UPDATE persons
     SET full_name           = 'Deleted Account',
         father_husband_name = '-',
         mlid                = 'DELETED-' || p_person_id::text,
         mobile_number       = NULL,
         aadhaar_number      = NULL,
         dob                 = NULL,
         password_hash       = NULL,
         pin_hash            = NULL,
         pin_length          = NULL,
         biometric_enabled   = false,
         profile_photo_url   = NULL,
         account_status      = 'Deleted',
         purge_after         = NULL
   WHERE person_id = p_person_id;

  -- Rows that are purely identity or contact, with no money attached.
  DELETE FROM person_addresses    WHERE person_id = p_person_id;
  DELETE FROM identity_documents  WHERE person_id = p_person_id;
  DELETE FROM person_id_history   WHERE person_id = p_person_id;
  DELETE FROM devices             WHERE person_id = p_person_id;
  DELETE FROM otp_verifications   WHERE person_id = p_person_id;
  DELETE FROM notifications       WHERE recipient_person_id = p_person_id;
  DELETE FROM duplicate_suspects  WHERE person_id_a = p_person_id OR person_id_b = p_person_id;
  DELETE FROM customer_documents  WHERE customer_id IN (
    SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM customer_remarks    WHERE customer_id IN (
    SELECT customer_id FROM customers WHERE person_id = p_person_id);
  DELETE FROM agent_documents     WHERE agent_id IN (
    SELECT agent_id FROM agents WHERE person_id = p_person_id);

  -- Memberships are set Removed rather than deleted: business_members is what
  -- loans, collections and settlements are keyed to, so dropping the row would
  -- take the money rows with it and defeat the point of anonymising.
  UPDATE business_members
     SET membership_status = 'Removed'
   WHERE person_id = p_person_id;

  -- NOT HANDLED HERE, and it needs a separate pass: the person's uploaded
  -- files. profile-photos and live-photos hold images of their face, and SQL
  -- cannot delete from Storage. Until that job exists, anonymising clears the
  -- URL but the object survives in the bucket.
END;
$function$;

-- ---------------------------------------------------------------------------
-- 3. The daily job.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.purge_due_accounts()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  r RECORD;
  v_hard INT := 0;
  v_anon INT := 0;
  v_snapshot JSONB;
BEGIN
  FOR r IN
    SELECT person_id
      FROM persons
     WHERE account_status = 'Pending Deletion'
       AND purge_after IS NOT NULL
       AND purge_after <= CURRENT_DATE
  LOOP
    SELECT jsonb_build_object(
      'person', to_jsonb(p.*),
      'had_financial_ties', app.person_has_financial_ties(r.person_id)
    ) INTO v_snapshot
    FROM persons p WHERE p.person_id = r.person_id;

    INSERT INTO admin_deletion_log (deleted_by, entity_type, entity_id,
                                    entity_snapshot, reason)
    VALUES (NULL, 'person', r.person_id::TEXT, v_snapshot,
            'Automatic purge 90 days after the person requested deletion');

    IF app.person_has_financial_ties(r.person_id) THEN
      PERFORM app.anonymise_person(r.person_id);
      v_anon := v_anon + 1;
    ELSE
      PERFORM app.purge_person_hard(r.person_id);
      v_hard := v_hard + 1;
    END IF;
  END LOOP;

  RETURN json_build_object('hard_deleted', v_hard, 'anonymised', v_anon);
END;
$function$;

REVOKE ALL ON FUNCTION app.person_has_financial_ties(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.anonymise_person(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION app.purge_due_accounts() FROM PUBLIC;
