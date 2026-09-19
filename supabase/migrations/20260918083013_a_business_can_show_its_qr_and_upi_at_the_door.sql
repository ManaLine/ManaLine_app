-- Design document 2.2.1: "Insert QR & UPI Id's to display ( In jpg < 1mb)".
--
-- On page 4 the Credits Received Slip carries `* QR  * UPI` in its header row,
-- beside the route and the agent's name -- so an agent standing at a door can
-- show a customer something to scan. It is the other half of 2.2.2's
-- "© - Cash / ℗ - Online Payment (Gpay,Phonepe, Paytm)", which shipped on
-- 2026-09-17: the app could already RECORD that money arrived by PhonePe and
-- had no way to let anybody actually pay that way.
--
-- ON businesses, NOT A NEW TABLE. Both are single values owned by the book,
-- and businesses already has exactly the two policies this needs:
-- businesses_owner_all (the Owner writes) and businesses_member_select (an
-- active agent, investor or customer reads). A separate table would mean
-- writing those two rules again.
--
-- upi_ids IS AN ARRAY because the document says "Id's" -- a business may
-- collect on more than one handle, and the slip shows them as a list.
--
-- THE VALIDATION IS A FUNCTION because a CHECK may not contain a subquery
-- (0A000), and checking every element of an array needs one. It is
-- deliberately loose: an element must contain a single '@' with something
-- either side and no whitespace, which is the whole of what a UPI virtual
-- payment address guarantees. Banks invent handle suffixes constantly, so a
-- stricter pattern would reject valid addresses and the refusal would land on
-- an Owner who typed their own ID correctly.
--
-- NO FORMAT CHECK ON THE QR PATH, deliberately. It is a storage path and the
-- bucket decides what may be put there; a CHECK here would be a second opinion
-- about the same thing, and the two would eventually disagree.

CREATE OR REPLACE FUNCTION app.upi_ids_are_valid(p_ids text[])
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT p_ids IS NULL
      OR NOT EXISTS (
           SELECT 1 FROM unnest(p_ids) AS h
            WHERE h !~ '^[^@[:space:]]+@[^@[:space:]]+$'
         );
$function$;

ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS upi_qr_path text,
  ADD COLUMN IF NOT EXISTS upi_ids     text[] NOT NULL DEFAULT '{}';

ALTER TABLE businesses DROP CONSTRAINT IF EXISTS businesses_upi_ids_look_like_vpas;
ALTER TABLE businesses
  ADD CONSTRAINT businesses_upi_ids_look_like_vpas
  CHECK (app.upi_ids_are_valid(upi_ids));

-- A QR IS NOT A LOGO, so it gets its own bucket rather than sharing
-- business-logos. Different ceiling (the document says under 1 MB; logos are
-- capped at 512 KB), different lifetime, and a different audience -- a logo is
-- decoration, this is the thing a customer's banking app has to read.
--
-- image/png IS ALLOWED ALONGSIDE image/jpeg, and this is the one place in this
-- codebase where that matters. JPEG is lossy, and a QR is fine high-contrast
-- detail: compress it too hard and the code stops scanning. That failure is
-- silent, and it happens at somebody's door with the customer waiting. An
-- Owner who already has a PNG from their payment app should be able to upload
-- it untouched.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('business-payment-qr', 'business-payment-qr', false, 1048576,
        ARRAY['image/jpeg', 'image/png'])
ON CONFLICT (id) DO UPDATE
  SET file_size_limit    = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- The same three rules business-logos uses: the Owner writes, every active
-- member reads. An agent MUST be able to read this one -- showing it is the
-- entire point.
DROP POLICY IF EXISTS business_payment_qr_owner_write   ON storage.objects;
DROP POLICY IF EXISTS business_payment_qr_owner_update  ON storage.objects;
DROP POLICY IF EXISTS business_payment_qr_member_select ON storage.objects;

CREATE POLICY business_payment_qr_owner_write ON storage.objects
  FOR INSERT TO authenticated, anon
  WITH CHECK (
    bucket_id = 'business-payment-qr'
    AND app.is_owner(((storage.foldername(name))[1])::uuid)
  );

CREATE POLICY business_payment_qr_owner_update ON storage.objects
  FOR UPDATE TO authenticated, anon
  USING (
    bucket_id = 'business-payment-qr'
    AND app.is_owner(((storage.foldername(name))[1])::uuid)
  );

CREATE POLICY business_payment_qr_member_select ON storage.objects
  FOR SELECT TO authenticated, anon
  USING (
    bucket_id = 'business-payment-qr'
    AND (
      app.is_owner(((storage.foldername(name))[1])::uuid)
      OR app.is_active_agent(((storage.foldername(name))[1])::uuid)
    )
  );

DO $$
DECLARE v_n INT; v_refused BOOLEAN := FALSE;
BEGIN
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='businesses'
     AND column_name IN ('upi_qr_path','upi_ids');
  IF v_n <> 2 THEN
    RAISE EXCEPTION 'expected both QR columns, found %', v_n;
  END IF;

  SELECT count(*) INTO v_n FROM storage.buckets WHERE id='business-payment-qr';
  IF v_n <> 1 THEN RAISE EXCEPTION 'the QR bucket is missing'; END IF;

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects'
     AND policyname LIKE 'business_payment_qr_%';
  IF v_n <> 3 THEN
    RAISE EXCEPTION 'expected 3 QR storage policies, found %', v_n;
  END IF;

  -- The function must accept what a real handle looks like and refuse what
  -- is not one. Asserted rather than assumed: a CHECK nobody has tried to
  -- violate is a CHECK nobody knows the shape of.
  IF NOT app.upi_ids_are_valid(ARRAY['siri@okhdfcbank','9493509919@ybl']) THEN
    RAISE EXCEPTION 'the pattern refuses a valid UPI handle';
  END IF;
  IF app.upi_ids_are_valid(ARRAY['no-at-sign']) THEN
    RAISE EXCEPTION 'the pattern accepts a handle with no @';
  END IF;
  IF app.upi_ids_are_valid(ARRAY['has space@bank']) THEN
    RAISE EXCEPTION 'the pattern accepts whitespace';
  END IF;
  IF app.upi_ids_are_valid(ARRAY['two@at@signs']) THEN
    RAISE EXCEPTION 'the pattern accepts two @';
  END IF;
  IF NOT app.upi_ids_are_valid(ARRAY[]::text[]) THEN
    RAISE EXCEPTION 'an empty list must be allowed -- it is the default';
  END IF;

  -- And the constraint itself must fire, not merely exist.
  --
  -- AMENDED 2026-09-19, and this is the only edit this file has had since it
  -- ran. It asserted the CHECK by updating `(SELECT business_id FROM
  -- businesses LIMIT 1)` -- whichever book happened to exist. On production
  -- that is a real row and the assertion is a real one. On a database rebuilt
  -- from empty there are no businesses: the subquery is NULL, the UPDATE
  -- matches zero rows, no CHECK is asked to fire, v_refused stays FALSE and
  -- the migration raises. `tool/verify_rebuild.ps1` stopped here, 24 files
  -- short of the end, so the repo could not rebuild itself from nothing.
  --
  -- Only the assertion changed; no schema statement in this file was touched,
  -- so what this migration DOES to the database is exactly what it did when
  -- it ran. The same shape is already banned for the files in
  -- `supabase/tests/` -- "a scratch file must build its own fixtures, never
  -- adopt an existing row" -- and that rule simply never covered migrations.
  --
  -- With a book present, the original test runs unchanged. With none, the
  -- claim is decomposed into the two halves that together mean the same
  -- thing and need no rows: the function refuses a bad handle (asserted four
  -- times above) and the constraint is attached to the column and delegates
  -- to that function.
  IF EXISTS (SELECT 1 FROM businesses) THEN
    BEGIN
      UPDATE businesses SET upi_ids = ARRAY['broken']
       WHERE business_id = (SELECT business_id FROM businesses LIMIT 1);
    EXCEPTION WHEN check_violation THEN
      v_refused := TRUE;
    END;
    IF NOT v_refused THEN
      RAISE EXCEPTION 'the CHECK did not fire on a bad handle';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint
       WHERE conrelid = 'public.businesses'::regclass
         AND contype = 'c'
         AND pg_get_constraintdef(oid) ILIKE '%upi_ids_are_valid%'
    ) THEN
      RAISE EXCEPTION 'the upi_ids CHECK is not attached to businesses';
    END IF;
  END IF;
END $$;
