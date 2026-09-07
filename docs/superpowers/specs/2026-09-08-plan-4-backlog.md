# Plan 4 — storage, compression, and the handset-testing findings

Date: 2026-09-08
Status: scoped, deliberately not started. Runs AFTER Plan 2 (responsive) and
Plan 3 (public site + deploy).

Everything here was found while verifying Plan 1 — some by querying production,
some by the owner testing build 4 on a handset. It is written down because the
SDD ledger that held it is git-ignored and will be deleted; these findings must
outlive it.

## 1. Business logos are 3-5x over their own preset

`ManaPhotoPreset.logo` targets 100 KB with a 512 KB hard limit. Production says
otherwise:

| bucket | files | largest | average |
|---|---|---|---|
| `business-logos` | 4 | **493 KB** | 311 KB |
| `live-photos` | 5 | 36 KB | 30 KB |
| `profile-photos` | 6 | 58 KB | 44 KB |

Live and profile photos are already comfortably under 100 KB. Logos are not.

**Find the cause before changing any number.** Either the logo preset is not
applied on that upload path, or something bypasses `ManaPhotoCompressor`
entirely. Raising or lowering a constant without knowing which would be
guessing, and the guess that "the preset must be wrong" is the likely wrong one
— the preset already says 100 KB.

## 2. Two storage buckets have no limits at all

`dispute-documents` and `member-documents` both have `file_size_limit = NULL`
and `allowed_mime_types = NULL`. Any file, of any type, at any size.

Migration `20260805174607_photo_bucket_size_and_mime_limits.sql` exists
precisely to close this and covered three buckets — `live-photos`,
`profile-photos`, `business-logos`. It missed these two. Both are empty today,
so nothing has exploited it.

This is the same shape as every other regression this project has recorded: a
fix that was correct for the cases it covered, while other consumers of the
same idea went unlisted.

## 3. Documents cannot be 100 KB in colour, and grayscale is the answer

The owner's requirement is everything stored at **<= 100 KB with no
de-pixelating or noise**. For faces that is already met. For documents the two
halves of the requirement conflict, and `ManaPhotoPreset.document`'s own
comment says why:

> an Aadhaar card compressed until the number is a smear is worth nothing at all

That preset uses 1600px at quality 80 deliberately. Forcing 100 KB at 1600px in
colour means roughly quality 35-40, which will smear a 12-digit number.

**Convert document scans to grayscale before encoding.** Text compresses far
better without colour channels, so 1600px grayscale at quality ~75 lands near
100 KB with the digits still legible. That is how document scanners solve this,
and it satisfies both halves rather than trading one away.

## 4. PDFs cannot go through the image compressor

`legal-documents` accepts `application/pdf` up to **10 MB**.
`ManaPhotoCompressor` is image-only and throws `PhotoUnreadableException` on a
PDF, so "PDF under 100 KB" is not a setting to change.

The owner asked for a real PDF path: rasterise an uploaded PDF to JPEG so it
goes through the same compressor and lands under the same ceiling.

**The risk to weigh first:** PDF rendering needs a new dependency, and this
project has been burned by native dependencies before — `file_picker` had to be
removed over an AGP 9 build failure, and `ManaPhotoCompressor` is pure Dart
specifically so it could not repeat that. Prefer a pure-Dart rasteriser, or
accept a server-side conversion, over a native plugin.

## 5. The Settings PIN dialog

`_PinVerifyDialog`, `lib/shared/settings_screen.dart:700`. Three defects, one
reported by the owner and two found while confirming it:

- **`maxLength: 6` is hardcoded.** It never reads the person's real
  `pin_length`, so someone with a 4-digit PIN is shown `0/6` — the wrong number
  of digits to type.
- **The counter is visible.** `lr_009_daily_login.dart` uses
  `InputDecoration.collapsed()` specifically to suppress it, with a comment
  saying so. The app already made this decision; this dialog missed it.
- **A wrong-length PIN silently does nothing.** `settings_screen.dart:324` is
  `if (entered == null || entered.length != pinLength) return;` — the dialog
  closes, no error, no retry, no indication anything happened. This is the
  confidently-silent failure this codebase treats as worse than an error, on a
  login-adjacent path.

Required: read the real `pin_length`, drop the counter, and replace the silent
return with a visible error and a retry.

## Also noted, not yet scoped

- **Live Photo title contrast.** The app-bar title on the capture screen is
  dark blue on flat black. That bar used to sit over a camera preview; the
  colour was never chosen for a black backdrop. Cosmetic.
- **The business picker does not remember your last business.**
  `lr_012_business_selector.dart:151` auto-opens only for a single-business
  owner; with two or more the picker appears every time. This is current
  intended behaviour, not a defect — but `lastBusinessId` is already persisted
  and unused for this, so "remember and skip" is a small feature if wanted.
- **`CLAUDE.md` tells you to run `pwsh tool/run_sql_tests.ps1`.** `pwsh` is not
  installed on the development machine — only Windows PowerShell 5.1 — so that
  command fails with `CommandNotFoundException`. The scripts themselves run
  fine under 5.1. Either install PowerShell 7 or correct the invocation in the
  docs to `& .\tool\<script>.ps1`. Worth fixing: the SQL guards' whole history
  is that they never ran, and a documented command that fails is how that
  stays true.
- **BR-205's "New Device Login" notification was never implemented** —
  `supabase/functions/auth-login/index.ts:250` carries the TODO. A login from a
  new device currently alerts nobody.
- **BR-152/BR-197's Single Device Policy is recorded but not enforced.** The
  `devices` table tracks which device is active and nothing anywhere reads that
  to restrict a second one. The policy exists as bookkeeping.
