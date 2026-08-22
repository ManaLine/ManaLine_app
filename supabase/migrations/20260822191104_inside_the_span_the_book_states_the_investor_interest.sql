-- Inside the migrated span the book states the investor interest.
--
-- Everywhere else in this migration the rule is already that: BF, line
-- balance and profit are all declared and the app derives from the cut-off
-- onward. Investor interest was the exception -- derived all the way back
-- through a period the app never saw -- and it landed Rs 1,600 under the
-- Owner's own book.
--
-- Neither figure was wrong so much as differently conventioned. The app
-- accrues on the principal standing in each stretch; the book accrues on the
-- full principal and then deducts what was settled by hand at each
-- withdrawal. Rs 600 of the gap is one such settlement on Karri Bhaskara
-- Reddy's withdrawals, Rs 1,000 is a period the Owner rounded up on the
-- 27 February investment. Arguing with either would be the app telling
-- someone their own book is wrong about their own money.
--
-- declared_interest_to_cutoff holds what the book says each investment had
-- earned by the cut-off. It is seeded here from migration_weeks, which
-- already carries the figures: investor_in_interest against the week an
-- investment started, less the investor_out_interest of any week that
-- investment was withdrawn from.
--
-- SEEDED ONLY WHERE IT IS UNAMBIGUOUS -- exactly one investment starting on
-- that account date, and no other investment withdrawn from in a week being
-- charged against it. Two investments in one week cannot be told apart from
-- weekly totals, and splitting them by guesswork would put a number in an
-- investor's balance that nobody wrote. Those stay NULL and keep deriving.
ALTER TABLE investments
  ADD COLUMN IF NOT EXISTS declared_interest_to_cutoff numeric(14,0);

COMMENT ON COLUMN investments.declared_interest_to_cutoff IS
  'What the migrated book says this investment had earned by the cut-off. '
  'NULL for anything not migrated, or where the book''s weekly totals could '
  'not be attributed to one investment. Used only up to migrated_through_date; '
  'after that the app derives.';

WITH starts AS (
  -- Only where a single investment began on that account date.
  SELECT i.investment_id, i.business_id, w.investor_in_interest AS earned
    FROM investments i
    JOIN migration_weeks w
      ON w.business_id = i.business_id
     AND w.account_date = i.effective_date
   WHERE i.deleted_at IS NULL
     AND 1 = (SELECT count(*) FROM investments x
               WHERE x.business_id = i.business_id
                 AND x.effective_date = i.effective_date
                 AND x.deleted_at IS NULL)
),
settled AS (
  -- Interest settled by hand when money was taken out of that investment.
  SELECT wd.investment_id, SUM(w.investor_out_interest) AS settled
    FROM investment_withdrawals wd
    JOIN investments i ON i.investment_id = wd.investment_id
    JOIN migration_weeks w
      ON w.business_id = i.business_id
     AND w.account_date = wd.business_date
   WHERE wd.deleted_at IS NULL AND i.deleted_at IS NULL
     AND 1 = (SELECT count(DISTINCT w2.investment_id)
                FROM investment_withdrawals w2
                JOIN investments i2 ON i2.investment_id = w2.investment_id
               WHERE i2.business_id = i.business_id
                 AND w2.business_date = wd.business_date
                 AND w2.deleted_at IS NULL)
   GROUP BY 1
)
UPDATE investments t
   SET declared_interest_to_cutoff =
         GREATEST(s.earned - COALESCE(x.settled, 0), 0)
  FROM starts s
  LEFT JOIN settled x ON x.investment_id = s.investment_id
 WHERE t.investment_id = s.investment_id;
