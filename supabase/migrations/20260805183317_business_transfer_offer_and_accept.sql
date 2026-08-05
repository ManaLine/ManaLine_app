-- P4 Business Transfer: hand a business to another person, with their consent.
--
-- WHAT MOVES: only ownership. business_id and mlbi never change, so loans,
-- collections, investments, chetis and the whole day_ledger chain are
-- untouched by construction -- the business is the same business, under new
-- management. owner_bf_balance stays with the business too: it is the till,
-- not the person's wallet, so the new owner inherits it.
--
-- TWO-STEP, BY DECISION. A business carries outstanding loans, agents and
-- liabilities. Pushing that onto someone who never agreed is not a transfer,
-- it is a dump. So this creates an OFFER, and the business moves only when the
-- recipient accepts.
--
-- DEPARTURE FROM THE ROADMAP, recorded deliberately: the roadmap says a
-- transfer leaves "zero trace in the old owner's account". By decision, the
-- outgoing owner KEEPS their Agent membership, so they can still collect for
-- the new owner. The consequence is that they also still see that business's
-- customers and collections. That is a trade made with eyes open, not an
-- oversight -- if "zero trace" is wanted later, the accept step is the one
-- place to change.
--
-- MEMBERSHIPS ARE NEVER DELETED. business_members.membership_id is what
-- collections.collected_by_membership_id, expenses.recorded_by_membership_id
-- and agent_bf_assignments key to. Deleting the outgoing owner's row would
-- take money rows with it, or fail on a foreign key. The Owner row becomes
-- 'Removed' -- present for referential integrity, gone from their account.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'business_transfer_status_enum') THEN
    CREATE TYPE business_transfer_status_enum AS ENUM (
      'Pending', 'Accepted', 'Declined', 'Cancelled'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.business_transfers (
  transfer_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id     UUID   NOT NULL REFERENCES businesses(business_id),
  from_person_id  BIGINT NOT NULL REFERENCES persons(person_id),
  to_person_id    BIGINT NOT NULL REFERENCES persons(person_id),
  status          business_transfer_status_enum NOT NULL DEFAULT 'Pending',
  note            TEXT,
  decline_reason  TEXT,
  requested_at    TIMESTAMP NOT NULL DEFAULT now(),
  responded_at    TIMESTAMP,
  CONSTRAINT chk_business_transfer_not_self CHECK (from_person_id <> to_person_id)
);

-- One live offer per business. Without this, an owner could offer the same
-- business to three people and whoever accepted first would win a race the
-- other two could not see.
CREATE UNIQUE INDEX IF NOT EXISTS uq_business_transfer_one_pending
  ON public.business_transfers (business_id)
  WHERE status = 'Pending';

ALTER TABLE public.business_transfers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS business_transfers_owner ON public.business_transfers;
CREATE POLICY business_transfers_owner ON public.business_transfers
  FOR SELECT USING (from_person_id = app.current_person_id());

DROP POLICY IF EXISTS business_transfers_recipient ON public.business_transfers;
CREATE POLICY business_transfers_recipient ON public.business_transfers
  FOR SELECT USING (to_person_id = app.current_person_id());

-- ---------------------------------------------------------------------------
-- Shared guard. Run at BOTH request and accept: an offer can sit for days, and
-- everything it assumed may have changed by the time it is answered.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.assert_business_transferable(
  p_business_id uuid,
  p_from_person bigint,
  p_to_person   bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_to_status account_status_enum;
  v_deceased  BOOLEAN;
  v_bf        NUMERIC;
  v_pending   INT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM businesses
                  WHERE business_id = p_business_id
                    AND owner_person_id = p_from_person) THEN
    RAISE EXCEPTION 'This business is not yours to transfer' USING ERRCODE = '42501';
  END IF;

  SELECT account_status, is_deceased INTO v_to_status, v_deceased
    FROM persons WHERE person_id = p_to_person;
  IF v_to_status IS NULL THEN
    RAISE EXCEPTION 'That person was not found' USING ERRCODE = 'P0002';
  END IF;
  -- Handing a business to a switched-off or half-deleted account would leave
  -- it owned by someone who cannot sign in to run it.
  IF v_to_status <> 'Active' OR v_deceased THEN
    RAISE EXCEPTION 'That person cannot take over a business right now'
      USING ERRCODE = '23514';
  END IF;

  -- The outgoing owner's agent float is real cash in their pocket. Transferring
  -- while it is outstanding would hand the new owner a book that says money is
  -- in the field, with no one accountable for it.
  SELECT COALESCE(SUM(a.agent_bf_current), 0) INTO v_bf
    FROM agent_bf_assignments a
    JOIN business_members bm ON bm.membership_id = a.membership_id
   WHERE bm.business_id = p_business_id
     AND bm.person_id = p_from_person;
  IF v_bf > 0 THEN
    RAISE EXCEPTION 'Settle your own agent cash of % first', v_bf
      USING ERRCODE = '23514';
  END IF;

  -- A settlement awaiting the outgoing owner's review is their decision to
  -- make, not the incoming owner's.
  SELECT count(*) INTO v_pending
    FROM account_settlements s
    JOIN account_periods ap ON ap.account_period_id = s.account_period_id
   WHERE ap.business_id = p_business_id
     AND s.status = 'Pending Owner Review';
  IF v_pending > 0 THEN
    RAISE EXCEPTION 'Review the % settlement(s) waiting on you first', v_pending
      USING ERRCODE = '23514';
  END IF;
END;
$function$;

-- ---------------------------------------------------------------------------
-- Offer.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.request_business_transfer(
  p_business_id uuid,
  p_to_person_id bigint,
  p_note text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_me BIGINT := app.current_person_id();
  v_id UUID;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in' USING ERRCODE = '42501';
  END IF;
  IF p_to_person_id = v_me THEN
    RAISE EXCEPTION 'You cannot transfer a business to yourself' USING ERRCODE = '23514';
  END IF;

  PERFORM app.assert_business_transferable(p_business_id, v_me, p_to_person_id);

  INSERT INTO business_transfers (business_id, from_person_id, to_person_id, note)
  VALUES (p_business_id, v_me, p_to_person_id, p_note)
  RETURNING transfer_id INTO v_id;

  INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type,
                         entity_id, entity_uuid, new_value, business_date)
  VALUES (p_business_id, v_me, 'Other Admin Event', 'business_transfer_offered', 0,
          v_id, json_build_object('to_person_id', p_to_person_id), CURRENT_DATE);

  RETURN json_build_object('transfer_id', v_id, 'status', 'Pending');
END;
$function$;

-- ---------------------------------------------------------------------------
-- Respond. Accepting is the only thing that actually moves the business.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.respond_business_transfer(
  p_transfer_id uuid,
  p_accept boolean,
  p_reason text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_me BIGINT := app.current_person_id();
  t RECORD;
  v_existing UUID;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Not signed in' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO t FROM business_transfers
   WHERE transfer_id = p_transfer_id FOR UPDATE;
  IF t IS NULL THEN
    RAISE EXCEPTION 'Transfer not found' USING ERRCODE = 'P0002';
  END IF;
  IF t.to_person_id <> v_me THEN
    RAISE EXCEPTION 'This offer was not made to you' USING ERRCODE = '42501';
  END IF;
  IF t.status <> 'Pending' THEN
    RAISE EXCEPTION 'This offer has already been answered' USING ERRCODE = '23514';
  END IF;

  IF NOT p_accept THEN
    UPDATE business_transfers
       SET status = 'Declined', responded_at = now(), decline_reason = p_reason
     WHERE transfer_id = p_transfer_id;
    RETURN json_build_object('status', 'Declined');
  END IF;

  -- Re-checked at accept time, not just at offer time. The offer may have sat
  -- for days while the outgoing owner took an agent float or a settlement
  -- landed in their queue.
  PERFORM app.assert_business_transferable(t.business_id, t.from_person_id, v_me);

  UPDATE businesses SET owner_person_id = v_me, updated_at = now()
   WHERE business_id = t.business_id;

  -- Outgoing owner: the OWNER role goes. Their Agent membership is left
  -- untouched on purpose (see this migration's header) so they can keep
  -- collecting for the new owner.
  UPDATE business_members
     SET membership_status = 'Removed', removed_at = now(), updated_at = now()
   WHERE business_id = t.business_id
     AND person_id = t.from_person_id
     AND role = 'Owner';

  -- Incoming owner: reuse an existing Owner row if one is lying around from a
  -- previous transfer, rather than accumulating a second one.
  SELECT membership_id INTO v_existing
    FROM business_members
   WHERE business_id = t.business_id AND person_id = v_me AND role = 'Owner'
   LIMIT 1;

  IF v_existing IS NOT NULL THEN
    UPDATE business_members
       SET membership_status = 'Active', removed_at = NULL, joined_at = COALESCE(joined_at, now()),
           updated_at = now()
     WHERE membership_id = v_existing;
  ELSE
    INSERT INTO business_members (person_id, business_id, role, membership_status,
                                  verification_status, onboarding_method,
                                  invited_by_person_id, joined_at)
    VALUES (v_me, t.business_id, 'Owner', 'Active', 'Not Required',
            'ID Lookup', t.from_person_id, now());
  END IF;

  UPDATE business_transfers
     SET status = 'Accepted', responded_at = now()
   WHERE transfer_id = p_transfer_id;

  INSERT INTO audit_log (business_id, actor_person_id, action_type, entity_type,
                         entity_id, entity_uuid, new_value, business_date)
  VALUES (t.business_id, v_me, 'Other Admin Event', 'business_transfer_accepted', 0,
          p_transfer_id,
          json_build_object('from_person_id', t.from_person_id, 'to_person_id', v_me),
          CURRENT_DATE);

  RETURN json_build_object('status', 'Accepted', 'business_id', t.business_id);
END;
$function$;

-- ---------------------------------------------------------------------------
-- Withdraw an offer that has not been answered.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.cancel_business_transfer(p_transfer_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_me BIGINT := app.current_person_id();
  t RECORD;
BEGIN
  SELECT * INTO t FROM business_transfers WHERE transfer_id = p_transfer_id FOR UPDATE;
  IF t IS NULL THEN
    RAISE EXCEPTION 'Transfer not found' USING ERRCODE = 'P0002';
  END IF;
  IF t.from_person_id <> v_me THEN
    RAISE EXCEPTION 'This offer is not yours to cancel' USING ERRCODE = '42501';
  END IF;
  IF t.status <> 'Pending' THEN
    RAISE EXCEPTION 'This offer has already been answered' USING ERRCODE = '23514';
  END IF;

  UPDATE business_transfers
     SET status = 'Cancelled', responded_at = now()
   WHERE transfer_id = p_transfer_id;

  RETURN json_build_object('status', 'Cancelled');
END;
$function$;

REVOKE ALL ON FUNCTION app.assert_business_transferable(uuid, bigint, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app.request_business_transfer(uuid, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION app.respond_business_transfer(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION app.cancel_business_transfer(uuid) TO authenticated;
