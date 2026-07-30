-- MANA LINE — operating areas become named, multi-village
--
-- BEFORE: `operating_areas` carried a single NOT NULL `location_id`, so
-- "operating area" was just a synonym for "village". An agent who walks
-- three villages on one round needed three operating_areas, which means
-- three agent_area_assignments and — the part that actually hurts — three
-- separate account_periods to open, submit and approve for what is one
-- day's work.
--
-- AFTER: an operating area is a NAMED round ("Srikalahasti round") with N
-- villages attached through `operating_area_locations`. One area, one
-- assignment, one account period, N villages.
--
-- Safe to do now and expensive to do later: this database has 5
-- operating_areas, 0 loans, 0 collections and 0 account_periods, so there
-- is nothing downstream to migrate. Every area is backfilled with exactly
-- one village and named after it, so nothing changes on screen until an
-- Owner adds a second village.
--
-- `operating_areas.location_id` is DROPPED rather than left nullable.
-- Keeping it as a "primary village" would mean two sources of truth for
-- the same question and every read site having to decide which one wins.

-- --------------------------------------------------------------------
-- 1. The name an area is known by.
-- --------------------------------------------------------------------
ALTER TABLE public.operating_areas
  ADD COLUMN name varchar(120);

-- --------------------------------------------------------------------
-- 2. The join table.
--
-- `business_id` is carried here deliberately, denormalised from the parent
-- area. It is what lets the partial unique index below keep the guarantee
-- that 20260101004200_dedupe_operating_areas_and_unique_constraint.sql
-- added — one village belongs to at most one area per business — which
-- would otherwise be lost when UNIQUE (business_id, location_id) goes away
-- with the column it was built on.
--
-- Soft delete via `removed_at`, per the schema's "nothing is ever hard
-- deleted" convention, and so detaching a village is auditable.
-- --------------------------------------------------------------------
CREATE TABLE public.operating_area_locations (
  operating_area_location_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operating_area_id uuid NOT NULL
    REFERENCES public.operating_areas (operating_area_id),
  location_id uuid NOT NULL
    REFERENCES public.locations (location_id),
  business_id uuid NOT NULL
    REFERENCES public.businesses (business_id),
  created_at timestamp NOT NULL DEFAULT now(),
  removed_at timestamp
);

COMMENT ON TABLE public.operating_area_locations IS
  'Villages attached to an operating area. N villages per area; a village belongs to at most one live area per business.';
COMMENT ON COLUMN public.operating_area_locations.business_id IS
  'Denormalised from operating_areas so uq_oal_business_location can enforce one-village-one-area per business.';

CREATE UNIQUE INDEX uq_oal_business_location
  ON public.operating_area_locations (business_id, location_id)
  WHERE removed_at IS NULL;

CREATE INDEX idx_oal_area
  ON public.operating_area_locations (operating_area_id)
  WHERE removed_at IS NULL;

-- --------------------------------------------------------------------
-- 3. Backfill BEFORE the old column goes away.
-- --------------------------------------------------------------------
INSERT INTO public.operating_area_locations (operating_area_id, location_id, business_id)
SELECT oa.operating_area_id, oa.location_id, oa.business_id
FROM public.operating_areas oa;

UPDATE public.operating_areas oa
SET name = l.village_town_name
FROM public.locations l
WHERE l.location_id = oa.location_id;

ALTER TABLE public.operating_areas
  ALTER COLUMN name SET NOT NULL;

-- --------------------------------------------------------------------
-- 4. Retire location_id. The UNIQUE constraint depends on it, so it goes
--    first; uq_oal_business_location above replaces the guarantee.
-- --------------------------------------------------------------------
ALTER TABLE public.operating_areas
  DROP CONSTRAINT uq_operating_areas_business_location;

ALTER TABLE public.operating_areas
  DROP COLUMN location_id;

-- --------------------------------------------------------------------
-- 5. RLS — mirrors operating_areas' own two policies, reached through the
--    parent area rather than duplicating the agent-permission logic.
--    RLS is NOT optional here: without it this table is readable by any
--    authenticated user and leaks which villages a business works.
-- --------------------------------------------------------------------
ALTER TABLE public.operating_area_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY operating_area_locations_owner_all
  ON public.operating_area_locations
  FOR ALL
  USING (app.is_owner(business_id))
  WITH CHECK (app.is_owner(business_id));

CREATE POLICY operating_area_locations_agent_select
  ON public.operating_area_locations
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.operating_areas oa
      WHERE oa.operating_area_id = operating_area_locations.operating_area_id
        AND app.is_active_agent(oa.business_id)
        AND (
          app.agent_permission(oa.business_id, 'can_view_dashboard')
          OR EXISTS (
            SELECT 1
            FROM public.agents a
            JOIN public.agent_area_assignments aaa ON aaa.agent_id = a.agent_id
            WHERE a.membership_id = app.active_membership_id(oa.business_id, 'Agent')
              AND aaa.operating_area_id = oa.operating_area_id
              AND aaa.removed_at IS NULL
          )
        )
    )
  );

GRANT SELECT, INSERT, UPDATE ON public.operating_area_locations TO authenticated;
