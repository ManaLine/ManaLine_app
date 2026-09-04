/// A committed picture of the database's shape, so tests can check the app
/// against it without a network call.
///
/// WHY THIS EXISTS: three times in one week I wrote a string literal into SQL
/// for an enum column and invented a value that did not exist — `'General'`,
/// `'Self Request'`, `'Full Payment'`. Each applied perfectly and threw on the
/// function's first call, because plpgsql bodies are not type-checked at
/// CREATE time. Each was caught only because the CLAUDE.md rule says to invoke
/// a function before believing it. That rule works, and it depends entirely on
/// somebody remembering. This does not.
///
/// It also automates the PGRST203 rule the repo has been enforcing by hand:
/// changing an RPC's parameter list is DROP then CREATE, never CREATE OR
/// REPLACE, because a second overload makes PostgREST answer HTTP 300 rather
/// than choose. That has bitten five times. Counting is now a test.
///
/// GENERATED, NOT WRITTEN. Regenerate after any schema change:
///
/// ```sql
/// -- enums
/// select string_agg(line, E'\n' order by line) from (
///   select '  ' || quote_literal(t.typname) || ': [' ||
///          string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder) || '],' as line
///     from pg_type t join pg_enum e on e.enumtypid = t.oid
///     join pg_namespace n on n.oid = t.typnamespace and n.nspname = 'public'
///    group by t.typname) x;
///
/// -- function overloads
/// select string_agg('  ' || quote_literal(proname) || ': ' || cnt || ',', E'\n' order by proname)
///   from (select p.proname, count(*) cnt
///           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
///          where n.nspname = 'app' and p.prokind = 'f'
///          group by p.proname) x;
/// ```
///
/// A stale snapshot is not silently wrong: it fails as soon as the app calls
/// something the snapshot has never heard of, which is the moment to
/// regenerate.
library;

/// Every enum in `public`, and its values in declaration order.
const manaDbEnums = <String, List<String>>{
  'account_cycle_unit_enum': ['Days', 'Weeks', 'Months'],
  'account_period_status_enum': ['Running', 'Overdue', 'Submitted', 'Approved', 'Locked'],
  'account_status_enum': ['Active', 'Temporarily Disabled', 'Pending Deletion', 'Deleted'],
  'adjustment_applied_to_enum': ['Agent Salary Deduction', 'Customer Pending Settlement', 'Excess Ledger-Unresolved'],
  'adjustment_type_enum': ['Short', 'Excess'],
  'agent_current_status_enum': ['Active', 'Disabled', 'Suspended', 'Removed'],
  'agreement_source_type_enum': ['Uploaded PDF', 'In-App'],
  'agreement_type_enum': ['Customer', 'Agent', 'Investor'],
  'area_assignment_frequency_enum': ['Once', 'Weekly', 'Monthly'],
  'audit_action_type_enum': ['Settings Change', 'Permission Change', 'Loan Correction', 'Collection Correction', 'Membership Change', 'Day Reopen', 'PIN Approval', 'Password Reset', 'Account Approval', 'Other Admin Event', 'Session Start', 'Area Change'],
  'business_member_role_enum': ['Owner', 'Agent', 'Investor', 'Customer'],
  'business_status_enum': ['Active', 'Not Started', 'Suspended'],
  'business_transfer_status_enum': ['Pending', 'Accepted', 'Declined', 'Cancelled'],
  'cheti_frequency_enum': ['Daily', 'Weekly', 'Monthly'],
  'cheti_status_enum': ['Running', 'Completed'],
  'cheti_type_enum': ['Fixed', 'Auction'],
  'collection_result_type_enum': ['Full', 'Partial', 'Excess', 'No Collection'],
  'customer_document_type_enum': ['Aadhaar', 'Photo', 'Address Proof', 'Customer Agreement', 'Loan Agreement', 'Guarantor Document', 'Other'],
  'customer_status_enum': ['Active', 'Inactive', 'Deceased'],
  'customer_type_enum': ['New', 'Migrated'],
  'day_ledger_status_enum': ['Open', 'Closed'],
  'distribution_recipient_type_enum': ['Agent', 'Investor'],
  'distribution_status_enum': ['Declared', 'Paid'],
  'draft_status_enum': ['Draft', 'Submitted', 'Discarded'],
  'draft_type_enum': ['Collection', 'Loan Distribution', 'Customer Remark', 'Document Upload'],
  'duplicate_detection_method_enum': ['System-Automatic', 'Owner-Manual'],
  'duplicate_suspect_status_enum': ['Open', 'Resolved-Merged', 'Resolved-Not Duplicate'],
  'excess_disposition_enum': ['Advance', 'Refund', 'Next Installment'],
  'expense_category_enum': ['General', 'Travel', 'Salary', 'Fuel', 'Other'],
  'extension_requested_by_enum': ['Customer', 'Agent'],
  'extension_status_enum': ['Pending', 'Approved', 'Rejected'],
  'guarantor_status_enum': ['Active', 'Removed'],
  'identity_document_type_enum': ['Aadhaar', 'Photo', 'Address Proof', 'Other'],
  'interest_ledger_entry_type_enum': ['Accrual Snapshot', 'Payment', 'Compounding Event'],
  'investment_interest_type_enum': ['Simple', 'Yearly Compound'],
  'investment_status_enum': ['Active', 'Closed'],
  'loan_request_status_enum': ['Pending', 'Approved', 'Rejected'],
  'loan_schedule_status_enum': ['Pending', 'Completed', 'Partial'],
  'loan_status_enum': ['Draft', 'Active', 'Grace Period', 'Penalty', 'Closed', 'Cancelled', 'Defaulted'],
  'loan_template_status_enum': ['Active', 'Inactive'],
  'location_area_type_enum': ['Village', 'Town'],
  'location_status_enum': ['Active', 'Inactive'],
  'membership_request_role_enum': ['Customer', 'Investor', 'Agent'],
  'membership_request_status_enum': ['Pending', 'Approved', 'Rejected'],
  'membership_status_enum': ['Pending Invitation', 'Pending Acceptance', 'Active', 'Temporarily Disabled', 'Suspended', 'Removed', 'Pending Approval'],
  'membership_verification_status_enum': ['Not Required', 'Pending Verification', 'Verified'],
  'mlid_type_enum': ['MLPI', 'MLTI'],
  'no_collection_reason_enum': ['Customer Not Home', 'House Locked', 'Customer Out Of Village', 'Requested Extension', 'Medical Emergency', 'Festival', 'Natural Disaster', 'Phone Call Not Answered', 'Shifted Village', 'Refused Payment', 'Other'],
  'notification_type_enum': ['New Device Login', 'Capacity Overflow', 'Owner Approval Confirmation', 'Pending Approval', 'Pending Loan Request', 'Pending Membership Request', 'Pending Withdrawal Request', 'Pending Online Payment', 'Account Period Due', 'Account Period Overdue', 'Incomplete Profile', 'Penalty Applied', 'Extension Request', 'Profit Share Declared', 'Profit Share Paid', 'Customer Address Updated', 'Other'],
  'occupation_enum': ['Farmer', 'Milk Vendor', 'Auto Driver', 'Tea Shop', 'Tailor', 'Daily Wage', 'Government Employee', 'Private Employee', 'Business', 'Housewife', 'Student', 'Retired', 'Other-Custom'],
  'onboarding_method_enum': ['Direct Registration', 'ID Lookup', 'Migration/Pre-Existing'],
  'online_payment_status_enum': ['Submitted', 'Confirmed', 'Not Received-Disputed'],
  'operating_area_status_enum': ['Active', 'Inactive'],
  'otp_purpose_enum': ['Registration', 'Role Escalation', 'Password Reset', 'PIN Reset', 'Account Unlock', 'Agreement Acceptance'],
  'otp_status_enum': ['Sent', 'Verified', 'Expired'],
  'payer_type_enum': ['Customer', 'Guarantor', 'Others'],
  'payment_mode_enum': ['Cash', 'UPI', 'Bank Transfer', 'Cheque'],
  'penalty_option_enum': ['Flat Amount', '% of Overdue Installment', '% of Remaining Balance'],
  'preferred_language_enum': ['English', 'Telugu', 'Hindi', 'Tamil', 'Kannada'],
  'profile_status_enum': ['Complete', 'Incomplete', 'Pending Verification', 'Archived'],
  'registration_source_enum': ['Owner', 'Agent', 'Migration', 'System'],
  'remark_priority_enum': ['Normal', 'High'],
  'repayment_frequency_enum': ['Daily', 'Weekly', 'Monthly'],
  'route_status_enum': ['Active', 'Inactive'],
  'salary_cycle_enum': ['Monthly', 'Custom'],
  'salary_ledger_status_enum': ['Pending', 'Paid'],
  'salary_mode_enum': ['Fixed', 'Daily Rate'],
  'settlement_cycle_type_enum': ['Daily', 'Weekly', 'Monthly'],
  'settlement_status_enum': ['Pending Owner Review', 'Approved', 'Returned'],
  'verification_ring_enum': ['GREEN', 'RED'],
  'withdrawal_request_status_enum': ['Pending', 'Approved-Paid', 'Rejected'],
  'withdrawal_type_enum': ['Interest Only', 'Principal Partial', 'Principal Full', 'Principal + Interest'],
};

/// How many overloads each `app.` function has.
///
/// Anything the app calls through `.rpc()` must be 1 — PostgREST cannot choose
/// between two and answers HTTP 300 (PGRST203). Functions used only inside RLS
/// policies and other SQL never reach PostgREST, so an overload there is
/// harmless; see [manaInternalOnlyOverloads].
const manaAppFunctionOverloads = <String, int>{
  'own_active_agent_membership_permits': 2,
};

/// Functions with more than one overload that are NEVER called through
/// `.rpc()` — they are used from inside SQL, where overload resolution is
/// Postgres's job and works fine.
///
/// Listed rather than ignored: if one of these ever gains a Dart caller, the
/// test below fails and the DROP-then-CREATE rule applies to it too.
const manaInternalOnlyOverloads = <String>{
  'own_active_agent_membership_permits',
};

/// Every `app.` function that exists. Membership is what the RPC-name check
/// tests against; a call to something not in here is a 404 waiting to happen.
const manaAppFunctions = <String>{
  'aadhaar_hash', 'account_period_window', 'active_membership_id',
  'add_area_to_session', 'add_location_if_missing', 'admin_delete_business',
  'admin_delete_collection', 'admin_delete_loan', 'admin_delete_person',
  'admin_lookup_business', 'admin_lookup_collection', 'admin_lookup_loan',
  'admin_lookup_person', 'agent_covers_customer', 'agent_covers_loan',
  'agent_expected_closing', 'agent_payable_salary', 'agent_permission',
  'agent_update_customer_address', 'agent_update_customer_phone',
  'amend_collection', 'anonymise_person', 'apply_investment_compounding',
  'apply_loan_penalty', 'approve_agent_settlement',
  'assert_business_transferable', 'assign_agent_area', 'attach_investor',
  'attach_investor_with_first_investment', 'avail_cheti',
  'bulk_import_identities', 'bulk_import_investments',
  'business_id_for_customer', 'business_id_for_loan',
  'business_id_for_membership', 'business_investor_payable_balance',
  'business_profit', 'can_apply_penalty_on_loan', 'cancel_business_transfer',
  'clear_aadhaar_on_erasure', 'close_business_day', 'close_loan',
  'collection_entry_window', 'compare_address_gps', 'confirm_bf_assignment',
  'confirm_cash_transfer', 'covering_agent_membership_id',
  'create_business_with_owner', 'create_loan_with_bf_check', 'current_admin_id',
  'current_person_id', 'customer_id_from_object_name', 'customer_line_score',
  'day_closure_expected', 'deactivate_operating_area',
  'decide_agent_bf_request', 'decide_extension', 'decide_membership_request',
  'delete_investment', 'disable_own_account', 'discover_businesses',
  'edit_investment', 'ensure_agent_bf_assignment', 'find_or_create_location',
  'find_or_create_village', 'find_potential_duplicate_customers',
  'get_investment_statement', 'global_person_search', 'grant_agent_bf',
  'grant_grace_period', 'hash_person_aadhaar', 'idempotent_replay',
  'idempotent_store', 'import_migrated_loans', 'import_migrated_withdrawals',
  'import_shareholders', 'import_weekly_account', 'initiate_cash_transfer',
  'investment_daily_interest', 'investment_interest_snapshot',
  'is_active_agent', 'is_active_customer', 'is_active_investor',
  'is_own_customer_row', 'is_own_investment_row', 'is_owner',
  'is_owner_of_any_shared_business', 'is_platform_admin', 'ledger_day_balances',
  'ledger_history', 'ledger_month_summary', 'list_agent_areas',
  'list_recent_deletes', 'loan_penalty_eligible_from', 'lock_migration',
  'mana_interest', 'may_delete_records', 'membership_belongs_to_current_person',
  'membership_is_active', 'migrate_loan', 'migrated_expense_lines',
  'migration_assert_open', 'migration_clear_derived_days',
  'migration_create_areas', 'migration_import_active', 'migration_plan_gaps',
  'migration_profit_summary', 'migration_progress',
  'migration_record_attendance', 'migration_summary',
  'migration_upsert_villages', 'migration_wizard_step', 'mint_person_mlid',
  'my_business_transfers', 'my_inbox_actions', 'onboarding_method_now',
  'open_business_day', 'own_account_status',
  'own_active_agent_membership_permits', 'owner_mark_member_profile_complete',
  'owner_member_profile_checklist', 'owner_owns_member_folder',
  'owner_owns_pending_or_active_member', 'owner_search_loan_candidate',
  'owner_search_person', 'owner_search_person_by_mlid',
  'owner_update_customer_address', 'owner_update_customer_phone',
  'owner_update_member_identity', 'owner_upload_member_document',
  'pay_out_withdrawal_request', 'penalty_collected_by_day',
  'person_current_village', 'person_delete_blockers',
  'person_has_financial_ties', 'profit_share_accrued',
  'purge_dependents', 'purge_due_accounts', 'purge_expired_deletes',
  'purge_person_hard', 'purge_record', 'purge_records',
  'reactivate_own_account', 'recompute_agent_bf', 'recompute_business_bf',
  'recompute_day_ledger', 'recompute_day_ledger_onward',
  'recompute_ledger_chain', 'record_cheti_payment', 'record_collection',
  'record_day_closure_adjustment', 'record_expense', 'record_investment',
  'record_investment_interest_payment', 'record_opening_snapshot',
  'refresh_day_ledger', 'register_new_agent', 'register_new_customer',
  'register_new_investor', 'remove_area_from_session',
  'remove_customer_membership', 'remove_operating_area', 'reopen_migration',
  'request_account_deletion', 'request_agent_bf', 'request_bf_update',
  'request_business_transfer', 'request_join_business', 'resolve_deletable',
  'respond_business_transfer', 'respond_to_invitation',
  'respond_to_membership_request',
  'restore_record', 'return_settlement', 'review_investor_request',
  'search_business_by_mlbi', 'search_businesses_by_name', 'set_migration_plan',
  'set_migration_wizard_step', 'set_opening_bf', 'settlement_preview',
  'shares_active_business', 'soft_delete_record', 'stamp_membership_removed_at',
  'stamp_migrated_person', 'start_business_session', 'submit_agent_settlement',
  'submit_draft', 'suggest_villages', 'support_fetch_latest_id_history',
  'support_lookup_person', 'support_suspend_business',
  'support_suspend_membership', 'support_suspension_impact',
  'support_unsuspend_business', 'support_unsuspend_membership',
  'support_upgrade_mlid_dispute', 'support_upload_identity_document',
  'sync_person_name', 'tg_recompute_day_ledger', 'update_collection_gps',
  'update_customer_address_from_gps', 'update_loan_gps', 'village_at_point',
  'waive_loan_penalty', 'withdraw_from_investment',
};

/// Every enum-typed column in `public`, and which enum it is.
///
/// Exists so a literal written into migration SQL can be checked without a
/// database. `manaDbEnums` already knows what values each enum allows; this is
/// the missing half — which columns those values apply to.
///
/// THE GAP THIS CLOSES, which CLAUDE.md listed as uncovered: plpgsql bodies are
/// not type-checked at CREATE time, so an invented enum literal applies cleanly
/// and throws on the function's FIRST CALL. Four times now — 'General',
/// 'Self Request', 'Full Payment', and 'Other' for occupation_enum, which made
/// approving a Customer's request to join fail every time for months while the
/// Investor path beside it worked.
const manaEnumColumns = <String, String>{
  'account_periods.status': 'account_period_status_enum',
  'account_settlements.cycle_type': 'settlement_cycle_type_enum',
  'account_settlements.status': 'settlement_status_enum',
  'agent_area_assignments.frequency': 'area_assignment_frequency_enum',
  'agent_compensation_history.salary_cycle': 'salary_cycle_enum',
  'agent_compensation_history.salary_mode': 'salary_mode_enum',
  'agent_documents.document_type': 'customer_document_type_enum',
  'agent_salary_ledger.status': 'salary_ledger_status_enum',
  'agents.current_status': 'agent_current_status_enum',
  'audit_log.action_type': 'audit_action_type_enum',
  'business_agreements.agreement_type': 'agreement_type_enum',
  'business_agreements.source_type': 'agreement_source_type_enum',
  'business_members.membership_status': 'membership_status_enum',
  'business_members.onboarding_method': 'onboarding_method_enum',
  'business_members.role': 'business_member_role_enum',
  'business_members.verification_status': 'membership_verification_status_enum',
  'business_transfers.status': 'business_transfer_status_enum',
  'businesses.business_status': 'business_status_enum',
  'chetis.cheti_type': 'cheti_type_enum',
  'chetis.frequency': 'cheti_frequency_enum',
  'chetis.status': 'cheti_status_enum',
  'collection_drafts.draft_type': 'draft_type_enum',
  'collection_drafts.status': 'draft_status_enum',
  'collection_payment_splits.payment_mode': 'payment_mode_enum',
  'collections.excess_disposition': 'excess_disposition_enum',
  'collections.payer_type': 'payer_type_enum',
  'collections.result_type': 'collection_result_type_enum',
  'customer_documents.document_type': 'customer_document_type_enum',
  'customer_online_payments.status': 'online_payment_status_enum',
  'customer_remarks.priority': 'remark_priority_enum',
  'customers.customer_status': 'customer_status_enum',
  'customers.occupation': 'occupation_enum',
  'day_ledger.status': 'day_ledger_status_enum',
  'distribution_declarations.recipient_type': 'distribution_recipient_type_enum',
  'distribution_declarations.status': 'distribution_status_enum',
  'duplicate_suspects.detection_method': 'duplicate_detection_method_enum',
  'duplicate_suspects.status': 'duplicate_suspect_status_enum',
  'expenses.category': 'expense_category_enum',
  'extension_requests.requested_by': 'extension_requested_by_enum',
  'extension_requests.status': 'extension_status_enum',
  'guarantors.status': 'guarantor_status_enum',
  'identity_documents.document_type': 'identity_document_type_enum',
  'investment_interest_ledger.entry_type': 'interest_ledger_entry_type_enum',
  'investment_withdrawal_requests.status': 'withdrawal_request_status_enum',
  'investment_withdrawal_requests.withdrawal_type': 'withdrawal_type_enum',
  'investment_withdrawals.withdrawal_type': 'withdrawal_type_enum',
  'investments.interest_type': 'investment_interest_type_enum',
  'investments.status': 'investment_status_enum',
  'loan_remarks.priority': 'remark_priority_enum',
  'loan_requests.preferred_frequency': 'repayment_frequency_enum',
  'loan_requests.status': 'loan_request_status_enum',
  'loan_schedule.status': 'loan_schedule_status_enum',
  'loan_templates.repayment_frequency': 'repayment_frequency_enum',
  'loan_templates.status': 'loan_template_status_enum',
  'loans.loan_status': 'loan_status_enum',
  'loans.repayment_type': 'repayment_frequency_enum',
  'locations.area_type': 'location_area_type_enum',
  'locations.status': 'location_status_enum',
  'membership_requests.requested_role': 'membership_request_role_enum',
  'membership_requests.status': 'membership_request_status_enum',
  'no_collection_visits.reason': 'no_collection_reason_enum',
  'notifications.notification_type': 'notification_type_enum',
  'operating_areas.account_cycle_unit': 'account_cycle_unit_enum',
  'operating_areas.status': 'operating_area_status_enum',
  'otp_verifications.purpose': 'otp_purpose_enum',
  'otp_verifications.status': 'otp_status_enum',
  'penalty_entries.penalty_option': 'penalty_option_enum',
  'persons.account_status': 'account_status_enum',
  'persons.customer_type': 'customer_type_enum',
  'persons.mlid_type': 'mlid_type_enum',
  'persons.preferred_language': 'preferred_language_enum',
  'persons.profile_status': 'profile_status_enum',
  'persons.registration_source': 'registration_source_enum',
  'persons.verification_ring': 'verification_ring_enum',
  'routes.status': 'route_status_enum',
  'settlement_adjustments.adjustment_type': 'adjustment_type_enum',
  'settlement_adjustments.applied_to': 'adjustment_applied_to_enum',
};
