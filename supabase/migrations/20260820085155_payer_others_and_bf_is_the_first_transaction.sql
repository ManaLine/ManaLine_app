-- Somebody other than the customer or their guarantor can pay.
--
-- The screen made the Agent choose Customer or Guarantor on every single
-- collection — a decision on the overwhelmingly common case, made standing at
-- a doorstep. It is Customer unless said otherwise; "Others" carries a free
-- text name because the person handing the money over is often a son, a
-- neighbour or a shopkeeper the app has never heard of.
ALTER TYPE payer_type_enum ADD VALUE IF NOT EXISTS 'Others';

ALTER TABLE collections
  ADD COLUMN IF NOT EXISTS payer_name varchar(120);

COMMENT ON COLUMN collections.payer_name IS
  'Who actually handed the money over, when payer_type is Others. Free text and optional - the Agent often does not know a full name.';
