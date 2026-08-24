-- What the Owner says their book contains, before the wizard starts.
--
-- The wizard used to march everyone through every page whether or not their
-- book had anything to put on it, and worked out the shape of the book from
-- whatever happened to arrive. Three of today's defects come from that:
--
--  * Shareholders were stamped with TODAY'S date, because the cut-off is not
--    chosen until page 6 and shareholders are recorded on page 3.
--  * A book with no weekly sheet seeds its declared BF onto the FIRST day of
--    the ledger instead of the cut-off, because nothing tells the ledger where
--    the old book ends. On the live data that produced an owner BF of minus
--    Rs 13,72,720 against a declared Rs 100.
--  * "0 instalments ready" cannot be told from "this book has no instalment
--    history", so a file that failed to read looks the same as one that had
--    nothing to give.
--
-- All three are the app learning the shape of the book too late. The plan is
-- recorded first: which sections apply, and the cut-off date, which is the
-- anchor everything else is stated as at.
--
-- Stored as jsonb rather than a column each: this is a statement of intent
-- that will grow a key whenever the wizard grows a page, and a column per tick
-- would mean a migration every time. Nothing computes money from it -- it
-- decides which pages are shown and what the lock warns about.
ALTER TABLE businesses
  ADD COLUMN IF NOT EXISTS migration_plan jsonb;

COMMENT ON COLUMN businesses.migration_plan IS
  'What the Owner said their book contains, recorded before the wizard runs: '
  'which sections apply and the cut-off date. Decides which pages are shown '
  'and what lock_migration warns about. Never a source of money figures.';

CREATE OR REPLACE FUNCTION app.set_migration_plan(
  p_business_id uuid,
  p_plan jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_cutoff date;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  PERFORM app.migration_assert_open(p_business_id);

  v_cutoff := NULLIF(btrim(COALESCE(p_plan ->> 'cutoff_date', '')), '')::date;
  IF v_cutoff IS NOT NULL AND v_cutoff > CURRENT_DATE THEN
    RAISE EXCEPTION 'The cut-off date cannot be in the future.' USING ERRCODE = '23514';
  END IF;

  UPDATE businesses
     SET migration_plan = p_plan,
         -- Recorded here as well as in the plan, so everything that already
         -- reads opening_bf_declared_on -- the ledger boundary, the shareholder
         -- declaration date -- sees the cut-off from the start rather than
         -- from page 6. The AMOUNT is still declared on the snapshot page;
         -- this is only the date it will be stated as at.
         opening_bf_declared_on = COALESCE(v_cutoff, opening_bf_declared_on)
   WHERE business_id = p_business_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Business not found' USING ERRCODE = 'P0002';
  END IF;

  RETURN p_plan;
END;
$$;

GRANT EXECUTE ON FUNCTION app.set_migration_plan(uuid, jsonb)
  TO authenticated, service_role;
