# App vocabulary review

Every distinct word, label and message the app shows, English beside Telugu, for
a read-through away from the code.

| File | What it is |
|---|---|
| `app_vocabulary.docx` | The review document — 5 columns, three sections, opens in Google Docs on a phone |
| `app_vocabulary.xlsx` | The same table as a spreadsheet — easier to type into on a phone, filter/sort on |
| `app_vocabulary.csv` | The same rows plus the translation keys, so corrections can be applied back to `ui_translations` |
| `ui_translations_dump.tsv` | The raw capture: `key~|~english~|~telugu`, one row per line |
| `build_vocabulary_review.py` | Regenerates the three files from the dump |

**Fill in the two "Changes" columns only.** A blank change cell means the wording
stays as it is.

## How the table was built

Source is the live `ui_translations` table — 1,692 rows. Rows are grouped **by the
English string**, because the same wording used on six screens is one wording
decision, not six: 1,613 rows to read instead of 1,692.

Where one English string has drifted into more than one Telugu wording, every
variant is shown in the cell, numbered, and the cell is marked. That drift is the
thing worth catching — 18 of them today.

Sections are by length, so the day-to-day vocabulary is read first and the long
notes last:

- **A — Words & Labels** (1,050): three words or fewer. Buttons, headings, field names.
- **B — Short Phrases** (329).
- **C — Messages, Notes & Helper Text** (234).

## Verification

The dump was checked row-for-row against per-row `md5()` values computed inside
the database, grouped by first letter: 1,691 of 1,692 rows are byte-identical.
The one exception is `terms_body`, which differs only in encoding — its two real
newlines are written here as a literal `\n` so the dump can stay one row per line.

## Known gaps this surfaced

- **9 strings have no Telugu at all.** Eight are the web-only strings
  (`web_home_*`, `web_route_unavailable_*`) and the ninth is `description`.
- **7 translation keys are raw English sentences with spaces in them** —
  `add a customer`, `existing customer`, `new person`, `exit app`,
  `save and add another`, `pre-existing business`,
  `are you sure you want to close mana line?`. Each is called from real screens,
  and each duplicates (or nearly duplicates) a properly-named key. Left alone:
  renaming a key is a code change, not a wording change.
