-- The Local Government Directory's pincode-to-village mapping: India's
-- official village → sub-district → district → state hierarchy.
--
-- WHY THIS EXISTS. The app needs a village, its mandal, district and state for
-- every customer address. Asking the Owner for all four is unworkable — one
-- real book of 61 customers produced 53 distinct villages, and the India Post
-- pincode directory cannot name them because a hamlet is not a post office.
-- LGD can: Burmanguda, Chatraiputtu and Malaguda are all in here, with their
-- mandal, under 531077.
--
-- READ-ONLY REFERENCE. Nothing in the app ever writes to this table. A village
-- the Owner selects is copied into `locations`, which stays the app's own
-- truth; village_code is carried across so a verified village can later be
-- told from a typed one.
--
-- IT SUGGESTS, IT NEVER VALIDATES. Three of the eleven villages supplied for
-- testing sit under a different pincode here than the Owner gave, and four are
-- absent entirely. The Owner knows their ground; this is a national
-- compilation. Free-text entry has to remain, and a mismatch against this
-- table must never reject an address.
--
-- A VILLAGE NAME IS NOT A KEY. The same name occurs in many districts. The
-- identifying tuple is pincode + mandal + district, which is what the second
-- index serves (added in the follow-up migration, after the bulk import —
-- indexing 778,833 rows on the way in is far slower than indexing them once
-- they have landed).
--
-- 768,529 rows, from 2,363,007 in the source. The difference is LGD's
-- version-bump repeats — rows identical across every column kept here.
--
-- NO CODE COLUMNS. LGD ships village, sub-district, district and state codes;
-- none is read, joined on or displayed by this app, and this project is on the
-- 500 MB tier. Dropping them also collapsed ~10,000 rows that differed by code
-- alone. If LGD ever renames a village there is no stable key to re-match on;
-- the source workbook is kept outside the repo, so that is recoverable.
--
-- NO TEXT INDEX EITHER, deliberately. A trigram index on `village` would be
-- 80–150 MB, larger than the table. It is unnecessary because a village is
-- only ever searched WITHIN a pincode — the Owner enters the PIN first — so
-- the candidate set is a few dozen rows (358 at the worst pincode seen), which
-- Postgres filters off the pincode index without help.
CREATE TABLE lgd_villages (
  pincode  TEXT NOT NULL,
  village  TEXT NOT NULL,
  mandal   TEXT NOT NULL,
  district TEXT NOT NULL,
  state    TEXT NOT NULL
);

COMMENT ON TABLE lgd_villages IS
  'LGD pincode-to-village reference. Read-only; suggests addresses, never validates them.';

ALTER TABLE lgd_villages ENABLE ROW LEVEL SECURITY;

-- Readable by anyone, signed in or not: LR-004 picks a village during
-- registration, before a session exists — the same reason ui_translations is
-- anon-readable.
CREATE POLICY lgd_villages_public_read ON lgd_villages
  FOR SELECT USING (true);
