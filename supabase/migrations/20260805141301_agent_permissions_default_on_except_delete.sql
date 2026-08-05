-- P2: agent permissions default ON, except deletion.
--
-- Every one of the 23 permission booleans defaulted to false, and all three
-- insert paths -- app.register_new_agent, app.create_business_with_owner and
-- app.request_join_business -- insert only `agent_id`. So a newly registered
-- agent came into being able to do nothing at all, and the Owner had to tick
-- 22 boxes before that agent could collect a single rupee. The column default
-- is the only lever any of those paths touch, which is why this migration
-- changes defaults and no application code.
--
-- can_delete_records stays FALSE, deliberately and permanently. Deleting a
-- record now rewrites the ledger chain and re-derives both BF pots
-- (20260805035332), so a delete is a money operation that moves closing
-- balances -- it is not the same class of thing as "can add a remark". An
-- Owner can still grant it explicitly; it just must never arrive by default.
ALTER TABLE agent_permissions
  ALTER COLUMN can_collect_payments      SET DEFAULT true,
  ALTER COLUMN can_issue_loans           SET DEFAULT true,
  ALTER COLUMN can_view_customers        SET DEFAULT true,
  ALTER COLUMN can_create_drafts         SET DEFAULT true,
  ALTER COLUMN can_edit_own_drafts       SET DEFAULT true,
  ALTER COLUMN can_cancel_own_drafts     SET DEFAULT true,
  ALTER COLUMN can_view_reports          SET DEFAULT true,
  ALTER COLUMN can_view_dashboard        SET DEFAULT true,
  ALTER COLUMN can_export_reports        SET DEFAULT true,
  ALTER COLUMN can_view_investor_info    SET DEFAULT true,
  ALTER COLUMN can_perform_day_settlement SET DEFAULT true,
  ALTER COLUMN can_access_collection_mode SET DEFAULT true,
  ALTER COLUMN can_upload_documents      SET DEFAULT true,
  ALTER COLUMN can_add_remarks           SET DEFAULT true,
  ALTER COLUMN can_transfer_collections  SET DEFAULT true,
  ALTER COLUMN can_apply_penalty         SET DEFAULT true,
  ALTER COLUMN can_create_customer       SET DEFAULT true,
  ALTER COLUMN can_edit_customer_contact SET DEFAULT true,
  ALTER COLUMN can_record_expenses       SET DEFAULT true,
  ALTER COLUMN can_migrate_records       SET DEFAULT true,
  ALTER COLUMN can_record_cheti          SET DEFAULT true;

-- can_delete_records is NOT listed above. Restated as an explicit no-op so a
-- future reader sees the omission was a decision, not an oversight.
ALTER TABLE agent_permissions ALTER COLUMN can_delete_records SET DEFAULT false;

-- NOTE, deliberately not done here: the five existing all-false permission
-- rows are left exactly as they are. "Never configured" and "the Owner
-- deliberately revoked everything" are indistinguishable in this table, and
-- guessing wrong grants an agent the ability to issue loans and record
-- collections against someone else's money. That backfill is the Owner's call,
-- not a migration's.
