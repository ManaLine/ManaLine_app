-- The roster shows one row per PERSON now, not one per membership, so a
-- status change has to ask which of their roles it is about.
--
-- Suspending somebody who is both an Agent and a Customer is two different
-- decisions: an Owner may well want to stop them collecting and go on
-- lending to them. Choosing one silently would make the other unreachable.
--
-- Asked only when it is a real question -- with a single role no sheet is
-- shown at all. Six people on the live books hold more than one role, and
-- every Owner is also an Agent, so this is not a corner case.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('which_role', 'Which Role?', 'ఏ పాత్ర?')
ON CONFLICT (translation_key) DO NOTHING;
