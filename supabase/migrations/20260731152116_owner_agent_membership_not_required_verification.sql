-- The Owner's own Agent membership must not sit in Pending Verification.
--
-- Sri Tirumala's Agent membership for the owner was 'Pending Verification'
-- while Satyanarayana's (created by owner_is_first_agent) was 'Not
-- Required'. LR-013 filters roles to Active AND (Verified OR Not Required)
-- per GLOBAL BR-191, so the Agent role vanished from the role switcher in
-- one business and appeared in the other — with only Owner left eligible,
-- LR-013 collapsed to a single role and went straight to the Owner home.
-- "Switch role does not work" was the role genuinely not being there.
--
-- WHY 'Not Required' IS RIGHT HERE, rather than raising an OTP prompt:
-- BR-188 requires OTP before an Agent role activates, and BR-190 makes it
-- mandatory when escalating an EXISTING CUSTOMER to Agent or Investor.
-- Neither addresses the Owner of the business also being its agent. That
-- person already registered with Aadhaar and a verified phone, holds the
-- Owner membership on the same identity, and is the one who would be
-- approving the verification. Re-OTPing them against their own business
-- adds friction and no security. Non-owner agents are untouched and still
-- require verification.
UPDATE business_members bm
SET verification_status = 'Not Required'
FROM businesses b
WHERE b.business_id = bm.business_id
  AND bm.person_id = b.owner_person_id
  AND bm.role = 'Agent'
  AND bm.membership_status = 'Active'
  AND bm.verification_status <> 'Not Required';
