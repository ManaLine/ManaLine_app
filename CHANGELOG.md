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
