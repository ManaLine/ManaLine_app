-- "Not Provided" was being shown to people as if it were a name.
--
-- It is not a UI placeholder. It is STORED DATA: the literal string sits in
-- persons.father_husband_name, written by supabase/create_platform_admin.sql,
-- a one-off bootstrap script that needed something for a NOT NULL column and
-- put a sentence there. Universal Search then drew it in the line that
-- identifies a person -- "MLPI142496232 · Not Provided" -- where every other
-- row carries a real father's or husband's name.
--
-- Blanked rather than deleted-around: the column is NOT NULL with no length
-- CHECK, so '' is a legal value meaning exactly what it looks like, and the
-- screens that join these fields already drop empty segments. An absent fact
-- should render as absent, not as a sentence about its absence.
--
-- Scoped by exact match on the one known placeholder, not by a pattern. A
-- regex over names is how somebody genuinely called "None" loses theirs.
-- Verified first: a scan of persons.full_name, persons.father_husband_name and
-- businesses.business_name for placeholder-shaped values found exactly one row
-- in the whole database, and this is it.
UPDATE persons
   SET father_husband_name = ''
 WHERE father_husband_name = 'Not Provided';
