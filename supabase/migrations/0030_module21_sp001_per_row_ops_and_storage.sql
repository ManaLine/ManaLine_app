-- =============================================================================
-- 0030 — Module 21: SP-001 Per-Row Suspend/Unsuspend RPCs, OTP Trigger Row,
-- Dispute-Documents Storage Bucket
-- =============================================================================
-- Supersedes 0029's app.support_apply_suspension(person_id, suspend) with
-- four separate RPCs matching the aadhaar_dispute_state.dart stub's ORIGINAL
-- signatures exactly (suspendBusiness/suspendMembership/unsuspendBusiness/
-- unsuspendMembership, each taking a single business_id or membership_id) —
-- per this session's explicit instruction to keep existing method
-- signatures unless a change is specifically flagged. The Dart-side
-- per-row loop (one call per SuspensionImpactRow) moves back into the
-- notifier, matching the original stub's confirmSuspension/resolveCase.
-- Each individual call is still its own gated RPC, not a raw client
-- UPDATE — single-column, single-row status flips are exactly the kind of
-- operation this codebase already always wraps in an RPC rather than a
-- direct table grant (see cash_transfers, agent_bf_assignments,
-- account_periods in rls_role_matrix.md's "RPC required instead" list).
-- =============================================================================

DROP FUNCTION IF EXISTS app.support_apply_suspension(BIGINT, BOOLEAN);

-- -----------------------------------------------------------------------------
-- support_suspend_business / support_unsuspend_business
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.support_suspend_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  UPDATE businesses SET business_status = 'Suspended', updated_at = now()
  WHERE business_id = p_business_id;
  -- No auto-expiry of any kind (SP-001 RESOLVED item: "CONFIRMED no
  -- timeout... stays suspended indefinitely until the original holder
  -- responds"). Deliberately no scheduled job, no expires_at column.
END;
$$;

GRANT EXECUTE ON FUNCTION app.support_suspend_business(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION app.support_unsuspend_business(p_business_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  UPDATE businesses SET business_status = 'Active', updated_at = now()
  WHERE business_id = p_business_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.support_unsuspend_business(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- support_suspend_membership / support_unsuspend_membership
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.support_suspend_membership(p_membership_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  UPDATE business_members SET membership_status = 'Suspended', updated_at = now()
  WHERE membership_id = p_membership_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.support_suspend_membership(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION app.support_unsuspend_membership(p_membership_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  UPDATE business_members SET membership_status = 'Active', updated_at = now()
  WHERE membership_id = p_membership_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.support_unsuspend_membership(UUID) TO authenticated;

-- -----------------------------------------------------------------------------
-- OTP re-verification on upgrade-mlid (04_API_Specification_v1_Part1.md
-- §1.1: "Triggers OTP re-verification (purpose=Registration)").
--
-- FLAGGED GAP, not silently skipped: this codebase's own 0012 RLS comment
-- states OTP issuance/verification "must go through a server-side function
-- that can actually check the code, rate-limit, and mark Expired" — but NO
-- such function exists in any migration provided to this session (0001-
-- 0029), and no AuthApiService/LR-005 Dart source was included in the
-- reference material either, so there is no existing OTP RPC pattern to
-- reuse here as instructed. Rather than invent a whole new OTP-dispatch/
-- verify subsystem (out of this chat's scope — SP-001 is the assigned
-- surface, not Module 0 auth), support_upgrade_mlid_dispute below is
-- extended to do only the one DB-level act available to it: write a
-- `Sent` otp_verifications row (purpose='Registration') so a real SMS-
-- dispatch integration has something to pick up. Actually sending the SMS
-- and the corresponding /auth/otp/verify confirmation step are NOT
-- implemented anywhere in this codebase per the material available to this
-- session — flagged here explicitly for master chat, not quietly omitted.
-- Re-created (not just altered) since RETURNS TABLE composition changes.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS app.support_upgrade_mlid_dispute(BIGINT, VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION app.support_upgrade_mlid_dispute(
  p_person_id BIGINT, p_corrected_aadhaar VARCHAR, p_reason VARCHAR
)
RETURNS TABLE(person_id BIGINT, old_mlid VARCHAR, new_mlid VARCHAR, otp_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_old_mlid VARCHAR(13);
  v_gender_digit CHAR(1);
  v_new_mlid VARCHAR(13);
  v_conflicting_person BIGINT;
  v_otp_id UUID;
BEGIN
  IF NOT app.is_platform_admin() THEN
    RAISE EXCEPTION 'Not authorized — platform admin access required' USING ERRCODE = '42501';
  END IF;

  SELECT mlid, gender_digit INTO v_old_mlid, v_gender_digit
  FROM persons WHERE persons.person_id = p_person_id;
  IF v_old_mlid IS NULL THEN
    RAISE EXCEPTION 'Person not found' USING ERRCODE = 'P0002';
  END IF;

  v_new_mlid := 'MLPI' || v_gender_digit || RIGHT(p_corrected_aadhaar, 8);

  SELECT persons.person_id INTO v_conflicting_person
  FROM persons WHERE persons.mlid = v_new_mlid AND persons.person_id <> p_person_id;
  IF v_conflicting_person IS NOT NULL THEN
    RAISE EXCEPTION 'Corrected Aadhaar already claimed by another person_id' USING ERRCODE = '23505';
  END IF;

  UPDATE persons
  SET mlid = v_new_mlid, mlid_type = 'MLPI', aadhaar_number = p_corrected_aadhaar, updated_at = now()
  WHERE persons.person_id = p_person_id;

  INSERT INTO person_id_history (person_id, old_mlid, new_mlid, reason)
  VALUES (p_person_id, v_old_mlid, v_new_mlid, p_reason);

  -- otp_code_hash has no real code to hash yet (no SMS-dispatch integration
  -- available to this RPC) — stored as a placeholder empty-hash marker so
  -- the NOT NULL constraint is satisfiable without fabricating a real,
  -- crackable code server-side. A genuine OTP-send integration must
  -- overwrite this row (by otp_id) with a real hash before the row is
  -- usable for verification. Flagged, not a working OTP flow.
  INSERT INTO otp_verifications (person_id, purpose, otp_code_hash, status)
  VALUES (p_person_id, 'Registration', '', 'Sent')
  RETURNING otp_verifications.otp_id INTO v_otp_id;

  RETURN QUERY SELECT p_person_id, v_old_mlid, v_new_mlid, v_otp_id;
END;
$$;

COMMENT ON FUNCTION app.support_upgrade_mlid_dispute(BIGINT, VARCHAR, VARCHAR) IS
  'BR-239/upgrade-mlid, Dispute Resolution variant. Writes person_id_history and an otp_verifications Sent placeholder row (see inline comment — real SMS dispatch + /auth/otp/verify are NOT implemented anywhere in the material available to this session; flagged gap). person_id never changes.';

GRANT EXECUTE ON FUNCTION app.support_upgrade_mlid_dispute(BIGINT, VARCHAR, VARCHAR) TO authenticated;

-- -----------------------------------------------------------------------------
-- dispute-documents storage bucket — both parties' proof documents
-- (identity_documents DATA MODEL TOUCHED note in SP-001's own spec).
-- Separate from the existing `live-photos` bucket (0023): that bucket's
-- path convention is {business_id}/..., but SP-001 documents frequently
-- have no business_id at all (the second person may not be a member of
-- any business, and may not even have a person_id yet at Step 1 — see the
-- identity_documents NOT NULL person_id gap already flagged in
-- aadhaar_dispute_state.dart). Path convention here is
-- {person_id}/{document_id}.ext for a known person (original holder), or
-- unregistered/{case_local_id}.ext for the pre-registration second-person
-- upload (no DB metadata row possible for that one, per the same flagged
-- gap — the bytes can still be stored even though identity_documents
-- can't hold a row for it yet).
--
-- SCOPE NOTE: this bucket + its policies are infrastructure only. The
-- actual client-side byte upload is NOT wired in aadhaar_dispute_state.dart
-- this pass — the SP-001 screen file (out of this chat's touch-scope per
-- the briefing) still only ever constructs a stub 'stub://...' URL rather
-- than performing a real Storage upload, so there is no real upload call
-- site yet to point at this bucket. Flagged for whoever next extends the
-- screen to actually pick/upload a file.
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('dispute-documents', 'dispute-documents', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY dispute_documents_platform_admin_insert ON storage.objects
  FOR INSERT
  WITH CHECK (bucket_id = 'dispute-documents' AND app.is_platform_admin());

CREATE POLICY dispute_documents_platform_admin_select ON storage.objects
  FOR SELECT
  USING (bucket_id = 'dispute-documents' AND app.is_platform_admin());

-- No UPDATE/DELETE policy for any role — these are case evidence, treated
-- with the same "never edited, only archived at the metadata layer"
-- posture as identity_documents.is_archived elsewhere in this schema; a
-- re-upload is a new object, not an overwrite.
