-- The same sheet, uploaded any number of times, must leave one loan.
--
-- import_migrated_loans already skips a row whose loan is on the book, but
-- that is a check inside one function: two taps racing, a retry that beats its
-- own predecessor, or any other path into migrate_loan can still write a second
-- copy. On 22 Aug 2026 that is exactly what happened -- 108 duplicate loans,
-- a line balance of nearly double, and the only reason it was caught is that
-- someone was watching the number.
--
-- A guard that lives in one function is a convention. This one is a rule the
-- database keeps.
--
-- IDENTITY, matching import_migrated_loans exactly: business + customer +
-- issue date + repayment amount. Two loans to one customer on one day for the
-- same amount cannot be told from a repeat, and the sheet has no way to say
-- which it meant; that case appears in no real book seen so far, and silently
-- importing a whole second copy is far worse than refusing the rare genuine
-- twin (which can still be entered one at a time, since only migrated loans
-- are covered).
--
-- Scoped to is_pre_existing so live lending is untouched: a customer may
-- genuinely take the same amount on the same day twice at the counter.
-- Soft-deleted rows are excluded so a deleted import can be redone.
CREATE UNIQUE INDEX IF NOT EXISTS loans_one_migrated_loan_per_customer_date_amount
    ON loans (business_id, customer_id, effective_date, repayment_amount)
 WHERE is_pre_existing AND deleted_at IS NULL;

COMMENT ON INDEX loans_one_migrated_loan_per_customer_date_amount IS
  'One migrated loan per customer/issue date/repayment amount. Re-uploading a '
  'migration sheet cannot create a second copy: import_migrated_loans skips '
  'the row, and if anything ever gets past that check the write fails here '
  'rather than doubling the book.';
