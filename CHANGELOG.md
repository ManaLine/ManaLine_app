# What changed, and why

Plain English, newest first. One entry per working session.

**Who this is for:** SP, reading this months from now, wondering why something
is the way it is. No code in here — file names only, so you know where to point
an AI session. The full technical reasoning lives in the commit messages and in
comments at the top of the files themselves.

**How to keep it:** add an entry at the end of each session, before pushing.
Say what changed, what it fixes in real terms, and anything deliberately left
undone. If a decision was a judgement call, write down the reason — that is the
part nobody remembers later.

---

## 2026-08-22 — A book cannot be imported twice, and every page says what is in it

- **The whole book went in twice, live.** Step 4 of the migration wizard sent
  54 loans. The app gives any single tap 20 seconds; the server needed longer,
  so the screen said "The server did not respond" while the import was in fact
  finishing. Pressing Retry put it all in again: 108 loans, an outstanding
  figure of 57,90,300 against a true 30,04,900, and a day ledger that cascaded
  to minus 8,20,320. Nothing on screen ever looked wrong. Both copies were
  incomplete, so both were removed and the business is back to where it was
  before the import, with the reason recorded on every removed row.
- **Three separate things had to be true for that, and all three are fixed.**
  Bulk work now gets five minutes rather than twenty seconds, and a Retry keeps
  that same allowance instead of dropping back to twenty. The loan import
  carries a key minted when the Owner taps Import, so the server can tell a
  retry from a second import and hands back the first result instead of writing
  again. And the key is thrown away once the import succeeds, so a later,
  deliberate second import still works.
- **Every wizard page now shows what is already in.** "Already In — 55
  customers, 3 investors, 1 agent." Counted from the live rows each time the
  page is opened, not remembered — so going Back, or resuming tomorrow on
  another handset, no longer shows a page that looks untouched. A page with
  nothing in it stays silent, and so does one whose count could not be read:
  a page claiming zero when the phone is offline would be worse than no line.
- **The instalment replay can now be resumed.** It is one call per instalment,
  hundreds of them, and the run on 22 Aug stopped after 204 — leaving the book
  ₹2,48,400 short with no safe way forward, because re-uploading the sheet
  would have collected those 204 twice. The sheet is now read as the target
  state: an instalment already on the loan is left alone, and the screen says
  how many. Re-upload the same file as often as you like.

- **Re-uploading a sheet no longer imports its loans a second time.** The
  retry key only covers one tap; picking the same file again is a different
  thing, and it would have put all 54 loans in on top of the 54 already there —
  the same accident, through the door left open to fix it. A row whose loan is
  already on the book is now skipped, and the screen says how many.

- **A historical instalment bigger than the loan's EMI now imports.** The app
  treats any payment over the regular instalment as an excess and asks the
  agent how the extra was returned or carried — right at a customer's door,
  wrong when replaying a book that already happened. 46 instalments in this
  business are somebody paying two weeks at once, and every one of them was
  refused. The replay now records the extra as going against the instalments
  that followed, which is what the old book means and what its closing balance
  already reflects.
- **A payment dated before its loan now says so in words.** The server refused
  it with neither date in the message, leaving a row number and nothing to
  correct. It now names both dates and asks which one is wrong. Nothing is
  re-dated automatically — that would move money between two of your own books.

- **A sheet edited in Excel keeps its instalment history.** The templates are
  written with text cells; the moment you open one in Excel and save, every
  amount becomes a number and reads back as "600.0" instead of "600". All 250
  instalments in the live sheet were dropped that way — silently, while the 54
  loans beside them imported fine. Amounts are now read as whole rupees
  however the spreadsheet chose to write them, and anything still unreadable is
  counted on screen **before** the import rather than leaving a bare zero.
  Paise are refused outright, not rounded: money columns cannot store them.

- **Rebuilding the ledger now recomposes the BF it feeds.** BF is derived from
  the day ledger, but nothing recomputed it after a rebuild, so the stored
  figure and the derived one drifted apart in ordinary use — Rs 1,17,600 apart
  on the live book after the instalment replay, in the direction that flatters
  the till.
- **A migrated loan is now marked pre-existing.** It never was, so the agent's
  cash float was charged Rs 30,71,360 for a book that was lent before the app
  existed, and their BF derived to minus Rs 21,73,960. Every already-imported
  loan is corrected and BF recomposed.

- **Page 3 can now import money investors took back out.** There was no way to
  record a withdrawal that happened before you started using the app — the live
  screen stamps today's date — so a book with Rs 11,10,000 of withdrawals showed
  its investors owed that much too much. New sheet on page 3: one row per
  withdrawal, amount is the cash that left, and re-uploading it changes nothing.
- **Profit and investor payable are shown as at the cut-off, not today.**
  Interest keeps accruing after the cut-off, so today's figure could never be
  checked against a book that stops in March. The card now names the date, and
  profit is the figure you declared rather than one derived from tables that
  never saw your closed loans.

- **Interest is credited for the time the money was actually in.** Recording a
  withdrawal used to rewrite history: the whole period re-accrued at whatever
  principal was left, so an investor who put in Rs 10,00,000 and later took
  Rs 9,00,000 out lost almost all the interest they had genuinely earned. The
  accrual now walks the withdrawals in date order. On the live book this closes
  the gap against the Owner's own figures from Rs 28,000 to Rs 1,600, and what
  remains is their own rounding.
- **Clearing a migrated span now starts where the ledger starts.** A day dated
  before the book's first account row survived inside the frozen span, where
  nothing could ever recompute it — one stale day showing minus Rs 68,500.

- **"Finish Migration" is no longer hidden under the Add A Customer button.**
- **The Attention Required card says what happened and what to do.** It always
  went somewhere useful when tapped; nothing on it said so. The "Updated ..."
  line is gone with it — a BF recompute touches that column, so a request from
  two days ago read as if it had just arrived.
- **A collection's outcome is in words.** "Details: Excess" was the raw
  database value and read as a warning; it only means the customer paid more
  than one instalment at once. Now "Payment: More Than The Instalment", in all
  five languages.

- **Portrait only.** This is a one-handed field app and every screen is laid
  out for a portrait phone; landscape was never a supported shape and looked it.
- **The opening screen is white.** The Android launch colour matches it exactly
  so the handover stays invisible. The "unable to connect" message went from
  white-on-white to dark ink in the same change.
- **Investor balances now match a migrated book to the rupee.** The book states
  the interest for its own span, the app derives from the cut-off onward — the
  same rule BF, line balance and profit already follow. Was Rs 1,600 under.

- **History was listing deleted money.** Of its nine sources only BF grants
  filtered deleted rows, so soft-deleted loans, collections, expenses and
  investments were all still on the screen — on the live book every "Loan To"
  row was a duplicate that had already been removed.
- **History is in date order again.** It sorted by when a row was typed in, so
  a migrated book shuffled January and March into import order.
- **A backdated entry no longer invents a time.** A collection taken in March
  announced itself at "8:14 AM" — the moment the spreadsheet was imported.
  Where only the day is known, only the day is shown.

- **A day in History opens on the cash carried into it.** It used to show a
  net — collections less what was lent — so every lending day read as a loss.
  The day now starts with its BF line and ends on a balance. For an Agent the
  figure is their own float, derived to that date rather than added up from a
  feed that only shows part of the business.

- **Investors and profit shares are entered in the app, not in Excel.** Search
  the people already on your books by name, MLID or village, tap one, and fill
  in what they put in. Dates come from a calendar and the interest type is a
  choice, so neither can be mistyped. A business has a handful of investors —
  downloading a sheet to retype names the app had just written down was work
  the task never asked for.

- **History shows the lending again.** Migrated loans were hidden because,
  when a day was shown as a net, listing them made every lending day read as a
  huge loss. The day now shows its closing balance, so there is nothing to
  protect against — and a day that closes on a figure the rows cannot account
  for is no use to anyone.
- **A deposit shows what was put in, not what is left.** An investor who put in
  Rs 10,00,000 and later withdrew Rs 9,00,000 had their original deposit drawn
  as Rs 1,00,000 — a past event restated with a later number.

- Files: `network_error_handler.dart`, `bulk_onboarding_service.dart`,
  `ow_bulk_onboarding_wizard.dart`, three new migrations.

## 2026-08-20 — Retrying a payment can no longer record it twice

- **Collections are now safe to retry.** An agent on 2G taps Save, the reply
  never comes back, the app offers Retry — and every retry used to record a
  *second* collection. The customer's balance dropped twice, the agent's cash
  rose twice, and nothing showed it until a settlement failed. Each save now
  carries a one-time key; if the same key arrives again the server replays the
  original receipt instead of writing anything. Verified: two identical calls,
  one collection, balance moved once.
  Files: `lib/shared/idempotency.dart`, `ow_006_collection_mode.dart`,
  `collection_mode_state.dart`, migrations `..._idempotency_for_financial_writes`,
  `..._record_collection_is_idempotent`.
  *Only collections so far. Loan issuance, expenses and settlements still need
  the same treatment — the mechanism is built and shared, so each is small.*

- **This changelog.** Recommended by the architecture guide and previously
  missing.

## 2026-08-20 — BF is a transfer, disputes reach the Owner, phantom investor gone

- **"August 2026 +₹0" was right; the day total was wrong.** Handing an agent
  their float moves cash from your till to their pocket inside the same
  business — nothing comes in or goes out. It was being counted as income, so
  History showed +₹11,000 for a day while the month correctly showed zero. Now
  shown in the list but counted in no total. *This was a bug introduced earlier
  the same day and caught by your question about the ₹0.*

- **"Waiting on Owner" now actually reaches the Owner.** The agent's screen
  promised the dispute had been sent. Nothing was sent anywhere, and the agent
  sat locked out of their round waiting. The Owner is now notified, and a card
  appears in Attention Required — a panel that until now was hardcoded empty
  and could never show anything at all.

- **Sri Tirumala Finance no longer claims you are an Investor.** There was an
  investor membership with no investment behind it, left over from older
  behaviour. Cleared, and the app now ignores such rows so it cannot recur.

## 2026-08-20 — Fonts ship inside the app; shared card and loading state

- **The app no longer downloads its fonts.** They were fetched over the network
  on first use, so a village user on 2G saw fallback fonts and money columns
  lost their alignment. Both now ship inside the APK.
- **Loading looks like the page instead of a spinner** on 15 list screens.
- **`ManaCard`** for the card padding and spacing that was drifting screen to
  screen. Adopted on 8 screens so far; the rest vary too much to convert safely
  in bulk.

## 2026-08-20 — One name per text style, one way to write a rupee amount

- **327 hand-written text styles became named roles.** Restyling the app used
  to mean editing 327 places.
- **Rupee amounts have one formatter.** Negatives now read −₹1,06,600 instead of
  ₹-1,06,600, where the minus sign was easy to miss.

## 2026-08-20 — Seven live-test fixes, and BF opens the day

- **Cash in Hand showed −₹1,06,600.** Two migrated loans were counted against
  an agent float that never held the money — that cash left the till months
  before the business joined MANA LINE. Corrected to +₹11,000, and no new
  negative can appear.
- **Agent BF grants appear in History**; they were previously invisible.
- **Collections stopped asking who paid** on every single entry. Customer
  unless you say otherwise, with an optional name for anyone else.
- **The History filter badge counts what you ticked** instead of always "1".
- **Memberships group by business** — one card, roles listed, instead of a card
  per role.
- **Add-a-village fills in mandal, district and state** from the PIN, but only
  when the reference agrees with itself: 8% of PIN codes list two districts and
  guessing writes a wrong address nobody reviews.

## 2026-08-19 — The onboarding wizard remembers where you stopped

- Eight pages and several file uploads is more than one sitting, and more than
  one phone. It used to reopen at page 1 with finished pages looking untouched,
  which is also how a book gets imported twice. Progress now lives on the
  server so it follows you between devices, with an offline fallback.
- **Bulk investor import accepts people who already exist.** It rejected every
  row for a pre-existing book — the exact case it was built for.
- **Merge All / Ignore All** on duplicate review. The live book flagged 55 rows.

## 2026-08-19 — Errors you can act on

- **Error messages stopped being database text.** "duplicate key value violates
  unique constraint uq_persons_mobile_number" now says the number belongs to
  someone else and to search by name. Unmapped errors deliberately still show
  their raw text — a friendly guess would hide a real bug.
- **Error messages now go away.** On this Flutter version a message with a
  button never dismissed itself; one sat over the Save buttons for six minutes
  and locked the screen.
- **Mobile number and door number are optional** when entering an old book.
  Requiring them meant inventing a phone number, which then collided with
  whoever really owns it.

---

*Entries before 2026-08-18 are in the git history only. Run
`git log --oneline` to see them; each commit message carries the reasoning.*
