-- Villages the LGD directory has never heard of are legitimate and permanent:
-- hamlets, new settlements, local names that never entered government records.
-- Dommarametta is one -- the Owner's own village, and %dommaramet% returns
-- nothing in 768,529 rows. The problem was never that they are missing. It was
-- that adding one was uncontrolled free text, and two things follow.
--
-- ONE: it drifts. `ichapuram` at 532312 and the directory's `Ichchapuram` are
-- the same town -- the Owner confirms it, the railway station carries the
-- second spelling. add_location_if_missing dedupes on an EXACT name, so the
-- next person to type the other spelling gets a second location for one town
-- and the customers split between them.
--
-- (An earlier draft of this comment reached the right conclusion from the
-- wrong evidence: I matched `ichapuram` against the MANDAL named Ichchapuram,
-- not a village, because lgd_villages has no village row by either spelling at
-- that pincode. Corrected here rather than left standing.)
--
-- TWO: you cannot tell afterwards. `locations` recorded no provenance, so
-- finding the eight non-directory rows needed a NOT EXISTS join rather than a
-- filter. A village invented by mistake was indistinguishable from one that is
-- genuinely off the map.
--
-- pg_trgm is for the first: near-match before create. Into the extensions
-- schema, where pgcrypto and uuid-ossp already live.
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;

-- And provenance for the second.
--
-- Three values, not a boolean, because there are genuinely three cases and the
-- seeded metro GPO rows are neither of the other two.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'location_source_enum') THEN
    CREATE TYPE location_source_enum AS ENUM ('Directory', 'Owner Entered', 'Seed');
  END IF;
END $$;

ALTER TABLE locations
  ADD COLUMN IF NOT EXISTS source location_source_enum;

-- Backfill from what can still be worked out.
UPDATE locations l SET source = 'Directory'
 WHERE l.source IS NULL
   AND EXISTS (SELECT 1 FROM lgd_villages g
                WHERE g.pincode = l.pin_code
                  AND lower(g.village) = lower(l.village_town_name));

UPDATE locations l SET source = 'Seed'
 WHERE l.source IS NULL
   AND l.village_town_name LIKE '%GPO';

UPDATE locations l SET source = 'Owner Entered'
 WHERE l.source IS NULL;

ALTER TABLE locations ALTER COLUMN source SET DEFAULT 'Owner Entered';
