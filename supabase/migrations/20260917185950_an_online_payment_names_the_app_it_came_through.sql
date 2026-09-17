-- The design document's mode column, at the granularity it actually asks for.
--
-- Page 4 of the 2024 design document writes the mode against every payment on
-- the Credits Received Slip, and page 5 glosses it: "© - Cash / ℗ - Online
-- Payment (Gpay,Phonepe, Paytm)". The table itself is finer than the gloss --
-- it writes G℗ and P℗, naming WHICH app -- and the Owner confirmed that
-- reading on 2026-09-17, choosing Cash / GPay / PhonePe / Paytm over a plain
-- two-way split. The reason is reconciliation: a PhonePe statement can only be
-- checked against a book that knows which payments were PhonePe.
--
-- I had this wrong in an earlier commit message, which called ℗ "Phone Pe".
-- It is online payment generally, and the provider is a separate fact.
--
-- ADDITIVE ONLY. payment_mode_enum already carries Cash, UPI, Cheque and Bank
-- Transfer, and collection_payment_splits is already live on it: 349 Cash, 5
-- UPI, 1 Bank Transfer across 353 undeleted collections. Removing or renaming
-- a value would rewrite six real payments into something nobody recorded, so
-- 'UPI' stays exactly where it is and keeps meaning what it meant -- an online
-- payment taken before the app could ask which app. New entries choose a
-- provider; the six historical rows are not touched and are not guesses.
--
-- IF NOT EXISTS on each, because this migration must be safe to re-run and
-- because ALTER TYPE ... ADD VALUE is not transactional in the way the rest of
-- this file's siblings are. Nothing USES these values in this migration, which
-- is deliberate: a value added and read in the same transaction raises
-- 55P04 "unsafe use of new value of enum type".
ALTER TYPE payment_mode_enum ADD VALUE IF NOT EXISTS 'GPay';
ALTER TYPE payment_mode_enum ADD VALUE IF NOT EXISTS 'PhonePe';
ALTER TYPE payment_mode_enum ADD VALUE IF NOT EXISTS 'Paytm';
