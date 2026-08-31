-- Adding an existing person as an Investor demanded the amount and the ROI in
-- the same breath. attach_investor_with_first_investment refuses outright
-- without an amount -- "An investment amount is required to add an investor."
-- -- so the Owner searched, found the person, pressed Add, and was told off
-- for not having filled in two boxes further down the sheet.
--
-- That is the wrong order for a doorstep. You establish who somebody is, and
-- then you talk about money. The person goes on the list first now; the
-- investment is recorded from their profile, where Record Investment already
-- lives.
--
-- attach_investor_with_first_investment keeps its amount guard and its
-- callers. This is the other half of the same idea, not a replacement: an
-- Owner who does have the figures to hand still adds both at once.
--
-- Idempotent in the same way its sibling is -- an existing membership is
-- reactivated rather than duplicated, and an existing investors row is
-- reused -- so pressing Add twice adds one investor.
CREATE OR REPLACE FUNCTION app.attach_investor(
  p_business_id uuid,
  p_person_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_membership_id uuid;
  v_investor_id uuid;
BEGIN
  IF NOT app.is_owner(p_business_id) THEN
    RAISE EXCEPTION 'Not authorized for this business' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM persons WHERE person_id = p_person_id) THEN
    RAISE EXCEPTION 'That person no longer exists.' USING ERRCODE = 'P0002';
  END IF;

  SELECT membership_id INTO v_membership_id
    FROM business_members
   WHERE business_id = p_business_id AND person_id = p_person_id AND role = 'Investor';

  IF v_membership_id IS NULL THEN
    INSERT INTO business_members (
      person_id, business_id, role, membership_status, verification_status,
      onboarding_method, invited_by_person_id, joined_at
    ) VALUES (
      p_person_id, p_business_id, 'Investor', 'Active', 'Not Required',
      'Direct Registration', app.current_person_id(), now()
    ) RETURNING membership_id INTO v_membership_id;
  ELSE
    UPDATE business_members
       SET membership_status = 'Active', removed_at = NULL,
           joined_at = COALESCE(joined_at, now())
     WHERE membership_id = v_membership_id;
  END IF;

  SELECT investor_id INTO v_investor_id FROM investors WHERE membership_id = v_membership_id;
  IF v_investor_id IS NULL THEN
    INSERT INTO investors (membership_id, person_id)
    VALUES (v_membership_id, p_person_id)
    RETURNING investor_id INTO v_investor_id;
  END IF;

  RETURN json_build_object(
    'membership_id', v_membership_id,
    'investor_id', v_investor_id
  );
END;
$function$;
