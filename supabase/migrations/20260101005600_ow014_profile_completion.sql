-- =============================================================================
-- 0053 — OW-014 Profile Completion (Owner-side): RPCs + storage policies
-- =============================================================================
-- OW-014's "Complete Profile" tile had no destination at all — it fired a
-- SnackBar saying the sub-flow was out of scope. Building the screen alone
-- would NOT have worked: every write the sub-flow needs is blocked by
-- 0012's RLS for an Owner acting on ANOTHER person's rows, and would have
-- failed silently or with a bare 42501:
--
--   * persons UPDATE            -> persons_self_update only (self)
--   * person_addresses INSERT   -> person_addresses_self_all only (self)
--   * identity_documents INSERT -> identity_documents_self_all only (self);
--                                  the business-partner policy is SELECT
--   * storage profile-photos    -> profile_photos_self_* only (0040), path
--                                  scoped to the CALLER's person_id folder
--
-- So the real gap was backend, not UI. Closed here with the same
-- SECURITY DEFINER + explicit-gate idiom already used by
-- app.owner_update_customer_address (0027) and
-- app.support_upload_identity_document (0029) — which exists for exactly
-- this reason on the platform-admin side.
--
-- Gate used throughout: app.owner_owns_pending_or_active_member (0035) —
-- the caller must be the owner_person_id of a business in which the target
-- person holds a business_members row. Deliberately NOT
-- shares_active_business, because a Pre-Existing member's membership may
-- still be 'Pending Invitation' at completion time.
--
-- DELIBERATELY NOT INCLUDED — password, PIN, OTP verification and terms
-- acceptance are all listed on the OW-014 tile, but none of them are an
-- Owner's to perform for another human being:
--   * password_hash / pin_hash — set by the member at LR-007 First Login.
--     An Owner writing another person's credential defeats the entire
--     auth model; no RPC is offered.
--   * OTP verification — otp_verifications is self-only by design (0012's
--     own comment); the code goes to the member's phone.
--   * terms / privacy acceptance — agreement_acceptances.otp_id is NOT
--     NULL, i.e. the schema itself requires the member's own verified OTP.
-- The screen surfaces these as member-side steps rather than pretending.
-- -----------------------------------------------------------------------------

-- -----------------------------------------------------------------------------
-- Storage folder gate. Wrapped in plpgsql (not inlined into the policy) so a
-- non-numeric first path segment returns FALSE instead of raising on the
-- ::BIGINT cast — a storage policy that can throw would break unrelated
-- uploads into the same bucket.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_owns_member_folder(p_folder TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
AS $$
BEGIN
  IF p_folder IS NULL OR p_folder !~ '^[0-9]+$' THEN
    RETURN FALSE;
  END IF;
  RETURN app.owner_owns_pending_or_active_member(p_folder::BIGINT);
END;
$$;

COMMENT ON FUNCTION app.owner_owns_member_folder(TEXT) IS
  'Storage-path variant of owner_owns_pending_or_active_member: TRUE if the first path segment is a person_id whose business_members row sits in a business owned by the caller. Returns FALSE (never raises) for non-numeric segments.';

GRANT EXECUTE ON FUNCTION app.owner_owns_member_folder(TEXT) TO authenticated;

-- --- profile-photos: extend 0040's self-only policies to Owner-on-member ----
-- 0040 scoped this bucket to '<person_id>/photo.jpg' written by that person
-- only. OW-014's Owner captures the photo for a member who has no session
-- of their own yet, so the Owner needs write access to that member's folder.

CREATE POLICY profile_photos_owner_member_write ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'profile-photos'
    AND app.owner_owns_member_folder((storage.foldername(name))[1])
  );

CREATE POLICY profile_photos_owner_member_update ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'profile-photos'
    AND app.owner_owns_member_folder((storage.foldername(name))[1])
  );

CREATE POLICY profile_photos_owner_member_select ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'profile-photos'
    AND app.owner_owns_member_folder((storage.foldername(name))[1])
  );

-- --- member-documents bucket ------------------------------------------------
-- identity_documents.file_url needs somewhere to point. The existing
-- 'dispute-documents' bucket (0030) is platform-admin-only and belongs to
-- SP-001's dispute flow — reusing it would hand Owners a bucket gated on
-- app.is_platform_admin(). New bucket, path convention
-- '<person_id>/<document_type>-<epoch>.jpg', readable/writable by the
-- person themselves or an Owner of a business they belong to.

INSERT INTO storage.buckets (id, name, public)
VALUES ('member-documents', 'member-documents', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY member_documents_write ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'member-documents'
    AND (
      (storage.foldername(name))[1] = app.current_person_id()::TEXT
      OR app.owner_owns_member_folder((storage.foldername(name))[1])
    )
  );

CREATE POLICY member_documents_update ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'member-documents'
    AND (
      (storage.foldername(name))[1] = app.current_person_id()::TEXT
      OR app.owner_owns_member_folder((storage.foldername(name))[1])
    )
  );

CREATE POLICY member_documents_select ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'member-documents'
    AND (
      (storage.foldername(name))[1] = app.current_person_id()::TEXT
      OR app.owner_owns_member_folder((storage.foldername(name))[1])
    )
  );

-- -----------------------------------------------------------------------------
-- app.owner_update_member_identity — the persons-row half of completion.
-- NULL params are left untouched (COALESCE), so the screen can save one
-- section at a time without having to re-send everything else.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_update_member_identity(
  p_person_id         BIGINT,
  p_mobile_number     VARCHAR DEFAULT NULL,
  p_dob               DATE DEFAULT NULL,
  p_aadhaar_number    VARCHAR DEFAULT NULL,
  p_profile_photo_url TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.owner_owns_pending_or_active_member(p_person_id) THEN
    RAISE EXCEPTION 'Not authorized for this person' USING ERRCODE = '42501';
  END IF;

  UPDATE persons SET
    mobile_number     = COALESCE(p_mobile_number, mobile_number),
    dob               = COALESCE(p_dob, dob),
    aadhaar_number    = COALESCE(p_aadhaar_number, aadhaar_number),
    profile_photo_url = COALESCE(p_profile_photo_url, profile_photo_url),
    updated_at        = now()
  WHERE person_id = p_person_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Person not found' USING ERRCODE = 'P0002';
  END IF;
END;
$$;

COMMENT ON FUNCTION app.owner_update_member_identity(BIGINT, VARCHAR, DATE, VARCHAR, TEXT) IS
  'OW-014 Profile Completion — Owner-side write to a member persons row. Deliberately cannot touch password_hash, pin_hash, terms_accepted_at or privacy_accepted_at: those are the member''s own to set (see 0053 header).';

GRANT EXECUTE ON FUNCTION app.owner_update_member_identity(BIGINT, VARCHAR, DATE, VARCHAR, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.owner_upload_member_document — identity_documents INSERT. Mirrors
-- app.support_upload_identity_document (0029) exactly, gated on Owner
-- instead of platform admin.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_upload_member_document(
  p_person_id BIGINT, p_document_type identity_document_type_enum, p_file_url TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_document_id UUID;
BEGIN
  IF NOT app.owner_owns_pending_or_active_member(p_person_id) THEN
    RAISE EXCEPTION 'Not authorized for this person' USING ERRCODE = '42501';
  END IF;

  INSERT INTO identity_documents (person_id, document_type, file_url)
  VALUES (p_person_id, p_document_type, p_file_url)
  RETURNING document_id INTO v_document_id;

  RETURN v_document_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.owner_upload_member_document(BIGINT, identity_document_type_enum, TEXT) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.owner_member_profile_checklist — drives the screen's per-step ticks.
-- An RPC rather than three client-side SELECTs specifically so
-- persons.password_hash / pin_hash never leave the database: the screen
-- needs to know WHETHER a credential exists, and nothing more.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_member_profile_checklist(p_person_id BIGINT)
RETURNS TABLE(
  full_name        VARCHAR,
  mlid             VARCHAR,
  profile_status   TEXT,
  has_photo        BOOLEAN,
  has_address      BOOLEAN,
  has_document     BOOLEAN,
  has_mobile       BOOLEAN,
  has_credential   BOOLEAN,
  terms_accepted   BOOLEAN,
  address_summary  TEXT
)
LANGUAGE plpgsql STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  IF NOT app.owner_owns_pending_or_active_member(p_person_id) THEN
    RAISE EXCEPTION 'Not authorized for this person' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.full_name,
    p.mlid,
    p.profile_status::TEXT,
    p.profile_photo_url IS NOT NULL,
    EXISTS (SELECT 1 FROM person_addresses a WHERE a.person_id = p.person_id AND a.is_current),
    EXISTS (SELECT 1 FROM identity_documents d WHERE d.person_id = p.person_id AND NOT d.is_archived),
    p.mobile_number IS NOT NULL,
    (p.password_hash IS NOT NULL OR p.pin_hash IS NOT NULL),
    p.terms_accepted_at IS NOT NULL,
    (
      SELECT a.door_no || ', ' || l.village_town_name || ', ' || a.mandal || ', ' || a.district || ' — ' || a.pin_code
      FROM person_addresses a
      JOIN locations l ON l.location_id = a.village_id
      WHERE a.person_id = p.person_id AND a.is_current
      LIMIT 1
    )
  FROM persons p
  WHERE p.person_id = p_person_id;
END;
$$;

GRANT EXECUTE ON FUNCTION app.owner_member_profile_checklist(BIGINT) TO authenticated;

-- -----------------------------------------------------------------------------
-- app.owner_mark_member_profile_complete — flips profile_status.
--
-- Prerequisites are enforced HERE, not only in the UI, so the transition
-- can't be reached by a hand-rolled RPC call with an empty profile. The
-- three required artifacts are exactly the Owner-capturable ones the
-- OW-014 tile lists (photo, address incl. PIN + village, identity
-- document); the member-side ones are checked but do NOT block, since a
-- Pre-Existing member's whole purpose is offline record-keeping before
-- they ever hold a session. When they are absent the status lands on
-- 'Pending Verification' rather than 'Complete' — profile_status_enum has
-- that value for precisely this half-way state (BR-231), so this is a
-- documented use of the existing enum, not a new policy.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_mark_member_profile_complete(
  p_person_id BIGINT, p_membership_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_has_photo    BOOLEAN;
  v_has_address  BOOLEAN;
  v_has_document BOOLEAN;
  v_member_side  BOOLEAN;
  v_new_status   profile_status_enum;
BEGIN
  IF NOT app.owner_owns_pending_or_active_member(p_person_id) THEN
    RAISE EXCEPTION 'Not authorized for this person' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM business_members bm
    JOIN businesses b ON b.business_id = bm.business_id
    WHERE bm.membership_id = p_membership_id
      AND bm.person_id = p_person_id
      AND b.owner_person_id = app.current_person_id()
  ) THEN
    RAISE EXCEPTION 'Membership does not belong to this person in a business you own'
      USING ERRCODE = '42501';
  END IF;

  SELECT
    p.profile_photo_url IS NOT NULL,
    EXISTS (SELECT 1 FROM person_addresses a WHERE a.person_id = p.person_id AND a.is_current),
    EXISTS (SELECT 1 FROM identity_documents d WHERE d.person_id = p.person_id AND NOT d.is_archived),
    (p.mobile_number IS NOT NULL
      AND (p.password_hash IS NOT NULL OR p.pin_hash IS NOT NULL)
      AND p.terms_accepted_at IS NOT NULL)
  INTO v_has_photo, v_has_address, v_has_document, v_member_side
  FROM persons p WHERE p.person_id = p_person_id;

  IF v_has_photo IS NULL THEN
    RAISE EXCEPTION 'Person not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_has_photo THEN
    RAISE EXCEPTION 'Profile photo missing' USING ERRCODE = '23514';
  END IF;
  IF NOT v_has_address THEN
    RAISE EXCEPTION 'Current address missing' USING ERRCODE = '23514';
  END IF;
  IF NOT v_has_document THEN
    RAISE EXCEPTION 'Identity document missing' USING ERRCODE = '23514';
  END IF;

  v_new_status := CASE WHEN v_member_side THEN 'Complete' ELSE 'Pending Verification' END::profile_status_enum;

  UPDATE persons SET profile_status = v_new_status, updated_at = now()
  WHERE person_id = p_person_id;

  RETURN v_new_status::TEXT;
END;
$$;

COMMENT ON FUNCTION app.owner_mark_member_profile_complete(BIGINT, UUID) IS
  'OW-014 Profile Completion terminal step. Returns the status actually applied: ''Complete'' only when the member-side steps (mobile, credential, terms) are also done, otherwise ''Pending Verification''. Deliberately does NOT touch business_members.verification_status — an Owner finishing a data-capture form is not identity verification (verification_ring/BR-188 is a separate concern).';

GRANT EXECUTE ON FUNCTION app.owner_mark_member_profile_complete(BIGINT, UUID) TO authenticated;
