-- A saved wizard position points at a page number, and the pages just moved.
--
-- Areas & Villages was page index 1 of eight. Removing it shifts everything
-- after it down by one, so a pointer saved before today means a different page
-- now: a 3 was Customers and is now Agents. The screen clamps an out-of-range
-- pointer, which catches the tail but not the middle -- an Owner would simply
-- reopen on the wrong page, with the resume banner telling them it was where
-- they left off.
--
-- Shifted rather than reset. Resetting to page 1 would be safe and would also
-- throw away the one thing the pointer is for; the shift preserves exactly
-- what it meant. Indices 0 and 1 both become 0, because 1 WAS the page that
-- no longer exists and Identities is the honest place to put someone who was
-- standing on it.
UPDATE businesses
   SET migration_wizard_step = CASE
         WHEN migration_wizard_step <= 1 THEN 0
         ELSE migration_wizard_step - 1
       END
 WHERE migration_wizard_step IS NOT NULL
   AND migration_wizard_step > 0;
