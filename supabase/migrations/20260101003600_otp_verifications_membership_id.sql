-- MANA LINE — 0036_otp_verifications_membership_id.sql
--
-- WHY: Role Escalation OTP verification needs to know WHICH
-- business_members row to mark verification_status='Verified' on
-- success — a person can hold multiple pending memberships (different
-- roles/businesses) simultaneously, so person_id alone is ambiguous.
-- auth-otp-verify's own code already flags this exact gap (see its
-- Role Escalation branch comment) rather than guessing. This is the
-- migration that comment asked for.

ALTER TABLE otp_verifications
  ADD COLUMN membership_id UUID NULL REFERENCES business_members(membership_id);

COMMENT ON COLUMN otp_verifications.membership_id IS
  'Set only for purpose=Role Escalation — identifies which business_members row to mark Verified on successful OTP confirmation. NULL for all other purposes (Registration/Password Reset/PIN Reset/Account Unlock have no membership context).';
