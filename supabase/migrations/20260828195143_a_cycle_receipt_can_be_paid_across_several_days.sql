-- A weekly loan whose customer pays daily.
--
-- Umesh owes Rs 300 a week and hands over Rs 100 on Monday, Rs 100 on
-- Tuesday, Rs 100 on Wednesday. The one-entry rule refused the second and
-- third: a Weekly loan may be collected once per account cycle. Correct as a
-- duplicate guard, useless as a description of how the money actually arrives.
--
-- The alternative considered was a child table -- collections as a receipt
-- header, one child row per day. It would have meant recompute_day_ledger,
-- recompute_agent_bf, ledger_history, v_collection_due, record_collection,
-- amend_collection and soft_delete_record all reading through a new join, and
-- every one of those is load-bearing on money.
--
-- This does the same thing with a link. Every payment stays an ordinary
-- collections row carrying its own business_date and its own amount, so the
-- day ledger, the agent's float and the settlement maths need no changes at
-- all and Tuesday's Rs 100 lands on Tuesday. The first payment of a cycle is
-- the receipt; the ones after it point at that row. The receipt an Owner or a
-- customer sees is the parent's, with its days listed underneath.
--
-- Existing rows are all parents, which is what a null means here -- so there
-- is nothing to backfill.
ALTER TABLE collections
  ADD COLUMN parent_collection_id UUID REFERENCES collections(collection_id);

COMMENT ON COLUMN collections.parent_collection_id IS
  'The first payment of this cycle receipt. NULL means this row IS the receipt. '
  'Set only by app.record_collection, which verifies the parent is the same '
  'loan, inside the same one-entry window, and not itself a child.';

-- Reading a receipt means finding its children, and the round asks per loan.
CREATE INDEX IF NOT EXISTS idx_collections_parent
  ON collections (parent_collection_id) WHERE parent_collection_id IS NOT NULL;

-- A child cannot be its own parent, and a parent cannot be a child: one level,
-- so "the receipt" is never a chain somebody has to walk.
ALTER TABLE collections
  ADD CONSTRAINT collections_parent_not_self
  CHECK (parent_collection_id IS NULL OR parent_collection_id <> collection_id);
