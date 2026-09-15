-- A person always has a name.
--
-- persons.full_name is NOT NULL and has been since module 0, and that constraint
-- has never been able to fire. trg_sync_person_name is a BEFORE INSERT trigger
-- that composes the name:
--
--   NEW.full_name := btrim(COALESCE(NEW.surname,'') || ' ' || COALESCE(NEW.given_name,''))
--
-- With surname, given_name and full_name all NULL that evaluates to btrim(' '),
-- which is ''. NOT NULL is satisfied. The row is a person with no name.
--
-- Found on 2026-09-15 by supabase/tests/schema_integrity_tests.sql, on the
-- first occasion it had ever been executed -- it asserted a 23502 that the
-- trigger made unreachable, and the assertion had been quietly wrong for as
-- long as the file had existed.
--
-- WHAT IT WOULD LOOK LIKE. Not an error. A blank where a name goes, on a
-- collection screen, next to an amount somebody is about to hand over. The
-- same category as a confidently wrong number: nobody notices.
--
-- Production held ZERO blank names when this was written, so no existing row
-- needed repair. What changes is the failure mode of the paths that could
-- create one -- the bulk identity import and the pre-existing-business wizard.
-- An import row with no name now fails loudly instead of landing nameless,
-- which is the trade this constraint is making on purpose.
--
-- btrim, not <> '', because ' ' is the value the trigger actually produces.
ALTER TABLE public.persons
  ADD CONSTRAINT persons_full_name_not_blank
  CHECK (btrim(full_name) <> '');

COMMENT ON CONSTRAINT persons_full_name_not_blank ON public.persons IS
  'BR-224. NOT NULL cannot fire here: trg_sync_person_name writes '''' before it is checked.';
