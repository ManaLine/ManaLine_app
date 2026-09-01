-- One pending join request broke the whole Business Detail screen:
--
--   type 'Null' is not a subtype of type 'Map<String, dynamic>' in type cast
--
-- fetchMembershipRequests embeds persons(full_name) to show WHO is asking.
-- The embed is not !inner, so when RLS hides the row PostgREST returns null
-- rather than dropping the request -- and the client cast it as non-null.
--
-- RLS hid it because owner_owns_pending_or_active_member only looks in
-- business_members, and somebody who has merely ASKED to join has no
-- membership row yet. Probed as the real Owner: can_see_requester_person_row
-- = 0.
--
-- RLS CHANGE, stated plainly: the Owner of a business may now read the
-- persons row of anybody with a request outstanding at that business. That is
-- the smallest grant that makes the approval queue usable -- an Owner cannot
-- decide on a request that shows no name -- and it ends the moment the
-- request is decided, because the predicate only matches status 'Pending'.
-- Approving creates a membership, which the existing branch already covers.
--
-- Nothing else widens: the function keeps its business_members branch exactly
-- as it was, and keeps reading businesses.owner_person_id rather than every
-- Owner-role membership, which is a separate question I am not answering here.
CREATE OR REPLACE FUNCTION app.owner_owns_pending_or_active_member(p_target_person_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM business_members bm
    JOIN businesses b ON b.business_id = bm.business_id
    WHERE bm.person_id = p_target_person_id
      AND b.owner_person_id = app.current_person_id()
  )
  OR EXISTS (
    -- Asked to join, not yet decided. The Owner has to see a name to answer.
    SELECT 1
    FROM membership_requests mr
    JOIN businesses b ON b.business_id = mr.business_id
    WHERE mr.person_id = p_target_person_id
      AND mr.status = 'Pending'
      AND b.owner_person_id = app.current_person_id()
  );
$function$;
