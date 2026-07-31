# MANA LINE — 15. CALCULATION ENGINE (Locked Formulas)
## Version 1.0 | CONFIRMED, MERGED EDITION — 2026-07-19 | Status: FULLY LOCKED

Purpose: Every formula referenced but never spelled out across OW/AG/CW/IW screens and the Global Rules Guide is defined here, precisely, with the exact math, inputs, and BR cross-references. This document is now the single source of truth for calculations — screens reference it, they do not redefine it.

New Business Rules introduced in this document: **BR-232 to BR-237**. These do not overwrite anything already locked; they fill formula gaps that were previously left as prose ("Owner decides", "calculated daily") without exact math.

---

### 1. PROFIT SHARE % — Agent (OW-002) & Investor (OW-003)

**Locked decision:** There is no system-calculated "base" (not Net Profit, not Gross Collections). Profit Share is a fully manual, Owner-declared amount — the % itself is not even applied automatically by the system to any ledger figure.

**BR-232 — Profit Share Declaration Model**
Rule: Profit Share % (Agent or Investor) is informational/contractual only. The Owner enters a % at the time of enabling it (OW-002 Compensation Structure / OW-003 Invest workflow), but the system does NOT auto-multiply this % against any collection or profit figure. Actual profit share payout is a separate manual entry by the Owner (BR-056: Manual Profit Distribution), recorded in the Distribution Ledger (BR-060). The % field exists for the Owner's own reference/reminder, not as a computed trigger.
Frequency: On demand only (BR-051 equivalent) — there is no monthly auto-run. Owner initiates a "Distribute Profit Share" action whenever they choose, enters the actual ₹ amount being distributed, and the system logs it against that Agent/Investor's ledger with the Effective Date already on record (BR-057).
Module Context: Finance Management / Agent Management / Investment Management

Screen impact: OW-002 Compensation Structure and OW-003 Invest workflow both keep the "Profit Share %" field exactly as designed (optional, tentative, disabled by default) — no redesign needed. Add one linked action, "Distribute Profit Share," to the Agent Profile and Investor Profile screens (Compensation History / Interest Ledger tabs) that opens a manual entry: Amount, Business Date, Remarks → Save → Distribution Ledger entry created (BR-060).

---

### 2. PAYMENT ALLOCATION ORDER — Collection Mode (OW-006/AG-002) & Customer Payments (CW-005)

**Locked decision:** No waterfall/priority split (no Penalty→Interest→Principal). Loan interest is never collected as a separate line item during repayment — it was already deducted upfront at disbursement (BR-004/BR-011: Amount Given = Repayment Amount − Interest − Processing Fee). So the only two things that can ever sit in a loan's outstanding balance are: (a) remaining installment principal, and (b) any Penalty amount added after grace period ends.

**BR-235 — Unified Remaining Balance Model**
Rule: A loan carries exactly one running figure: **Remaining Balance**. At loan creation, Remaining Balance = Repayment Amount (the full amount the customer must pay back over the loan term — this already excludes prepaid interest and fees per BR-004/BR-011). If/when a Penalty is applied after grace period ends (BR-236), the Penalty amount is added directly into Remaining Balance — it is not tracked or displayed as a separate collectible line item. Every payment collected, of any amount, at any time, simply reduces Remaining Balance by that amount. There is no allocation order to define because there is nothing to allocate between — one balance, one reduction.
This applies identically in OW-006 Collection Mode, AG-002 Agent Collection, and CW-005 Customer Payments.
Module Context: Loan Management / Collection Management

Note: this simplifies (and does not conflict with) the existing Partial Collection logic already shown in OW-006 ("Collected Amount < Installment Amount → Pending Difference stored, Loan Week does not advance"). That logic is about **installment-level** progress tracking (BR-112: Completed Weeks Progress based on full installment completion). Remaining Balance is the loan-level total; installment tracking is a separate, unaffected layer that already works exactly as designed.

---

### 3. DAILY INTEREST CALCULATION — Simple vs Yearly Compound (BR-032/BR-033/BR-053/BR-055) — Investor Ledger (IW-003)

**Locked decision (from your answer):** ROI is entered in Rupees per ₹100 per month — the standard rural-finance convention (e.g., ₹1.5 per ₹100/month on a ₹100,000 investment).

**BR-233 — ROI Rate Format**
Rule: Investor ROI is always entered and stored as "₹ per ₹100 per month" (e.g., 1.5). This is the only supported ROI input format in V1 — not annual %, not flat ₹.
Module Context: Investment Management / ROI

**BR-234 — Interest Calculation Formula**
Rule (Simple Interest, default — BR-033):
```
Daily Interest Amount = Principal × (ROI ÷ 100) ÷ 30
Accrued Interest (as of any date) = Daily Interest Amount × Days Elapsed
```
Where:
- `Principal` = current investment principal (unaffected by simple interest; only changes via BR-170 partial withdrawal or new capital)
- `ROI` = the ₹-per-100-per-month rate on record (BR-050: fixed per period, prospective changes only)
- `Days Elapsed` = Business Date (today) − later of (Investment Start Date / Last Interest Payment Date, per BR-051: "calculated until payment date")
- **30-day month convention** — every month is treated as 30 days for daily-rate purposes, regardless of actual calendar days (standard convention for ₹-per-100-per-month rates). **CONFIRMED 2026-07-17.**

Rule (Yearly Compound — BR-053):
```
At each 12-month anniversary of the investment (or last compounding event):
  New Principal = Old Principal + Accrued Interest for that completed year
  Accrued Interest for that year = Daily Interest Amount (computed on Old Principal) × 360
Interest for the NEW year then accrues daily on New Principal using the same Simple formula above,
until the next 12-month anniversary triggers compounding again.
```
Interest Type (Simple/Compound) is fixed per investment at creation and frozen in the Agreement Snapshot (BR-034) — it cannot change mid-investment.

**ROUNDING RULE — NEW, mobile scenario-testing session 2026-07-19 (see
03B_Database_Schema_ADDENDUM_v2.md §1 for full scope, applies system-wide
not just here):** every calculated amount — Daily Interest Amount, Accrued
Interest, each year's compounding result — rounds UP (ceiling) to the
nearest whole rupee at the point it's calculated. For Yearly Compound
specifically: each year's New Principal rounds up BEFORE it feeds into the
next year's calculation as Old Principal — rounding compounds forward
year-over-year, it is not deferred to a single rounding step on the final
total. No paise are ever stored or displayed anywhere in the app.

Rule (System vs Owner — BR-055 unchanged): the system auto-calculates Accrued Interest daily using the formula above; the Owner verifies/confirms before any interest payout is recorded. Outstanding (unpaid) interest is never auto-converted to principal outside a compounding event (BR-052).
Module Context: Investment Management / Interest Engine

---

### 4. GRACE PERIOD PENALTY — Post-Grace Manual Entry

**Locked decision (from your answer, amends the timing implied — but not the fields — in BR-206):** Penalty is NOT auto-calculated and does not auto-apply the moment grace period ends. It is a manual Owner action triggered at that point.

**BR-236 — Grace Period Penalty Application**
Rule: When (Due Date + Grace Period) passes with the loan still not fully settled, the loan's status flag changes to "Penalty Eligible" (BR-113) and surfaces in OW-006/AG-002 collection lists (already-designed "Penalty" sort/status). No penalty amount is added automatically. The Owner, or an Agent explicitly granted a "Can Apply Penalty" permission (new granular permission, added to the existing OW-002 Permission Management list alongside "Can Collect Payments" / "Can Issue Loans" etc., per BR-073/BR-074), then manually opens the loan, selects a Penalty Option, and enters the Penalty Amount. On Save:
```
Remaining Balance = Remaining Balance + Penalty Amount   (per BR-235)
Loan Status → "Penalty" (visible to customer per BR-206: penalty is the only thing revealed; grace period itself stays internal)
Customer Notification → sent immediately (penalty applied)
Audit Entry → created (BR-003)
```
Penalty Options available to the Owner at this entry point (matches BR-009 "Penalty is not fixed and is decided by the owner per loan"):
- Flat ₹ Amount
- % of Overdue Installment
- % of Remaining Balance
(Owner picks one option and enters the value each time — no system default, no locked calculation method across loans; this preserves full owner discretion as already established by BR-009.)

Relationship to BR-206: BR-206 remains correct that Grace Period (days) is set at Loan Creation. BR-236 clarifies (**CONFIRMED 2026-07-17**) that the **Penalty amount/option itself is decided at the moment grace expires**, not pre-set at loan creation — the Loan Creation screen's "Penalty" field (BR-206) is read as an optional default/template the Owner may pre-fill, but the actual applied penalty is always the manual post-grace entry described here.
Module Context: Loan Management / Penalty Engine

Screen impact: OW-002 Permission Management list gains one new toggle — "Can Apply Penalty" — alongside the existing permission checkboxes (Can Collect Payments, Can Issue Loans, etc.). Default: OFF for new Agents, Owner enables per Agent as needed.

---

### 5. SHORT / EXCESS CALCULATION — Day Closure → Salary Formula (BR-068)

**BR-237 — Short/Excess Determination**
Rule:
```
Expected Closing Balance = BF Cash (opening)
                          + Total Collections (all payment modes, this agent, this Business Date)
                          + Total Loan Repayments Received
                          − Total Loans Disbursed (cash handed out)
                          − Total Expenses Recorded
                          − Cash Handed to Another Agent (BR-173 transfer out)
                          + Cash Received from Another Agent (BR-173 transfer in)

Difference = Physical Closing Balance (actual counted cash, confirmed via Owner PIN per BR-163) − Expected Closing Balance

If Difference = 0.00        → Zero Difference Policy satisfied; Day Closure allowed (BR-043/BR-219)
If Difference < 0.00        → SHORT.  Short Amount = |Difference|.  Recorded to that Agent's individual ledger (BR-066).
If Difference > 0.00        → EXCESS. Excess Amount = Difference.  Recorded to Excess Ledger (BR-070).
```
Feed into Salary Formula (BR-068, REWRITTEN — mobile scenario-testing
session 2026-07-19, supersedes BR-046/BR-068/BR-237 in part):
```
Payable Salary (this cycle) = (Daily Rate × Working Days) + Other Owner-
                                Approved Expenses − Shorts (ONLY IF Owner
                                chooses to deduct this cycle)
```
Two corrections from the original formula:
1. **Daily Allowance removed entirely.** BR-046's old language ("not an
   expense; reduces final salary") is superseded. Daily Allowance (e.g.
   ₹200/day) is paid same-day, direct cash to the Agent, with ZERO
   relationship to Payable Salary — it never appears in this formula in
   any form. It's tracked only for Owner visibility in the new Daily
   Allowance tab (OW-013) — see 03B_Database_Schema_ADDENDUM_v2.md §3.
2. **Shorts are no longer automatic.** A Short is always recorded (agent
   still owes it, permanent ledger entry, BR-066 unchanged), but the Owner
   now manually decides EACH CYCLE whether to actually deduct it from that
   salary run: **Deduct** (subtracts from Payable Salary this cycle),
   **Waive** (short stays on record as owed, not taken this cycle), or
   **Defer** (carries forward, Owner re-decides next cycle). Mirrors the
   already-locked Waive/Reduce Penalty pattern on loans.
Excess is unchanged — deliberately **excluded** from the Salary Formula, it
is never auto-credited back to the agent's salary. It sits in the Excess
Ledger for the Owner to manually adjust (BR-070), e.g. applying it as a
Temporary Adjustment to a customer's pending settlement (BR-045), or
otherwise, entirely at Owner discretion.

Owner BF interaction (NEW — see 03B_Database_Schema_ADDENDUM_v2.md §4): at
settlement, the FULL Expected Closing Balance (the agent's assigned BF)
returns to businesses.owner_bf_balance regardless of a declared Short — the
Short never reduces what flows back to the Owner's pool; it exists purely
as the standalone receivable described above.
Module Context: Day Closure / Agent Management / Salary Engine

---

### 6. LINE SCORE CALCULATION — Included by Reference (Already Locked)

Line Score is **already fully locked** in the Global Rules Guide (BR-210 to BR-218, session 2026-07-16) — it does not need to be redefined here, only cross-referenced so this document is a complete calculation index:

```
Line Score = min( On-Time Ratio Component + Loan Completion History Component
                   + Penalty Frequency Component + Penalty Recovery Bonus , 93 )
```
- New customers start at 35 (BR-211)
- On-Time Ratio (max 40): (On-Time % across all loans) × 40, most recent loan weighted 1.5x (BR-212)
- Loan Completion History (max 25): +12.5 per fully-closed clean loan, capped at 25; any defaulted/written-off loan zeroes this component (BR-213)
- Penalty Frequency (starts 20, deducts): −5 per loan that ever crossed into Penalty status, floor 0, most recent loan weighted 1.5x (BR-214)
- Penalty Recovery Bonus (uncapped): +3 per Penalty-status loan closed with penalty actually paid in full (BR-215)
- Hard cap at 93, never stored — recalculated live on every view (BR-210/BR-216B)

No changes required. Included here purely so the Calculation Engine document is the complete, single index of every locked formula in the system.

---

### STATUS: FULLY LOCKED (confirmed 2026-07-17)

All three open items are confirmed:
1. 30-day month convention — CONFIRMED.
2. BR-236 timing (post-grace manual penalty entry, BR-206 as optional pre-fill template) — CONFIRMED.
3. Penalty can be applied by Owner or by Agents with the new "Can Apply Penalty" permission — CONFIRMED. OW-002 Permission Management updated accordingly.

This document is now closed. No open items remain. Proceeding to Phase 2 (Database Schema) one file/module at a time, per your instruction — full 14-file loose-end audit to follow once Phase 2 output is complete.

---

---

===============================================================================
15_Calculation_Engine — APPENDIX A
WORKED EXAMPLE: INVESTOR INTEREST CALCULATION (BR-233/BR-234)
Cross-referenced from: IW-003 My Investments, IW-004 Request Withdrawal
Status: LOCKED (appended to 15_Calculation_Engine.txt, does not alter any
existing formula — illustrative worked example only)
===============================================================================

PURPOSE
Demonstrate BR-233/BR-234 with concrete numbers so IW-003/IW-004 field
values can be verified against a known-correct calculation during
development and QA.

-------------------------------------------------------------------------------
INPUTS
-------------------------------------------------------------------------------
Principal (original_principal_amount) : ₹100,000
Effective Date                        : 09/05/2021
Business Date (today, for this example): 18/07/2026
ROI (roi_rate)                         : ₹1.50 per ₹100 per month (BR-233)
Days Elapsed                           : 1,896 calendar days
  (Business Date − Effective Date; no prior interest payment recorded,
  so "later of Effective Date / Last Interest Payment Date" = Effective
  Date, per BR-234. 30-day month convention applies only to the daily
  rate divisor, never to the elapsed-day count itself.)

-------------------------------------------------------------------------------
CASE A — SIMPLE INTEREST (interest_type = 'Simple')
-------------------------------------------------------------------------------
Daily Interest Amount = 100,000 × (1.50 ÷ 100) ÷ 30 = ₹50.00 / day
Accrued Interest       = 50.00 × 1,896 = ₹94,800.00

Principal is unaffected by Simple Interest (BR-234) — it changes only
via withdrawal (BR-170) or new capital.

IW-003 List Row (this investment):
  Principal Amount          : ₹100,000.00
  ROI                       : ₹1.50 / ₹100 / month
  Interest Method           : Simple
  Effective Date            : 09/05/2021
  Interest Accrued to Date  : ₹94,800.00
  Interest Paid to Date     : ₹0.00
  Status                    : Active

IW-004 Available Balance = Principal + Accrued Interest
                          = 100,000.00 + 94,800.00 = ₹194,800.00

-------------------------------------------------------------------------------
CASE B — YEARLY COMPOUND (interest_type = 'Yearly Compound')
-------------------------------------------------------------------------------
Per BR-234, compounding fires at each 12-month anniversary of
Effective Date. Annual accrual on the pre-compounding principal =
Daily Interest Amount (on Old Principal) × 360, which for a 1.50 ROI
reduces to a flat 18% (1.50 × 12) applied to Old Principal.

Compounding Event  | Old Principal  | Year's Interest (18%) | New Principal
09/05/2022         |   100,000.00   |       18,000.00        |   118,000.00
09/05/2023         |   118,000.00   |       21,240.00        |   139,240.00
09/05/2024         |   139,240.00   |       25,063.20         |   164,303.20
09/05/2025         |   164,303.20   |       29,574.58         |   193,877.78
09/05/2026         |   193,877.78   |       34,898.00         |   228,775.78

Each row above is one `investment_interest_ledger` row with
entry_type = 'Compounding Event'. After the 5th event,
`investments.principal_amount` = 228,775.78 and
`last_compounding_date` = 09/05/2026.

Remaining period (09/05/2026 → 18/07/2026 = 70 days) accrues Simple
Interest on the new principal, per BR-234's "Interest for the NEW
year then accrues daily on New Principal using the same Simple
formula":
  Daily Interest Amount = 228,775.78 × (1.50 ÷ 100) ÷ 30 = ₹114.39 / day
  Accrued Interest (70 days) = 114.39 × 70 = ₹8,007.15

IW-003 List Row (this investment):
  Principal Amount          : ₹228,775.78
  ROI                       : ₹1.50 / ₹100 / month
  Interest Method           : Yearly Compound
  Effective Date            : 09/05/2021  (frozen, Agreement Snapshot —
                               never changes regardless of compounding)
  Interest Accrued to Date  : ₹8,007.15  (current partial year only —
                               prior years' interest is already folded
                               into Principal per BR-052: compounded
                               interest is never re-shown as separately
                               withdrawable "interest")
  Interest Paid to Date     : ₹0.00
  Status                    : Active

IW-004 Available Balance = Principal + Current-Year Accrued Interest
                          = 228,775.78 + 8,007.15 = ₹236,782.93

If Withdrawal Type = "Interest Only" is selected on IW-004, the
maximum requestable amount is capped at ₹8,007.15 — NOT the
cumulative interest since Effective Date — because every prior year's
interest already became Principal at its compounding event and is
withdrawable only as Principal from that point forward.

-------------------------------------------------------------------------------
AGREEMENT SNAPSHOT (BR-034) — IDENTICAL IN BOTH CASES
-------------------------------------------------------------------------------
original_principal_amount : ₹100,000.00
roi_rate                  : 1.50
interest_type              : Simple / Yearly Compound (frozen at creation,
                              cannot change mid-investment)
effective_date             : 09/05/2021
This block never changes regardless of any compounding events,
withdrawals, or interest payments — it is the permanent record of the
original terms, per BR-034.

-------------------------------------------------------------------------------
NOTES FOR QA / DEVELOPMENT
-------------------------------------------------------------------------------
  - Use this worked example as a regression test fixture: given the
    same inputs, both Case A and Case B figures above must reproduce
    exactly.
  - Rounding: all intermediate and final ₹ figures in this example are
    rounded to 2 decimal places (standard currency rounding). No
    rounding-mode (round-half-up vs banker's rounding) has been locked
    yet — FLAG, not blocking this appendix, but should be confirmed
    before Development phase if compounding chains grow long enough
    for rounding drift to matter.

===============================================================================
END OF APPENDIX A
===============================================================================
