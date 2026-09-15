-- can_apply_penalty defaults TRUE, on purpose, written down where it is read.
--
-- WHY THIS MIGRATION EXISTS AT ALL. The column had no comment, and four places
-- in the tree said the opposite of the schema -- two Dart comments, one RLS
-- migration header and one RPC comment -- all citing "BR-236", which is
-- "No Renewal Linking" and has nothing to do with permissions. The citation
-- was invented once and copied. Nothing anywhere states a default for this
-- flag; BR-009 governs the penalty AMOUNT ("not fixed, decided by the owner
-- per loan"), not who may apply one.
--
-- THE HISTORY. module4 created all 23 permission booleans DEFAULT FALSE. On
-- 2026-08-05, 20260805141301_agent_permissions_default_on_except_delete
-- flipped 22 of them, because all three agent-insert paths write only
-- `agent_id`, so a newly registered agent came into being able to do nothing
-- and the Owner had to tick 22 boxes before they could collect a rupee.
--
-- can_delete_records was deliberately held back, with the reason stated: a
-- delete rewrites the ledger chain and re-derives both BF pots, so it moves
-- closing balances. can_grant_grace_period is likewise FALSE.
--
-- THE QUESTION ASKED ON 2026-09-15, and answered. Applying a penalty is also a
-- money operation -- app.apply_loan_penalty does
-- `remaining_balance = remaining_balance + p_penalty_amount`, increasing what a
-- real customer owes -- so it arguably belonged beside can_delete_records. At
-- that point 10 of 13 agent permission profiles in production had it on and no
-- Owner had chosen it; the column default had.
--
-- Decided: it STAYS TRUE. An agent trusted to collect at the door is trusted to
-- penalise at the door; the two are the same job. The Owner can switch it off
-- per agent on OW-002, and the RLS INSERT policy plus
-- app.can_apply_penalty_on_loan both honour the flag -- verified by switching
-- it off and watching the write be refused.
--
-- Nothing changes in the schema. This records the decision so the next reader
-- finds it here rather than re-deriving it from four wrong comments.
COMMENT ON COLUMN public.agent_permissions.can_apply_penalty IS
  'Defaults TRUE, decided 2026-09-15: an agent trusted to collect is trusted to penalise. Applying a penalty adds to loans.remaining_balance, so this IS a money permission -- it was weighed against can_delete_records (FALSE) and kept ON. Owner switches it off per agent on OW-002. Do NOT cite BR-236 for this; BR-236 is No Renewal Linking.';

COMMENT ON COLUMN public.agent_permissions.can_delete_records IS
  'Defaults FALSE, deliberately and permanently (20260805141301). A delete rewrites the ledger chain and re-derives both BF pots, so it moves closing balances. Granted only explicitly, never by default.';
