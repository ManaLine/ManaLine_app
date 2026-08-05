-- P2: let a person clear their own notifications.
--
-- notifications had SELECT and UPDATE policies scoped to
-- recipient_person_id, but no DELETE policy at all. A client-side delete would
-- therefore match zero rows -- and PostgREST returns 200 for a DELETE that
-- removes nothing, so "Clear" would have appeared to work and changed nothing
-- until the next refresh put every notification back.
--
-- Scoped to the recipient, exactly like the other two policies. A notification
-- is addressed to one person; nobody else may clear it, and clearing your own
-- must not touch a colleague's copy of the same event.
CREATE POLICY notifications_self_delete ON notifications
  FOR DELETE USING (recipient_person_id = app.current_person_id());
