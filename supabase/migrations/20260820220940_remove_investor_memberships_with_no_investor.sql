-- One Investor membership existed with no `investors` row and no investment
-- behind it, so the workspace picker announced "Owner, Agent, Investor" for a
-- business the person had never put a rupee into.
--
-- Residue from the behaviour the membership_follows_activity migration
-- removed: a membership used to be inserted on its own and left there. This
-- clears what that left behind. Marked removed rather than deleted — the row
-- is a historical fact about what the app once did, and the audit trail here
-- is append-only by convention.
UPDATE business_members bm
   SET membership_status = 'Removed',
       removed_at = now()
 WHERE bm.role = 'Investor'
   AND bm.removed_at IS NULL
   AND NOT EXISTS (SELECT 1 FROM investors i WHERE i.membership_id = bm.membership_id);
