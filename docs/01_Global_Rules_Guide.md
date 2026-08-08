# MANA LINE — GLOBAL BUSINESS RULES GUIDE
## CONFIRMED, MERGED EDITION — 2026-07-19
Status: LOCKED. This is the single confirmed source for all Business Rules
(BR-001 through BR-240 plus the two supersession/new-rule blocks below).
Merges the original guide (BR-001–BR-231) with Addendum v2 (BR-232–240)
and Addendum v3 (role-ID restrictions, cross-business privacy principle,
address alert exception, business-cap queue, wrong-Aadhaar handling — all
confirmed, no open items). Superseded rules (e.g. old single-company
BR-119) are intentionally left as historical record within this document
per the project's no-backport rule; the REVISED versions are what's
authoritative wherever a conflict exists.

Numbering note (verified this session): base document's highest rule is
confirmed BR-231; Addendum v2 correctly continues at BR-232 with no
collision. BR-241–269 exist inline within individual OW screen docs
(OW-002–OW-005) rather than centrally cataloged here — out of scope for
this merge pass, flagged for a future numbering-consolidation pass if
desired.

---

# MANA LINE  
## Version: 1.0 


---

### 1. Vision & Mission
**Vision:** Become the digital operating system for local lending businesses, providing peace of mind, transparency, and operational efficiency.
**Mission:** Ensure every rupee is accounted for, every action is tracked, and every owner closes their day with absolute confidence.

### 2. Core Principles
1.  **Confidence First:** Every feature increases business trust.
2.  **Reality Over Theory:** Software follows business, not the other way around.
3.  **One-Tap Thinking:** Most common tasks take < 3 taps.
4.  **Speed:** Faster than a notebook.
5.  **Simplicity:** If the user has to think, we have failed.
6.  **Immutable Financial Records:** Money is never deleted or hidden.
7.  **One Source of Truth:** Business data is unified and validated.
8.  **Effective Date Engine:** Settings/Rules apply prospectively.
9.  **Global Customer Identity:** One human = one identity, regardless of business count.
10. **Cloud-First, Offline Protected:** Data is safe even without connectivity.

### 3. Core Business Rules (Summary)
BR-001: Business Date is the only source of truth.
BR-002: All financial records are permanent and immutable.
BR-003: Every action leaves an audit trail.
BR-004: Amount Given = Repayment - Interest - Fees (Locked formula).
BR-005: Investment Return = Independent of loan operations.
BR-006: A customer may pay any amount at any time until the loan end date plus the owner-defined grace period. (Collection Management)
BR-007: Grace Period: Every loan can have a grace period (e.g., 45 days) during which collections continue, no penalty is shown, and the loan remains active. (Loan Management)
BR-008: Early Closure Reward: Returning principal before half-time may attract a reward decided by the owner. (Loan Management)
BR-009: Penalty: Penalty is not fixed and is decided by the owner per loan. (Loan Management)
BR-010: A loan is defined by its agreement, not just the money handed over. (Loan Management)
BR-011: Amount Given = Repayment Amount - Interest - Processing Fee (Locked calculation formula). (Loan Engine)
BR-012: Loan Templates: Templates are predefined models used for quick loan creation but do not lock the loan values. (Loan Management)
BR-013: Every new loan request is a decision; the owner/agent selects from new loan, renewal, or merge based on customer status. (Loan Workflow)
BR-014: Loan Merge: Multiple existing loans can be merged into a single new loan with a new agreement. (Loan Management)
BR-015: Loan Cancellation: A loan can be cancelled only before cash handover. No financial impact occurs. (Loan Workflow)
BR-016: Loan Editing: If a saved loan contains incorrect details, edit the loan. Previous values preserved in audit log. (Audit/Loan)
BR-017: New Customer Issuance: Physical presence required for new customers for verification. (Customer Mgmt)
BR-018: Existing Customer Issuance: Remote issuance allowed for existing customers. (Customer Mgmt)
BR-019: Daily Reminder: Sent at 5:00 AM only to customers with repayment due. (Collection)
BR-020: Business Date: System operations follow the business day, not calendar time. (System)
BR-021: Effective Date: Changes apply prospectively, history remains immutable. (System)
BR-022: Single Business Cash Pool: All cash belongs to the business, not individuals. (Cash Engine)
BR-023: Payment Mode: Multiple payment modes (Cash, UPI, Bank, Cheque) supported in one transaction. (Collection)
BR-024: Closing Balance: Shows breakdown of all payment modes. (Cash Engine)
BR-025: Split Payments: One collection transaction can support multiple payment modes. (Collection)
BR-026: Collection Draft: Partially entered collections are saved as drafts to prevent data loss. (Collection)
BR-027: Routes: Routes are business plans, not fixed schedules. (Route Mgmt)
BR-028: Flexible Route Execution: Routes can be changed, skipped, or merged based on real-world situations. (Route Mgmt)
BR-029: Investment Engine: Every investment is an independent transaction. (Investment)
BR-030: ROI Agreement: ROI is individual per investment. (Investment)
BR-031: Profit Sharing: Manually decided and recorded by owner. (Finance Mgmt)
BR-032: Daily Interest Calculation: Interest calculated daily based on ROI. (Investment)
BR-033: Interest Type: Simple or Yearly Compound supported per investment. (Investment)
BR-034: Agreement Snapshot: Agreement terms are frozen at the time of investment. (Investment)
BR-035: Physical Documents Checklist: Optional tracking of documents (Bond, Cheque, etc.). (Verification)
BR-036: Live Photo Capture: Mandatory for new loans. (Fraud Prevention)
BR-037: Surprise Village Verification: 100% of customers in selected village verified. (Verification)
BR-038: Secrecy: Verification schedule revealed only on the day of verification. (Fraud Prevention)
BR-039: Verification Result: Four statuses: Verified, Shifted, Not Found, Suspicious. (Verification)
BR-040: Verification History: Every verification is permanently stored. (Verification)
BR-041: Fraud Dashboard: Tracks pending verifications, alerts, and overdue verifications. (Fraud Prevention)
BR-042: Verification Status: Verification does not automatically modify business data; owner confirms updates. (Verification)
BR-043: Zero Difference Policy: Day Closure allowed only if difference is ₹0.00. (Day Closure)
BR-044: Draft Prevention: Day Closure blocked if any drafts exist. (Day Closure)
BR-045: Temporary Adjustment: Shortage/Excess can be adjusted to a customer profile as a pending settlement. (Settlement)
BR-046: Daily Allowance: Fixed agent allowance is not an expense; reduced from final salary. (Agent Mgmt)
BR-047: Salary Advance: Deducted from agent salary account. (Agent Mgmt)
BR-048: Business Expense: General expenses recorded in business general account. (Finance)
BR-049: Every investment is independent. (Investment)
BR-050: ROI History: ROI agreements are fixed per period; changes are prospective. (Investment)
BR-051: Interest Payment: Payable on demand; calculated until payment date. (Investment)
BR-052: Outstanding Interest: Unpaid interest stays as pending, not converted to principal. (Investment)
BR-053: Compounding: Yearly compounding adds interest to principal. (Investment)
BR-054: Principal & Interest: Independent financial events. (Investment)
BR-055: System Interest: System calculates daily; owner verifies. (Investment)
BR-056: Manual Profit Distribution: Owner distributes profit manually. (Finance)
BR-057: Percentage History: Profit share % changes are prospective. (Finance)
BR-058: Declaration vs Payment: Profit declaration is separate from cash payout. (Finance)
BR-059: Pending Profit Interest: Pending profit sharing may earn interest if agreed. (Finance)
BR-060: Distribution Ledger: Every profit share is recorded. (Finance)
BR-061: External Chits: Recorded as business expense only. (Finance)
BR-062: Chit Profit/Loss: Belongs to business line profit. (Finance)
BR-063: Permanent Agent Identity: One permanent Agent ID for life. (Agent Mgmt)
BR-064: Leave Settlement: BF settled before leave. (Agent Mgmt)
BR-065: Individual Accountability: Shared route but individual transaction accountability. (Agent Mgmt)
BR-066: Short/Excess Accountability: Belongs to individual agent ledger. (Agent Mgmt)
BR-067: Flexible Salary Cycle: Monthly or custom payment. (Agent Mgmt)
BR-068: Salary Formula: Fixed + Adjustments - Advances - Shorts. (Agent Mgmt)
BR-069: Short Recovery: Owner controlled, not automatic. (Agent Mgmt)
BR-070: Excess Ledger: Stored for owner adjustment. (Agent Mgmt)
BR-071: Pending Salary: Stays unpaid until owner pays. (Agent Mgmt)
BR-072: Salary History: Permanent record of each month. (Agent Mgmt)
BR-073: Agent Permissions: Configurable per agent. (Permissions)
BR-074: Granular Permissions: Permission based access. (Permissions)
BR-075: Loan Permissions: One permission for full loan workflow. (Permissions)
BR-076: Collection Permissions: Record/Edit/Delete access. (Permissions)
BR-077: Report Access: Limited to own data for agents. (Permissions)
BR-078: Closed Day Protection: Owner approval required for post-closure edits. (Permissions)
BR-079: Immediate Loan Creation: No approval required for agents. (Loan)
BR-080: Permissions Context: Apply within assigned route sessions only. (Permissions)
BR-081: Live Photo at Every Loan (Mandatory). Agent must capture live customer photo before saving a new loan. Context: Fraud Prevention.
BR-082: Surprise Village Verification. Owner selects a village, and 100% of customers must be verified after 4-6 months. Context: Fraud Prevention.
BR-083: Surprise Verification Secrecy. Verification list visible only to Owner until the day of verification. Context: Fraud Prevention.
BR-084: Verification Results. Statuses limited to Verified, Shifted, Not Found, Suspicious. Context: Fraud Prevention.
BR-085: Customer Photo Only (Verification). Verification captures only a live customer photo. Context: Fraud Prevention.
BR-086: Village Change Rule. If a customer has shifted, village is updated immediately, but history remains. Context: Location Management.
BR-087: Verification History. Every verification is permanently recorded with audit trail. Context: Fraud Prevention.
BR-088: Fraud Dashboard. Owner Home shows pending/completed/alert verifications. Context: Fraud Prevention.
BR-089: Universal Calendar. Global rule for all date inputs; calendar picker mandatory. Context: System Administration.
BR-090: Operational Report Only. Daily report includes only operational data (Collection, Loan, Expense, Cash, etc.). Context: Reports & Analytics.
BR-091: Corrected Data as Truth. Reports always reflect the latest corrected data. Context: Reports & Analytics.
BR-092: Agent Balance First. Daily Business Report header shows Agent Balance Status first. Context: Reports & Analytics.
BR-093: Pending Customers Second. Daily Business Report shows pending customers list immediately after Agent Balance. Context: Reports & Analytics.
BR-094: Daily Record Book (Structure). One row per business day; permanent history. Context: Reports & Analytics.
BR-095: No Health Rating. MANA LINE does not rate or rank business performance. Context: Reports & Analytics.
BR-096: Monthly Summary (Ledger). Monthly closing summary row automatically generated. Context: Reports & Analytics.
BR-097: Remarks (Optional, Daily). Optional remarks allowed for each business day record. Context: Reports & Analytics.
BR-098: Monthly Closing Row. System generates monthly closing summary automatically. Context: Reports & Analytics.
BR-099: Permanent Annual Record Book. System permanently stores annual ledger records. Context: Reports & Analytics.
BR-100: Default View (Customer Outstanding). Customer Outstanding report always opens with 'Today's Pending Customers'. Context: Reports & Analytics.
BR-101: Standard Sorting (Customer Outstanding). Sorting order: Today's Due, Overdue, Future Due. Context: Reports & Analytics.
BR-102: Customer Summary Row (Fields). Each row shows core details and financial status. Context: Reports & Analytics.
BR-103: Planning Filters (Quick Filters). Filters for time and agent/route. Context: Reports & Analytics.
BR-104: One Customer = One Row (Loan Combination). Outstanding balance across all loans combined. Context: Reports & Analytics.
BR-105: Today's Pending Only (Filtering Rule). Customer Outstanding shows today's pending only, moving to overdue if not cleared. Context: Reports & Analytics.
BR-106: Active Loans (Loan Portfolio Default). Report opens with 'Active Loans'. Context: Reports & Analytics.
BR-107: Loan Categories (Filters). Quick filters available for different loan statuses. Context: Reports & Analytics.
BR-108: Loan Information (Row Fields). Row shows core loan details and status. Context: Reports & Analytics.
BR-109: Loan Sorting (Penalty/Grace/Due/Renewal). Sorted by business priority. Context: Reports & Analytics.
BR-110: Active Filters (Loan Portfolio). Filters by route, village, agent, template. Context: Reports & Analytics.
BR-111: Active Until Closed (Loan Status). Loans remain in 'Active' portfolio until fully closed. Context: Reports & Analytics.
BR-112: Completed Weeks Progress (Accurate tracking). Based on full installment completion only. Context: Loan Management.
BR-113: Penalty Eligible Loans (Risk). Highlighted in Loan Portfolio. Context: Loan Management.
BR-114: Operational Agent Report (Agent Management). Status monitoring only, not ranking. Context: Agent Management.
BR-115: No Agent Ranking. Agent performance is never ranked. Context: Agent Management.
BR-116: Line Performance (Over Agent). Analysis focuses on business line, not agent comparison. Context: Agent Management.
BR-117: Collection Ownership (Transaction responsibility). Every collection records who collected it. Context: Collection Management.
BR-118: Transaction Responsibility (Responsibility trail). Every financial transaction records the responsible person. Context: Financial Management.
BR-119: Single Company (V1 scope). V1 supports only one company profile. Context: Administration.
BR-120: Business Defaults (Configurable). Templates and general settings configurable. Context: Administration.
BR-121: Notification Configuration (Owner controlled). Notifications configurable by Owner. Context: Administration.
BR-122: Every Day is a Business Day (Calendar rule). No holidays enforced. Context: Administration.
BR-123: Backup & Restore (Full business). Complete business restoration. Context: Administration.
BR-124: Audit Log (Important events). Only administrative/security events logged. Context: Administration.
BR-125: Owner Approval (PIN). Mandatory PIN for sensitive actions. Context: Security.
BR-126: Location (Type/Name/Area/PIN). Basic location structure. Context: Location Management.
BR-127: Permanent Location (No deletion). Locations are Inactive, never deleted. Context: Location Management.
BR-128: Customer Relocation (History preserved). Customer moves, history kept. Context: Location Management.
BR-129: Location Summary (Operational). Status monitoring for villages/towns. Context: Location Management.
BR-130: Search (Universal). Search all locations by name/PIN. Context: Location Management.
BR-131: Route Master (Configurable). Permanent route definitions. Context: Route Management.
BR-132: Multiple Locations (per route). Routes support any number of locations. Context: Route Management.
BR-133: Manual Location Order (Sequence). Order of visit is manual. Context: Route Management.
BR-134: Default Team (Route assignment). Agent assignment is default. Context: Route Management.
BR-135: Expected Collection Cycle (Planning). Planning-only cycle. Context: Route Management.
BR-136: Effective Date Route Changes. Route changes apply from effective date. Context: Route Management.
BR-137: Multiple Route Membership (Locations). Location can belong to multiple routes. Context: Route Management.
BR-138: Route Growth (Split, not expand). New routes created if capacity exceeded. Context: Route Management.
BR-139: Loan Template Structure. Name, status, remarks. Context: Administration.
BR-140: Default Loan Amount. Amount configurable per template. Context: Administration.
BR-141: Loan Structure (Defaults). Template sets repayment frequency, duration, etc. Context: Administration.
BR-142: Financial Defaults (ROI/Fee/Grace). Configurable per template. Context: Administration.
BR-143: Individual Permissions (Template). Template specific agent permissions. Context: Administration.
BR-144: Effective Date (Template). Changes apply from effective date. Context: Administration.
BR-145: Template Usage Statistics. Tracking how often templates are used. Context: Administration.
BR-146: Template Deletion (Only if unused). Blocked if linked to existing loans. Context: Administration.
BR-147: Template-Based Loan Creation. Default workflow. Context: Loan Management.
BR-148: User Roles (Owner/Agent). Two system roles. Context: User Management.
BR-149: User Profile. Profile details and status. Context: User Management.
BR-150: Login System (PIN + Password). Daily usage via PIN. Context: User Management.
BR-151: Password Reset (Owner controlled). Reset by owner directly. Context: User Management.
BR-152: Single Device Policy. One active device per user. Context: Security.
BR-153: Permanent Agent Identity. Agent ID is permanent. Context: Agent Management.
BR-154: Owner Authority (Unrestricted). Absolute authority. Context: User Management.
BR-157
Rule: One user can have only one active device. If they log in on a new device, the previous session is automatically logged out and the owner is notified.
Module Context: Administration/Security
BR-158
Rule: The Audit Log records only important administrative and security actions (e.g., settings changes, permission updates, loan corrections). Routine business transactions (collections, loan issues) are kept in their respective workspaces to keep the Audit Log concise and focused.
Module Context: Administration/Audit
BR-159
Rule: Business migration can only be performed before agents are allowed to use the system. Once the owner clicks "Business Started," the migration mode is locked, and future entries must follow regular workflows.
Module Context: Administration/Business Migration
BR-160
Rule: Every person has one identity in the MANA LINE network. Finance businesses share only this customer identity (e.g., Aadhaar, Name) to prevent duplicates, while keeping all business data (loans, collections, notes) private to each business.
Module Context: Customer Management/Identity
BR-161
Rule: Every customer receives a permanent MANA LINE Customer ID that remains with the person, regardless of new loans, finance companies, address changes, or phone number changes.
Module Context: Customer Management/Identity
BR-162
Rule: Every collection session starts only after the agent checks the handed-over cash and the owner approves the handover with a PIN. This creates an auditable record of cash responsibility.
Module Context: Daily Operations/Cash
BR-163
Rule: Before balancing, the agent hands over the cash to the owner, who counts it and confirms receipt via PIN. This confirms the cash return before the balancing process begins.
Module Context: Daily Operations/Day Closure
BR-164
Rule: Every financial transaction stores two distinct times: an 'Operational Date' (the business day the transaction belongs to) and an 'Entry Timestamp' (the actual system time when it was entered). Business reports always use the Operational Date.
Module Context: Core System/Architecture
BR-165
Rule: No loan can be created if the collector's assigned BF cash is insufficient. The BF balance must be updated first, then the loan can be issued.
Module Context: Daily Operations/Loan Management
BR-166
Rule: Each customer has a default maximum active loan count (Company Setting), but owners can increase this limit individually for specific customers without changing the default company policy. Exceeding a customer's specific limit requires Owner PIN approval.
Module Context: Customer Management/Loan Limits
BR-167
Rule: Existing customers allow remote loan issuance (as they are already verified). New customers require physical presence for identity verification (Aadhaar, photo capture) to be registered.
Module Context: Customer Management/Registration
BR-168
Rule: A loan can be cancelled only before the money is handed over. No financial transaction is created, and it leaves no permanent business impact.
Module Context: Loan Management/Lifecycle
BR-169
Rule: Once a loan is saved, it cannot be deleted. Any errors must be corrected through an edit workflow that creates a new audit log entry, preserving the history of previous values.
Module Context: Loan Management/Audit
BR-170
Rule: Partial withdrawals reduce the investment principal. They do not create a new investment, and the withdrawal history is permanently preserved.
Module Context: Investment Management/Withdrawal
BR-171
Rule: Investment ownership may be transferred to a nominee. The investment contract remains the same; only the owner of the investment changes.
Module Context: Investment Management/Transfer
BR-172
Rule: When an investor adds more money, the owner decides whether to merge it into an existing investment (if terms are identical) or create a new independent investment.
Module Context: Investment Management/Capital
BR-173
Rule: BF Cash may be transferred between agents. The transaction records the From Agent, To Agent, Amount, Business Date, Time, and both agents' confirmations.
Module Context: Agent Management/Cash
BR-174
Rule: Every collection session must capture the result. If a customer is visited, the outcome (Payment, Locked, Promise, etc.) must be recorded. Draft collections are mandatory to ensure no partial data is lost.
Module Context: Collection Management/Lifecycle
BR-175
Rule: Salary is a payable amount. It remains outstanding in the agent's ledger until paid by the owner. It does not automatically carry forward to the next month's salary automatically without owner intent.
Module Context: Agent Management/Salary
BR-176
Rule: The system automatically performs daily incremental backups of all business data. No manual backup is required for normal operation. Cloud synchronization happens automatically in the background whenever internet is available.
Module Context: System Workspace/Backup
BR-177
Rule: The system operates on an "Operational Business Date" configured by the owner, not strictly on the calendar clock. The owner decides when one business day ends and the next begins.
Module Context: Core System/Architecture

### 3B. Identity & Access Governance (merged from FILE 7B, 2026-07-16)

BR-178
Rule: One Person = One MANA LINE ID, permanently. A person never receives a second ID even after acquiring multiple roles.
Module Context: Identity Network/Core

BR-179
Rule: Roles (Owner, Investor, Agent, Customer) are additive, independent toggles on a single identity, not separate accounts. A person may hold all four roles simultaneously on one ID.
Module Context: Identity Network/Roles

BR-180
Rule: Any existing ID holder may be escalated to a new role via a single action by the party authorized to grant it (the Owner, or self-registration where applicable).
Module Context: Identity Network/Roles

BR-181
Rule: Permanent ID (MLPI) format: "MLPI" + gender digit (0=Female, 1=Male) + last 8 digits of Aadhaar number. Assigned only when Aadhaar is provided at registration.
Module Context: Identity Network/ID Generation

BR-182
Rule: Temporary ID (MLTI) format: "MLTI" + gender digit (0=Female, 1=Male) + unique random 8-digit number. Assigned when Aadhaar is not provided at registration.
Module Context: Identity Network/ID Generation

BR-183
Rule: MLTI random segments must be checked for uniqueness against the full ID table before assignment, with a collision retry loop.
Module Context: Identity Network/ID Generation

BR-184
Rule: An MLTI ID is upgraded to an MLPI ID once Aadhaar is later captured for that identity. The prior MLTI value is retained in ID history for audit continuity; it is not silently overwritten.
Module Context: Identity Network/ID Generation

BR-185
Rule: One master tenancy (one deployed business instance) has exactly one Owner.
Module Context: Identity Network/Tenancy

BR-186
Rule: The Owner defines and may adjust at any time the maximum headcount cap (X) for Investors, Agents, and Customers within their tenancy, via an administrative settings screen.
Module Context: Identity Network/Tenancy

BR-187
Rule: The Owner has full, granular control over which screens, metrics, and navigation paths are visible per role within their tenancy.
Module Context: Identity Network/Permissions

BR-188
Rule: Investor and Agent roles require SMS OTP phone verification before activation, whether the person self-registers or is linked/escalated by the Owner.
Module Context: Identity Network/Verification

BR-189
Rule: Customer roles require no OTP verification.
Module Context: Identity Network/Verification

BR-190
Rule: If an existing Customer identity is escalated to Agent or Investor, OTP verification is mandatory at the moment of escalation. There is no exemption based on the identity's prior OTP-free Customer status.
Module Context: Identity Network/Verification

BR-191
Rule: A role in "pending_verification" state is not shown as an accessible workspace tab. Attempting to open it redirects immediately to the OTP verification screen; underlying role data is never exposed pre-verification.
Module Context: Identity Network/Verification

BR-192
Rule: If an Agent registers a new Customer after the Owner's Customer cap (X) has been reached, the registration is not blocked. The record is created and placed into a Pending Approval queue, with an immediate notification raised in the Owner's workspace.
Module Context: Identity Network/Capacity

BR-193
Rule: Pending Approval customers are excluded from reporting totals (Outstanding, Due Today, etc.) until approved by the Owner.
Module Context: Identity Network/Capacity

### 3C. Session Merge — 2026-07-16 (Discussion Reconciliation)
Source: Entire_discussion_1.txt cross-check against Files 2-9. Supersedes BR-097 (Daily Lock) and amends BR-185 (Tenancy).

BR-194
Rule: [SUPERSEDES BR-097 / "Daily Lock"] Daily Lock is permanently removed from V1. Every transaction stores two distinct timestamps: Operational Date (the business day the transaction belongs to) and Entry Timestamp (actual date/time of entry). Agents may enter collections after their working hours or after midnight; the entry is simply tagged to the correct Operational Date. No owner approval is required for late entry under this rule.
Module Context: Core System/Business Date Engine

BR-195
Rule: Login model for Owner and Agent: first login requires Mobile Number + Password, then the user creates a 4-or-6-digit PIN. Daily login uses PIN only. Password is required only for: new-device login, changing the PIN, or account recovery.
Module Context: Security/Authentication

BR-196
Rule: A Biometric Authentication toggle (enable/disable) is available in Settings, as an optional substitute for PIN entry on supported devices. Disabled by default; PIN remains the fallback at all times.
Module Context: Security/Authentication

BR-197
Rule: Single Device Policy: each user may have only one active device. Logging in on a new device automatically logs out the previous session and sends a notification to the Owner (e.g., "Agent Ravi logged in from a new device at 10:42 AM").
Module Context: Security/Authentication

BR-198
Rule: Permanent Agent Identity: every Agent keeps one permanent Agent ID for life. If an Agent leaves and later rejoins, the same account, ID, and history are reactivated — a new account is never created.
Module Context: Agent Management/Identity

BR-199
Rule: Owner Authority: the Owner account has unrestricted access — it can approve corrections, change permissions, override restrictions, and access every workspace without exception.
Module Context: Security/Authorization

BR-200
Rule: Owner Approval Mode: sensitive actions (collection corrections, loan corrections, permission changes) are approved in-context by the Owner entering their PIN, without switching accounts. Every approval is recorded in the Audit Log as "Approved By: Owner" with date/time.
Module Context: Security/Authorization

BR-201
Rule: [AMENDS BR-195 recovery path] Account recovery for PIN or password is available to any role (including Owner) via phone or email OTP — no dependency on a higher-privilege user resetting it for them. After 3 consecutive wrong PIN entries, the system falls back to requiring the password. After 5 consecutive wrong password entries, the account is fully locked and requires mobile OTP verification to unlock.
Module Context: Security/Authentication

BR-202
Rule: [AMENDS BR-185] Tenancy model is many-to-many for Agent and Investor roles: a single Agent/Investor identity may be linked to and work under N different Owners' tenancies simultaneously. Owner-count is not limited to one per Agent/Investor. (BR-185's "one Owner per tenancy" still holds from the Owner's own side: one deployed business instance has exactly one Owner — the change is that the reverse relationship, one Agent/Investor to many Owners, is now explicitly permitted.)
Module Context: Identity Network/Tenancy

BR-203
Rule: Each Owner independently controls (locks/unlocks) an Agent's or Investor's access to that specific Owner's business data only. A lock applied by one Owner has no effect on that person's standing, access, or visibility with any other Owner's tenancy. Locked users can still log in but cannot access the locked Owner's business data.
Module Context: Identity Network/Permissions

BR-204
Rule: Onboarding: the first Owner of a tenancy self-registers directly (no separate bootstrap/setup flow required). The Owner then adds Investors/Agents via two methods: (a) fresh in-app registration, or (b) MANA LINE ID lookup — Owner searches by ID, system returns a match, Owner adds instantly ("search → found → add").
Module Context: Identity Network/Onboarding

BR-205
Rule: Basic in-app notification behaviors are enabled system-wide, including at minimum: new-device login alert to Owner, capacity-overflow alert to Owner (Pending Approval queue), and Owner Approval Mode confirmations. Notifications are visible in a dedicated Notification screen/inbox.
Module Context: Cross-Cutting/Notifications

BR-206
Rule: Grace Period and Penalty fields are mandatory fields on the Loan Creation screen (not merely referenced in business rules): Grace Period (days, owner-configurable default, overridable per loan) and Penalty (owner-decided amount/rate per loan, not fixed system-wide). Grace Period is internal only — never shown to the Customer; only the Penalty becomes visible once the grace period ends.
Module Context: Loan Management/Loan Creation

BR-207
Rule: A Guarantor Management workflow exists on the Customer Workspace: Add Guarantor, Edit Guarantor, Remove Guarantor, linked to an existing MANA LINE identity where possible. Guarantor data remains strictly private to the Owner's business (Privacy Rule #1) except where it contributes to that guarantor's own Line Score exposure to other tenancies per BR-215.
Module Context: Customer Management/Guarantor

BR-208
Rule: Multi-tenancy login: any user whose MANA LINE ID is linked to more than one Owner's tenancy is shown a "Select Business" screen immediately after PIN/biometric entry, on every login. This is not skipped or defaulted to a last-used business.
Module Context: Identity Network/Login

BR-209
Rule: Role-switching within a single Owner's tenancy (e.g., a person who is both Investor and Customer under the same Owner) is presented as tabs at the top of the screen (e.g., "Investor | Customer"), not a dropdown or separate home-screen picker.
Module Context: Cross-Cutting/Navigation

### 3D. Line Score v1 — Locked Formula (Session 2026-07-16)

BR-210
Rule: Line Score is a derived value, never stored directly — it is recalculated from underlying transaction/loan history each time it is displayed or evaluated (per Architecture Decision #002).
Module Context: Investment & Reputation/Line Score

BR-211
Rule: Line Score is a single number on a 0-100 scale in V1 (not a tier/label system). New customers with no loan history start at a baseline of 35 points.
Module Context: Investment & Reputation/Line Score

BR-212
Rule: On-Time Ratio component (max 40 points): calculated as (On-Time % across all loans) × 40. The customer's most recent loan is weighted 1.5x in this blended calculation relative to older loans.
Module Context: Investment & Reputation/Line Score

BR-213
Rule: Loan Completion History component (max 25 points): +12.5 points per fully-closed clean loan, capped at 25 (i.e. 2+ clean closures earns full marks). Any single defaulted/written-off loan zeroes this component entirely regardless of other clean closures.
Module Context: Investment & Reputation/Line Score

BR-214
Rule: Penalty Frequency component (starts at 20 points, deducts): -5 points per loan that ever crossed into Penalty status historically (floor at 0). The most recent loan's penalty status is weighted 1.5x in this calculation relative to older loans.
Module Context: Investment & Reputation/Line Score

BR-215
Rule: Penalty Recovery Bonus (uncapped, applies every time, no limit per customer): +3 points for each Penalty-status loan that is fully closed with the penalty amount actually paid (not waived/reduced by Owner). If the penalty was waived or reduced, no recovery bonus applies. If the loan is not closed (still active or defaulted), no recovery bonus applies. This bonus is added on top of, not instead of, the -5 point deduction in BR-214 for that same incident.
Module Context: Investment & Reputation/Line Score

BR-216 [SUPERSEDED 2026-07-16]
Rule: Guarantor Factor is REMOVED from the Line Score formula entirely. Reason: it required reading a guarantor's Line Score across tenancy boundaries, contradicting the core privacy rule that business data stays strictly private to each Owner (FILE 7). Guarantor strength (strong/weak/none) is still shown on the Customer Workspace as a visible trust signal, but no longer contributes numeric points to the Line Score.
Module Context: Investment & Reputation/Line Score

BR-216B [NEW 2026-07-16]
Rule: Line Score final total is hard-capped at 93 points — no customer can ever reach 100 in V1. Formula: min(On-Time Ratio + Loan Completion History + Penalty Frequency + Penalty Recovery Bonus, 93). This resolves the mathematical overflow risk created by the uncapped Recovery Bonus (BR-215) once combined with the other components.
Module Context: Investment & Reputation/Line Score

BR-217
Rule: Family/household-level scoring is explicitly rejected. Every individual's loan and Line Score stand entirely on that individual's own history — no household or family score exists in V1.
Module Context: Investment & Reputation/Line Score

BR-218 [UPDATED 2026-07-16 — Guarantor removed from example]
Rule: The Customer Workspace displays the Line Score alongside a breakdown of its contributing factors (e.g., "Line Score: 84 — 92% on-time, 1 Penalty incident, 2/2 loans closed clean"), never as a bare number alone, so the Owner can see the reasoning behind the score. Guarantor status is shown separately, alongside but not inside this breakdown.
Module Context: Investment & Reputation/Line Score

### 3E. Day Closure & Business Date — Full Mechanics (Session 2026-07-16, sourced from Entire_discussion_1.txt, resolves the BR-194 conflict)

BR-219
Rule: Zero Difference Policy (BR-043 equivalent, reaffirmed as-is): Day Closure is NOT allowed unless the difference between Expected Closing and Physical Closing is exactly ₹0.00. The Close Day action remains disabled at any non-zero difference (₹0.01, ₹2, ₹50, etc.) in V1. A "Forced Closure" override is explicitly out of scope for V1 and may be considered as an advanced Owner-enabled setting in a future version.
Module Context: Owner Workspace/Day Closure

BR-220
Rule: No Drafts at Day Closure (BR-044 equivalent, reaffirmed as-is): Day Closure is blocked while any Draft Collections, Draft Loans, or Draft Expenses remain pending. All drafts must be completed or discarded first.
Module Context: Owner Workspace/Day Closure

BR-221
Rule: Reopen Closed Day is an Owner-only permission (BR-076 equivalent). Agents cannot reopen a closed Business Date under any circumstance.
Module Context: Owner Workspace/Day Closure

BR-222
Rule: Closed Day Protection (BR-078 equivalent): once a Business Date is closed, any attempted edit or new entry against it prompts "This day is already closed. Owner approval required." Upon Owner approval, the day reopens, the change is recorded, and the system recalculates all affected accounts. This is the mechanism that reconciles BR-194 (free late entry while a day is still open, no approval needed) with the Zero Difference Policy (BR-219) — the two rules govern different states (open vs. closed), not conflicting requirements on the same state.
Module Context: Owner Workspace/Day Closure

### 3F. Customer Aggregate V1 — Frozen (Session 2026-07-16, source: customer.txt)

BR-223
Rule: MLC (business-local sequential Customer ID) is REJECTED and removed. Every Customer is identified solely by their global MANA LINE ID (MLPI/MLTI, per BR-181/182) — the same single-identity system used for Owner, Agent, and Investor. No separate business-scoped customer numbering scheme exists anywhere in the system.
Module Context: Customer Management/Identity

BR-224
Rule: No nickname/local-name field ("Known As") exists on the Customer record. Customers are identified only by their original, official names. (Reaffirms the earlier "Decision 1: No Nickname," which a later draft had reopened and which this rule now formally re-closes.)
Module Context: Customer Management/Identity

BR-225
Rule: Customer Address stores full depth: Door No., PIN Code, Village (Selected), Mandal (Auto), District (Auto), State (Auto) — not Village-only. Address History is unlimited, storing Village, From Date, To Date, Reason per entry.
Module Context: Customer Management/Address

BR-226
Rule: IsDeceased is a simple Boolean (Yes/No) field in V1. No separate Date of Death field.
Module Context: Customer Management/Status

BR-227
Rule: No Blacklist status or field of any kind exists on the Customer record. Explicitly removed 2026-07-16 and must not be reintroduced in any future file or screen without a new, explicit decision.
Module Context: Customer Management/Status

BR-228
Rule: Duplicate Suspected can be raised both automatically (system detection via Aadhaar/Phone matching) AND manually (Owner can flag a suspected duplicate directly) — not automatic-only.
Module Context: Customer Management/Fraud Prevention

BR-229
Rule: Customer Type (New / Migrated) and Registration Source (Owner / Agent / Migration / System) exist specifically to support importing pre-existing customers at initial deployment. This does not grant Customers a self-service login or app in V1 — Customers remain Owner/Agent-managed records; only the data model now explicitly supports historical/migrated customer records from go-live.
Module Context: Customer Management/Onboarding

BR-230
Rule: Occupation is a mandatory-category business attribute (Farmer, Milk Vendor, Auto Driver, Tea Shop, Tailor, Daily Wage, Government Employee, Private Employee, Business, Housewife, Student, Retired, Other-Custom), used to understand livelihood, repayment capacity, and collection patterns — not treated as incidental personal data.
Module Context: Customer Management/Profile

BR-231
Rule: Profile Status ("is the form complete?": Complete/Incomplete/Pending Verification/Archived) and Customer Status ("can we currently do business with them?": Active/Inactive/Deceased) are two distinct fields answering two distinct questions. They must never be merged into a single status field.
Module Context: Customer Management/Status


### 5. Module Hierarchy
*   **Daily Operations:** Home, Customer, Loan, Collection
*   **Financial Management:** Expenses, Investments, Interest, Profit Sharing
*   **Agent Management:** Profiles, Salary, Permissions, Exit
*   **Administration:** Settings, Locations, Routes, Templates
*   **System Maintenance:** Backup, Security, Audit Logs

Cross-Cutting Modules & Shared Systems
Scope: System-wide background modules not restricted to a single workspace.
Route Management: Permanent business structures for daily collection planning. Links villages to routes; allows manual location ordering, status (active/inactive), and links to collection sessions. Managed by Owner.
Location Management: Geography-based master data (Village/Town + Area). Permanent identity with soft-delete (Active/Inactive); used for customer addressing, route planning, and verification history.
Loan Templates: Starter blueprints (Default Loan Amount, Duration, Interest Type, Fees). Immutable once used; template changes apply prospectively via Effective Date Engine.
Record Book / Reports Hub: Digital ledger for daily, monthly, and annual business summaries. Serves as the operational source of truth.
Identity Network: Global MANA LINE Customer ID links a person's identity across multiple finance businesses. Individual business data (Loans, Collections, Notes) remains strictly private to each owner.

FILE 7B: Identity & Access Governance (merged 2026-07-16, detailed spec — see BR-178 to BR-193)

(a) V1 — Finalized

1. Identity Model: One Person, One ID, Multiple Roles
Purpose: Guarantee exactly one database identity per human, regardless of how many roles (Owner, Investor, Agent, Customer) they hold, across one or more businesses.
Business Rules: BR-178 (one permanent ID for life), BR-179 (roles are additive toggles, not separate accounts), BR-180 (one-click role escalation by an authorized party).
Superseded Note: Formalizes and extends the identity model already defined in FILE 3 ("Investor is a role assigned to a Person entity") and the original Identity Network line above. No conflict — this is the detailed ID-format specification that was previously left open.

2. ID Generation Formula
Purpose: Deterministic, collision-resistant, human-traceable identity numbers.
Format:
  - Permanent (MLPI): "MLPI" + Gender Digit (0=Female, 1=Male) + Last 8 digits of Aadhaar number. Example: Aadhaar 0000 1234 5678, female -> MLPI012345678; male -> MLPI112345678.
  - Temporary (MLTI): "MLTI" + Gender Digit (0=Female, 1=Male) + Unique Random 8-digit number. Example: no Aadhaar provided, female, random seed 65321535 -> MLTI065321535.
Business Rules: BR-181, BR-182 (format definitions), BR-183 (MLTI uniqueness check with collision retry), BR-184 (MLTI-to-MLPI upgrade path, historical ID retained for audit).

3. Tenancy Hierarchy
Purpose: Define ownership and containment boundaries for a single business deployment.
Business Rules: BR-185 (one Owner per master tenancy — one deployed business instance has exactly one Owner), BR-186 (Owner-adjustable headcount caps for Investors/Agents/Customers), BR-187 (Owner controls per-role screen/metric/navigation visibility).
[AMENDED 2026-07-16, see BR-202, BR-203] The reverse relationship is many-to-many: a single Agent or Investor identity may be linked to and actively work under N different Owners' tenancies simultaneously. Each Owner independently locks/unlocks that person's access to their own business data only — a lock from one Owner never affects standing with any other Owner. A user linked to more than one tenancy sees a Select Business screen on every login (BR-208).

4. Onboarding Methods
Purpose: Let the Owner add people to their tenancy without creating duplicate identities.
Methods: (1) Direct In-App Registration — Owner fills the form from scratch, new ID generated per Section 2. (2) By MANA LINE ID Lookup — Owner enters an existing person's ID (MLPI/MLTI) to link that identity to their tenancy and grant a role, without duplicating the record.

5. Verification Gate (Role Escalation Security)
Purpose: Prevent a low-privilege role (Customer) from silently gaining access to a high-privilege role (Agent/Investor) without identity confirmation.
Business Rules: BR-188 (Investor/Agent roles require SMS OTP before activation), BR-189 (Customer roles require no OTP), BR-190 (OTP mandatory at the moment an existing Customer is escalated to Agent/Investor — no exemption), BR-191 (unverified roles hidden from navigation; opening one redirects to OTP screen, no data exposed pre-verification).

6. Capacity Overflow Handling
Purpose: Prevent field data loss when a business hits its Owner-defined headcount cap.
Business Rules: BR-192 (Customer registrations beyond cap are not blocked; placed in Pending Approval queue with immediate Owner notification), BR-193 (Pending Approval customers excluded from reporting totals until approved).

7. Multi-Owner Tenancy & Access Control (merged from Session 2026-07-16, see BR-202, BR-203, BR-204)
Purpose: Allow a single Agent/Investor identity to work across multiple independent businesses without those businesses' data mixing.
Business Rules: BR-202 (many-to-many: one Agent/Investor may work under N Owners), BR-203 (each Owner independently locks/unlocks that person's access to their own data only, with no cross-tenancy effect), BR-204 (Owner self-registers first; adds Investors/Agents via fresh registration or ID lookup search-found-add).

8. Role-Switcher Navigation (merged from Session 2026-07-16, see BR-209)
Purpose: Let a person holding multiple roles under the same Owner move between workspaces cleanly.
Business Rules: BR-209 (presented as tabs at the top of the screen, e.g. "Investor | Customer" — not a dropdown or separate home-screen picker, when both roles are under the same Owner's tenancy).


Glossary of Business Terms
BF Cash: Brought Forward Cash; the opening cash balance for the current business day.
Line Score: Local repayment index based on historical behavior, used as a customer reputation indicator.
Sort: A shortage of cash compared to the expected closing balance.
Excess: A surplus of cash compared to the expected closing balance.
Business Date: The operational date that a transaction belongs to, independent of the actual time of entry.
MANA LINE ID: Permanent, global identity for individuals across the network.
Effective Date: The date from which a new business setting (e.g., ROI change, fee increase) becomes active.
Day Closure: Final daily reconciliation of cash and transactions.
Route: A reusable collection plan that bundles villages/locations for collection.
Collection Session: A single operational unit of work performed by an agent (or team) on a route.
Line: The business term for a loan account/repayment track.
MLPI: MANA LINE Permanent ID — assigned to any person who has provided their Aadhaar number at registration. Format: MLPI + gender digit (0=Female, 1=Male) + last 8 digits of Aadhaar.
MLTI: MANA LINE Temporary ID — assigned to any person registered without an Aadhaar number. Format: MLTI + gender digit (0=Female, 1=Male) + unique random 8-digit number. Upgradeable to MLPI once Aadhaar is later provided.
Verification Gate: The security checkpoint that blocks access to a newly escalated role (Agent/Investor) until SMS OTP verification is completed.
Pending Approval Queue: Holding state for new Customer registrations submitted after the Owner's system-defined headcount cap has been reached.
Tenancy: A single deployed business instance, containing exactly one Owner and their Owner-managed Investors, Agents, and Customers.
Operational Date: The Business Date a transaction is tagged to, stored alongside (but separate from) the actual Entry Timestamp — replaces the earlier, rejected "Daily Lock" concept.
Owner Approval Mode: An in-context PIN confirmation by the Owner used to approve sensitive actions (corrections, permission changes) without switching accounts; recorded in the Audit Log.
Select Business: The screen shown after login to any user linked to more than one Owner's tenancy, letting them choose which business context to enter.
Line Score Recovery Bonus: The +3 point addition applied to a customer's Line Score each time a Penalty-status loan is fully closed with the penalty amount actually paid — applies uncapped, every incident.
Penalty Recovery: The act of a customer closing a Penalty-status loan in full, including the penalty amount, as distinct from simply catching up on a late installment mid-loan.

---

## ADDENDUM v2 CONTENT (BR-232–BR-240) — MERGED, CONFIRMED

### BR-232 — Business Name Uniqueness
Business names are unique system-wide. Creation is blocked if the entered
name already exists (case-insensitive match). On collision, the system
suggests alternatives by appending the business's general area name (e.g.
"Sharma Finance" taken → suggest "Sharma Finance – Vijayawada").
Schema impact: `businesses.name` requires a unique constraint.

### BR-233 — Pre-Membership Business Visibility
When a Customer or Investor searches for a business to join (not yet a
member), search results show **only**: MLBI (business ID), business name,
and general operating area. No owner name, loan terms, or other detail is
exposed pre-membership.

### BR-234 — Loan Limit Override Approval Detail (revises OW-005 Step 2)
When a customer would exceed the Maximum Active Loans per Customer setting,
the Owner's PIN-approval screen shows **only**: current active loan count
vs. the configured limit (e.g. "Customer has 2 active loans, limit is 2 —
approve one more?"). No loan amounts, due dates, or other financial detail
are shown on this approval screen.

### BR-235 — No Automated Loan Eligibility Pre-Check Beyond System Hard-Stops
(Clarifies OW-005 Step 2, not a removal of the existing system checks.) The
existing automatic pass/fail checks (Customer Exists, Blocked, Duplicate
Loan, etc.) remain and continue to return only a pass/fail result plus a
short reason category — never a detailed dump of the customer's financial
history — to whichever role is creating the loan.

### BR-236 — No Renewal Linking
Loan Renewal as a distinct feature is removed. When an existing loan's
remaining balance reaches ₹0, it closes normally. Any subsequent loan for
that customer is a standalone New Loan with no system-level link
(`parent_loan_id` is removed from schema) to the prior loan. The customer's
overall loan history remains visible on their profile via the normal
customer-loans list — this is unaffected, since it was never dependent on
renewal-linking.

### BR-237 — No Payment Receipts
Recording an EMI collection updates the loan balance directly in the
database. No receipt document (printed or generated) is produced. The
Customer's own app reflects the updated balance automatically since it
reads from the same underlying data — no separate sync or notification
step is needed for this.

### BR-238 — Profile Field Change History + Notification (Important Fields
Only)
When a Customer, Agent, or Investor updates their own profile, only
**important fields** — phone number, address, and Aadhaar/ID-related
details — trigger: (a) the old value being retained in history (never
overwritten, consistent with the existing address-history pattern in
BR-225), and (b) a notification sent to every business Owner this person is
connected to. Minor fields (e.g. spelling correction to name) do not
trigger history retention or notification. Owners can view old-vs-new
values via a "Previous Data" button on that person's profile.

### BR-239 — Aadhaar Correction (Wrong ID Entered at Signup)
Once captured, a person's Aadhaar number is a permanent identity — this
does not change (existing rule). If a wrong Aadhaar was entered at
signup, the fix is a Correction action, not a normal edit:
- Only the **Owner** may perform this correction (not Agent, not the
  person themselves).
- Requires Owner PIN entry **and** a typed reason.
- The corrected Aadhaar runs through the same duplicate-check used for new
  registrations (BR-228), to confirm it doesn't already belong to someone
  else.
- The old (wrong) value is retained in `person_id_history`, same mechanism
  as the existing MLTI→MLPI upgrade path — nothing is erased.
- All existing loans/records remain attached automatically — only the ID
  value itself changes on the same underlying person record.

### BR-240 — Agent Field-Route Local Cache (Offline Support)
To support poor-network/rain-affected field conditions without exposing
excess sensitive data on-device:
- Only the current day's due list, for that Agent's own assigned area, is
  cached locally on the phone. No broader customer database is downloaded.
- Cached data is stored in the device's encrypted storage (standard secure
  storage on Android/iOS) — not plain readable files.
- The cache clears every 24 hours by device clock, and also clears
  immediately on every fresh login — this is independent of Day Closure
  (business_date), since Day Closure can be delayed by the Owner and is
  not reliably once-per-24-hours.
- If an Agent's access is suspended or a device is reported lost, the next
  app launch (even offline) is blocked from displaying any cached data
  once the server revokes their session.
- No business-wide financial totals (only that Agent's own route data) are
  ever cached on-device.

---

---

## ADDENDUM v3 CONTENT — MERGED, CONFIRMED

BR-181/182/190 SUPERSEDED (role-based ID restriction):
Owner, Agent, Investor registration → Aadhaar mandatory, MLPI only, no
exceptions, effective at registration. MLTI is blocked outright for these
three roles going forward.
Customer registration → MLTI still permitted, but NEVER permanent. Every
MLTI customer (migrated pre-app customers AND new registrations alike)
triggers a Complete Profile / Skip for Now pop-up whenever an Owner/Agent
opens their record, and is hard-gated to Aadhaar/MLPI at their next new
loan — no customer stays MLTI indefinitely. See LR-004 F14 for the
registration-form implementation.

NEW PRINCIPLE — Cross-Business Financial/Performance Privacy:
An Agent's (or Investor's, or Customer's) financial or performance history
at one business — Shorts, debts, penalties, defaults, anything — is NEVER
surfaced to another Owner considering onboarding them, regardless of
amount or how long unresolved. No shared "reputation score" of any kind
crosses tenancy boundaries. Each Owner-Agent/Investor/Customer relationship
starts a clean slate, privacy-first, always. This is a firm design
principle, not a one-off answer to a single scenario — apply it wherever
cross-business visibility is being considered for any future feature.

NEW RULE — Cross-Lender Proactive Address Alert (exception to the privacy
principle above, deliberately, since it protects the customer/business
relationship rather than exposing one Owner's data to another):
When a customer's global address changes, every business where that
customer holds a currently non-closed loan (Active/Grace Period/Penalty/
Defaulted) is proactively notified. Businesses where all the customer's
loans are Closed are not. See 03B_Database_Schema_ADDENDUM_v2.md §6.

NEW RULE — Business Caps, Pending Queue (not Hard Block):
When max_investors/max_agents/max_customers is reached, onboarding is NOT
blocked — the new member's status becomes "Pending Approval" (existing
`membership_status` ENUM value, schema §1.8, capacity overflow queue per
BR-192) until the Owner raises the cap or manually approves them past it.

NEW RULE — Wrong-Aadhaar Handling (deletion never occurs):
No Aadhaar mismatch, at registration or new-business-creation, ever
triggers account deletion. Business accounts are never deleted, period.
Registration-form warning text: "Enter your Aadhaar Number carefully.
Incorrect entry may result in account suspension until resolved."
Suspension (not deletion) only occurs via the duplicate-Aadhaar
dispute-resolution flow — see SP-001_Aadhaar_Dispute_Resolution.md — when
a second person later proves an Aadhaar number is genuinely theirs. When
triggered, the ENTIRE business (not just the Owner) is suspended — every
Agent/Investor/Customer under it sees: "This business is temporarily
suspended. Will be available soon."
