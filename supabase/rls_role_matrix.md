# MANA LINE — RLS ROLE MATRIX
Companion document to migrations `0012`–`0018`. For every table: who gets
SELECT/INSERT/UPDATE/DELETE, under what condition, and — per the briefing's
instruction — what the policy specifically *prevents*. Policy names below
match the `{table}_{role}_{action}` names in the migration files exactly.

Legend: **O**=Owner, **A**=Agent, **I**=Investor, **C**=Customer.
No table anywhere grants DELETE to any authenticated role — the schema has
no hard-delete workflow anywhere (BR-002/127); "removal" is always a status
flag. RLS is `ENABLE`d on every table in this document; where a role has no
row below for a table, that role has zero access (deny-all default).

---

## MODULE 0 — IDENTITY NETWORK

### persons
- O/A (`persons_business_partner_select`): SELECT any person with an Active
  membership in a business where requester is Active Owner, or Active Agent
  with `can_view_customers`. **Prevents:** reading anyone with no shared
  active business membership — no global people-search via this table.
- Self (`persons_self_select/update`): full read, own-row update only.
- I/C: no business-partner policy — Investors/Customers never read another
  person's identity row. **Prevents:** Customer/Investor enumeration of
  other members.
- No INSERT/DELETE for any role — registration is service_role only.

### person_id_history
- O: SELECT for persons who share an active business with them.
- Self: SELECT own history.
- **No INSERT for any role, Owner included** — write-once, trigger-populated
  only, per explicit briefing instruction. **Prevents:** any client
  fabricating an MLID-upgrade history row.

### person_addresses
- Self: full (read/write own addresses).
- O/A(`can_view_customers`): SELECT for shared-business partners.
- **Prevents:** I/C never see another person's address; A without
  `can_view_customers` sees none.

### devices
- Self only, full access. **Prevents:** literally everyone else, including
  Owner — device fingerprints are a security control surface, not business
  data.

### otp_verifications
- Self: SELECT only. **No INSERT/UPDATE for anyone** — OTP issuance/
  verification must go through a server-side function that can check codes
  and rate-limit. **Prevents:** any client marking their own OTP "Verified"
  without actually verifying.

### identity_documents
- Self: full. O/A(`can_view_customers`): SELECT for shared-business
  partners. Same shape as person_addresses.

### duplicate_suspects
- **No policy for any client role.** RLS enabled = deny-all. This is a
  Support/back-office table; all access via service_role until a Support
  tool auth model exists (flagged as open item below).

---

## MODULE 1 — TENANCY / BUSINESS

### businesses
- O: full on own business(es).
- A/I/C: SELECT only, only while their own membership is Active.
  **Prevents:** reading a business you hold no active membership in;
  public "Find A Business" browse (CW-002/IW-002) must use a
  SECURITY DEFINER RPC, not a direct table grant — flagged as integration
  note below.

### locations
- Any authenticated user: SELECT (shared master reference data, not
  tenant-scoped). No client write policy — platform-managed.

### operating_areas
- O: full. A: SELECT if `can_view_dashboard` OR assigned to that area via
  `agent_area_assignments`. **Prevents:** an Agent with neither dashboard
  access nor an area assignment seeing operating areas at all.

### routes / route_locations
- O: full. A: SELECT only for routes where they are `default_agent_id`.
  **Prevents:** an Agent seeing another Agent's routes.

### business_agreements
- O: full. A/I/C: SELECT any agreement template for their own active
  business (legal text, low sensitivity — not role-siloed).

### agreement_acceptances
- Self: SELECT + INSERT own acceptance only. O: SELECT for their business's
  agreements. **No UPDATE/DELETE for anyone** — permanent record.

### business_members
- O: full within own business.
- Self: SELECT own membership rows across *any* business (BR-208
  role-switcher needs this).
- A(`can_view_customers`): SELECT **only** Customer-role rows where
  `customers.assigned_agent_membership_id` = the Agent's own membership.
  **Prevents:** an Agent seeing Owner/other-Agent/Investor membership rows,
  or Customer rows not assigned to them — this is the single most important
  negative case in the whole schema (BR-202/203 multi-tenancy + AG-004
  scoping combined).

### membership_requests
- Self: SELECT + INSERT own requests. O: full for requests targeting their
  business.

### account_periods
- O: full. A: SELECT only for periods where `agent_membership_id` is their
  own. **No client INSERT/UPDATE for Agent** — submission must go through a
  SECURITY DEFINER RPC (flagged below); RLS alone can't safely restrict
  which status transitions/columns an Agent may touch.

---

## MODULE 2 — LOAN TEMPLATES

### loan_templates
- O: full. A(`can_issue_loans`): SELECT. C: SELECT, **Active status only**
  (never sees Inactive templates). **Prevents:** Customer picking a
  retired/inactive template at loan-request time.

---

## MODULE 3 — CUSTOMER DOMAIN

### customers
- O: full. A: SELECT/UPDATE(contact only) scoped to
  `assigned_agent_membership_id` = own, gated `can_view_customers` /
  `can_edit_customer_contact` respectively. Self: SELECT own row.
  **Prevents:** Agent A2 (not assigned) reading Customer X's row even
  though X is in the same business as A2. Customer creation is **not** a
  raw INSERT grant — must go through a `can_create_customer`-gated RPC
  (flagged below).

### guarantors
- O: full. A: full, scoped to loans of their assigned customers, gated
  `can_view_customers`(read)/`can_issue_loans`(write). C: SELECT own loans'
  guarantors only.

### customer_remarks
- O: full. A: SELECT(`can_view_customers`)/INSERT(`can_add_remarks`),
  assigned customers only. **No Customer access at all** — internal
  operational notes, never customer-visible. **No UPDATE/DELETE for
  anyone** — append-only per spec.

### customer_documents
- O: full. A: SELECT(`can_view_customers`)/INSERT(`can_upload_documents`),
  assigned customers only. Self (Customer): SELECT + INSERT own documents,
  no UPDATE (archival is Owner/Agent-only).

---

## MODULE 4 — AGENT DOMAIN

### agents
- O: full. Self: SELECT own row. **No I/C access at all** — matches
  briefing's "Investor: no access to Agent/Customer operational data".

### agent_compensation_history (FINANCIALLY SENSITIVE)
- O: full. Self (Agent): SELECT own compensation only. **No other Agent, no
  Investor, no Customer ever sees this table.** **Prevents:** Agent-to-Agent
  salary snooping; Investor visibility into agent pay (not granted by any
  spec — defaulted to no access per briefing instruction).

### agent_permissions
- O: full (this *is* the toggle table, OW-002 C5d). Self (Agent): SELECT
  only — **explicitly no self-UPDATE**, which would be a privilege
  escalation hole (an Agent granting themselves permissions).

### agent_area_assignments
- O: full. Self: SELECT own assignments.

### agent_documents
- O: full. Self (Agent): full (own documents).

### cash_transfers
- O: full, either party's business. A: SELECT only, as `from_agent_id` or
  `to_agent_id`. **No client UPDATE for Agent** — confirmation should go
  through a SECURITY DEFINER RPC (flagged below), since RLS can't cleanly
  restrict which columns an UPDATE may touch.

---

## MODULE 5 — INVESTOR DOMAIN

### investors
- O: full. Self: SELECT own row. **No A/C access.**

### investments
- O: full. I: SELECT own investments only (`investors.person_id` = self).
  A: SELECT, business-wide, **only if** `can_view_investor_info` (no
  assigned-investor concept exists anywhere in the schema, unlike
  Agent↔Customer, so this permission is necessarily business-wide by
  design — flagged as an accepted design constraint, not an oversight).
  **Prevents:** Investor 1 ever seeing Investor 2's investment row; Agent
  without the flag seeing any investor data.

### investment_interest_ledger / investment_withdrawals (FINANCIALLY SENSITIVE)
- O: full. I: SELECT own investments' rows only.
  `investment_withdrawals`: **no Agent access at all** (Owner↔Investor
  financial transaction, no spec grants Agent visibility — defaulted
  restrictive). `investment_interest_ledger`: Agent SELECT mirrors
  `investments` (`can_view_investor_info`), consistent scope, no write.

### investment_withdrawal_requests
- O: full. I: SELECT + INSERT, own requests on own investments only.

### distribution_declarations / distribution_payments (FINANCIALLY SENSITIVE)
- O: full. A: SELECT own rows only (`recipient_type='Agent'` AND
  `agent_id` = self). I: SELECT own rows only (`recipient_type='Investor'`
  AND investment = own). **Prevents:** Agent seeing Investor distributions
  or another Agent's; Investor seeing Agent distributions or another
  Investor's — this is the table where a copy-paste mistake would most
  easily leak profit-share data across roles, so both `recipient_type` and
  ownership are checked together in every policy.

---

## MODULE 6 — LOAN DOMAIN

### loans
- O: full. A: SELECT(`can_view_customers`)/INSERT(`can_issue_loans`),
  assigned customers only. C: SELECT own loans only.

### loan_schedule
- Mirrors `loans` visibility exactly via the parent loan (installments are
  no more sensitive than the loan itself; CW-004 explicitly shows the full
  schedule to Customers).

### loan_cancellations
- O: full. A: full, assigned customers' loans, gated `can_issue_loans`.
  **No Customer access** — internal pre-handover action, never customer-
  facing.

### loan_requests
- O: full (approve/reject). A: **SELECT only** (judgment call — screens
  describe this as an Owner decision queue; Agent can see but not action).
  C: SELECT + INSERT own requests.

### extension_requests
- O: full (decision is always Owner's). A: full for assigned customers'
  loans, `can_view_customers`, INSERT restricted to `requested_by='Agent'`.
  C: SELECT + INSERT own loans only, restricted to `requested_by='Customer'`.
  **Prevents:** either party inserting a row falsely attributed to the
  other's `requested_by` value.

### penalty_entries
- O: full. A: SELECT(`can_view_customers`)/INSERT(`can_apply_penalty` —
  **off by default per BR-236**, so this is intentionally hard to satisfy
  until an Owner explicitly enables it). C: SELECT own loans' penalties.

---

## MODULE 7 — COLLECTION DOMAIN

### collections
- O: full. A: SELECT(`can_view_customers`)/INSERT(`can_collect_payments`),
  assigned customers, and INSERT is further constrained so
  `collected_by_membership_id` must equal the inserting Agent's own active
  membership (**prevents** an Agent recording a collection under another
  Agent's name). C: SELECT own loans' collections.

### collection_payment_splits
- Mirrors parent `collections` visibility/write scope exactly.

### no_collection_visits
- O: full. A: full, assigned customers, gated `can_access_collection_mode`,
  and `visited_by_membership_id` pinned to self on write. **No Customer
  access** — internal field-ops log.

### collection_drafts
- O: full. A: SELECT/INSERT(`can_create_drafts`)/UPDATE(`can_edit_own_drafts`
  or `can_cancel_own_drafts`) — **all scoped to `created_by_membership_id`
  = self only.** **Prevents:** Agent A2 reading or editing Agent A1's
  in-progress draft, even in the same business. **No I/C access at all.**

### customer_online_payments
- O: full. A: SELECT(`can_view_customers`)/UPDATE-confirm
  (`can_collect_payments`, `confirmed_by_person_id` pinned to self), assigned
  customers. C: SELECT + INSERT own submissions only.

---

## MODULE 8 — FINANCE / CASH / DAY CLOSURE
*(No Customer or Investor policy anywhere in this module — internal
business-cash figures, per the briefing's explicit "Customer: zero
visibility into business-internal figures" instruction. Deliberately
restrictive by default throughout.)*

### expenses
- O: full. A: SELECT/INSERT own entries only
  (`recorded_by_membership_id`=self), gated `can_perform_day_settlement`
  — **judgment call**: no screen spec names an explicit
  "can_record_expenses" flag; this is the closest fit since expenses affect
  day-level cash totals. Flagged for confirmation.

### day_ledger (FINANCIALLY SENSITIVE, business-wide aggregate)
- O: full. A: SELECT only, gated `can_view_reports` (report-hub-adjacent,
  not a per-agent figure so no "own entries" scoping is possible). **No
  client write for Agent** — system-computed only.

### day_closures
- **O only, full stop** — schema explicitly marks `closed_by`/`reopened_at`
  as Owner-only (BR-221). No Agent policy at all.

### account_settlements (FINANCIALLY SENSITIVE)
- O: full. A: SELECT + INSERT **own** settlement rows only
  (`agent_id`=self), INSERT constrained to `status='Pending Owner Review'`
  (**prevents** an Agent self-approving). **No Agent UPDATE at all** —
  approve/return is Owner-exclusive.

### settlement_adjustments (FINANCIALLY SENSITIVE — named explicitly in briefing)
- O: full — "Owner-controlled, never automatic" per schema. A: SELECT own
  rows only. **No write access for Agent at all. No Customer/Investor
  access even when `target_customer_id` references them** — internal
  accounting adjustment, not a customer statement. Erred maximally
  restrictive per briefing instruction.

### agent_salary_ledger (FINANCIALLY SENSITIVE — named explicitly in briefing)
- O: full. A: SELECT own rows only. **No write access for Agent at all.**

### salary_advances
- O: full. A: SELECT own advances only. **No client Agent INSERT** —
  advances are always Owner-entered per every screen reference reviewed.

### agent_access_days
- O: full (grants/edits). A: SELECT own rows only.

### agent_bf_assignments
- O: full (sets opening/current BF). A: SELECT own rows only. **No Agent
  UPDATE** — session-start confirmation (`confirmed_by_agent`/
  `update_requested`) should go through a SECURITY DEFINER RPC, not a raw
  column-scoped UPDATE grant (flagged below).

### loan_groups / loan_group_members
- O: full. A: SELECT/INSERT(`loan_groups` only) gated `can_issue_loans`,
  scoped to groups they created (loan_groups) or member loans they cover
  (loan_group_members, following the guarantors pattern). C: SELECT own
  loans' group membership only (needed to render Group Balance/EMI
  aggregates on their own loan).

---

## MODULE 9 — NOTIFICATIONS & AUDIT

### notifications
- Self: SELECT + UPDATE (mark-read) own notifications only. **No INSERT
  for any role** — system/service_role generated exclusively. **Known
  gap:** the self-UPDATE policy can't restrict to only the `is_read`
  column at the RLS layer; flagged below as needing either a trigger guard
  or an RPC.

### audit_log
- **O: SELECT only**, for their own business's rows. **No INSERT/UPDATE/
  DELETE for ANY role, Owner included** — append-only, service_role/
  trigger-populated exclusively, per explicit briefing instruction.
  **No Agent/Investor/Customer read access at all.** Rows with
  `business_id IS NULL` (platform-level events) are visible to no client
  role. This is the single most restrictive table in the schema, by
  design.

### owner_approvals
- **O only, full stop.** In-context PIN-confirmation artifact — no other
  role has any legitimate reason to read it.

---

## SUMMARY FOR MASTER CHAT

### Judgment calls made on ambiguous scope (always erred restrictive)
1. `expenses` INSERT for Agent — gated on `can_perform_day_settlement` in
   absence of a dedicated flag. Confirm intended flag.
2. `duplicate_suspects` — no client policy at all; Support-tool-only via
   service_role until that tool's own auth model exists.
3. `loan_requests` — Agent gets SELECT, not INSERT/UPDATE, treating it as
   an Owner decision queue per CW-003 language ("Owner decision").
4. `investments`/`investment_interest_ledger` Agent visibility via
   `can_view_investor_info` is necessarily business-wide (no
   assigned-investor concept exists in the schema) — accepted as a design
   constraint, not narrowed further.
5. `settlement_adjustments`, `agent_salary_ledger`,
   `investment_withdrawals`, `agent_compensation_history` — all
   deliberately given zero cross-role visibility beyond Owner + the
   directly-affected Agent/Investor's own rows, per the briefing's
   "financially sensitive, default to no access" instruction.

### Tables left without a role-specific write policy (RPC required instead)
RLS alone cannot safely express "only this specific column may change" or
"only this specific status transition is valid" — these need a
SECURITY DEFINER function/RPC layer on top of RLS, not a raw UPDATE grant:
- `account_periods` — Agent submission (status → 'Submitted')
- `cash_transfers` — Agent confirmation timestamps
- `agent_bf_assignments` — Agent session-start confirm/update-request flags
- `notifications` — mark-as-read (currently a full self-UPDATE grant with a
  flagged risk, not yet hardened)
- `customers` creation (`can_create_customer`) — needs an atomic
  membership+customer-row creation transaction, not a plain INSERT grant

### Tables/columns assumed from the schema doc — confirm against actual DDL
- Every table/column referenced above is taken from `03_Database_Schema.md`
  as attached to this session. **None of it has been checked against the
  schema-migration chat's actual `0001`–`0011` output**, per the briefing
  ("build against the doc... master chat needs to confirm"). Specifically
  flag: `businesses.owner_person_id`, `business_members.membership_status`
  enum values (esp. 'Active' exact spelling), `customers
  .assigned_agent_membership_id`, `agents.membership_id`,
  `investors.membership_id`, all `agent_permissions.*` boolean column names
  (used via dynamic lookup in `app.agent_permission()` — a renamed column
  there will silently return FALSE, not error, so this needs a smoke test
  per flag).
- `agent_access_days`, `agent_bf_assignments`, `loan_groups`,
  `loan_group_members` — these come from the "MERGED ADDENDUM" section of
  the schema doc, not the main numbered module list; confirm they were
  actually created by the schema-migration chat under these exact names.

### Auth integration — the single biggest open dependency
`app.current_person_id()` (in `0012`) assumes a JWT custom claim named
`person_id`. **This is not confirmed anywhere in the reviewed docs** — the
API spec only says "Bearer JWT, issued at login." If the actual auth
integration doesn't inject this claim, every single policy in this entire
deliverable silently evaluates to deny-all for authenticated users (fails
safe, not open — but the app would be completely broken, not insecure).
This must be verified against the real auth setup before these migrations
are applied to any environment with real users.

### SP-001 suspension enforcement — decision point, not resolved here
Per the briefing's instruction, this was flagged rather than silently
picked: while `businesses.business_status = 'Suspended'`, no RLS policy in
this migration set blocks a suspended business's Owner from continuing to
query their own data (Owner policies check only `owner_person_id`/active
membership, not `business_status`). This is almost certainly correct — the
Owner needs query access to resolve an Aadhaar dispute per SP-001 — but the
"every non-Owner role sees only the generic suspension message" behavior
for Agent/Investor/Customer is **not enforced at the RLS layer at all** in
this migration set; it must be enforced at the application layer (blocking
navigation before any query fires) or via an additional
`AND business_status != 'Suspended'` clause added to every non-Owner SELECT
policy above. I did not add that clause because SP-001 itself calls this
Support-mediated and app-layer-plausible, and adding it unilaterally to
~40 policies without confirmation risked getting the exact cutover
semantics wrong (e.g. does a Suspended business's Agent still need read
access mid-dispute for some narrow purpose?). **Master chat: please make
the final call and I'll add the clause everywhere in a follow-up migration
if app-layer enforcement isn't judged sufficient.**

### Tables status: ALL modules complete
Every table in `03_Database_Schema.md` Modules 0–9, plus the four addendum
tables, has `ENABLE ROW LEVEL SECURITY` and at least one policy (or a
documented intentional deny-all, for `duplicate_suspects` and the
`business_id IS NULL` slice of `audit_log`). No table was skipped or left
partial.
