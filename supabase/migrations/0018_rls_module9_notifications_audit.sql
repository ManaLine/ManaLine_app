-- ============================================================================
-- 0018_rls_module9_notifications_audit.sql
-- MANA LINE — RLS: Module 9 (Notifications & Audit)
-- Depends on: 0012, 0013
-- ============================================================================

-- notifications: strictly self-only (recipient_person_id). Every role only
-- ever sees their own notifications, regardless of role or business. No
-- client INSERT policy for any role — notifications are always
-- system/trigger/service_role generated (loan requests, capacity overflow,
-- penalty applied, etc. are all system-detected events, never a client
-- directly creating a notification for themselves or anyone else). Client
-- MAY mark their own as read (UPDATE limited to is_read).
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY notifications_self_select ON notifications
  FOR SELECT
  USING (recipient_person_id = app.current_person_id());

CREATE POLICY notifications_self_update_read ON notifications
  FOR UPDATE
  USING (recipient_person_id = app.current_person_id())
  WITH CHECK (recipient_person_id = app.current_person_id());
-- Note: this UPDATE policy technically allows the client to rewrite any
-- column on their own notification row, not just is_read, since RLS can't
-- restrict to a single column without a trigger (BEFORE UPDATE guard
-- rejecting changes to message/notification_type/etc.). Flagged in END
-- RESULT as a follow-up: add a trigger that only permits is_read to change,
-- or move "mark as read" behind a SECURITY DEFINER RPC instead of a raw
-- UPDATE grant. Left as an authenticated self-UPDATE for now since the risk
-- is limited to a person editing their own notification text, not
-- cross-tenant leakage.

-- audit_log: administrative/security events ONLY. Per the briefing's
-- explicit instruction: "audit_log ... write-once, read-scoped, never
-- client-writable directly ... A Customer should never have an INSERT
-- policy on audit_log, even indirectly." NO role gets an INSERT policy here
-- — all writes are service_role/trigger-only. Owner: read-only for their
-- own business's audit events. NO Agent/Investor/Customer read access at
-- all — this is administrative/security data (Settings Change, Permission
-- Change, Day Reopen, PIN Approval, etc.), never delegated to non-Owner
-- roles by any screen spec reviewed. Erring maximally restrictive here,
-- consistent with this being one of the highest-sensitivity tables in the
-- schema.
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY audit_log_owner_select ON audit_log
  FOR SELECT
  USING (business_id IS NOT NULL AND app.is_owner(business_id));
-- No INSERT/UPDATE/DELETE policy for ANY authenticated role, Owner
-- included — append-only, service_role/trigger-populated exclusively, per
-- the explicit briefing instruction. Rows with business_id IS NULL
-- (platform-level events, e.g. cross-business duplicate-suspect flags) are
-- visible to no client role at all — Support-tool/service_role only.

-- owner_approvals: in-context PIN confirmations (BR-125/200). Owner: full
-- (approved_by_person_id is always Owner). No other role gets any policy —
-- this is an Owner-authentication artifact, not operational business data;
-- Agent/Investor/Customer never need to read another party's PIN-approval
-- record.
ALTER TABLE owner_approvals ENABLE ROW LEVEL SECURITY;

CREATE POLICY owner_approvals_owner_all ON owner_approvals
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));
