-- Two questions the Add New Village form should never have asked a person to
-- answer from memory.
--
-- 1. WHAT MANDAL, DISTRICT AND STATE IS THIS?
--
-- It asked for all three as free text, which is how a village came to record
-- its state as "Andhrapradesh" and then narrow every picker to nothing. The
-- pincode already answers it, nearly always:
--
--     one state          17,148 of 17,183 pincodes   99.8%
--     <= two districts   16,800                      97.8%
--     <= three mandals   14,628                      85.1%
--
-- So the form can offer the answer instead of asking for it. A village the
-- directory has never heard of still sits in a mandal the directory knows.
--
-- 2. DID YOU MEAN ONE OF THESE?
--
-- add_location_if_missing dedupes on exact (pin_code, lower(name)), so two
-- spellings of one town become two locations.
--
-- Threshold 0.4, measured against real pairs rather than picked:
--
--     ichapuram / Ichchapuram              0.833   must catch  (one town)
--     Panagal / Panagallu                  0.636   should offer
--     Akkurthy / Akkurthi                  0.636   should offer
--     Srikalahasti / Kalahasti             0.533   should offer
--     Dommarametta / Dommara Pochampally   0.269   must NOT offer
--     Akkurthy / Madamala                  0.000   must NOT offer
--
-- Deliberately generous. These are SUGGESTIONS somebody can ignore: a false
-- one costs a glance, a missed one costs a duplicate village and customers
-- split across it.
--
-- NOTE: suggest_similar_villages is superseded by 20260904121753, which
-- deduplicates a village that appears twice because its pincode spans a
-- district split. This file is the record of what was applied.

CREATE OR REPLACE FUNCTION app.pin_administrative_options(p_pincode text)
RETURNS TABLE(mandal text, district text, state text, villages integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT g.mandal::text, g.district::text, g.state::text, count(*)::int
    FROM lgd_villages g
   WHERE g.pincode = btrim(p_pincode)
   GROUP BY g.mandal, g.district, g.state
   -- Most villages first: with a pincode spanning two mandals, the one
   -- carrying thirty is the likelier answer than the one carrying three.
   ORDER BY count(*) DESC, g.mandal;
$function$;

GRANT EXECUTE ON FUNCTION app.pin_administrative_options(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION app.suggest_similar_villages(
  p_pincode text,
  p_name    text
) RETURNS TABLE(
  village     text,
  mandal      text,
  district    text,
  state       text,
  location_id uuid,
  in_use      boolean,
  score       real
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
  SELECT l.village_town_name::text, l.mandal::text, l.district::text,
         l.state::text, l.location_id, true,
         extensions.similarity(lower(l.village_town_name), lower(btrim(p_name)))
    FROM locations l
   WHERE l.pin_code = btrim(p_pincode)
     AND l.status = 'Active'
     AND extensions.similarity(lower(l.village_town_name), lower(btrim(p_name))) >= 0.4

  UNION ALL

  SELECT g.village::text, g.mandal::text, g.district::text, g.state::text,
         NULL::uuid, false,
         extensions.similarity(lower(g.village), lower(btrim(p_name)))
    FROM lgd_villages g
   WHERE g.pincode = btrim(p_pincode)
     AND extensions.similarity(lower(g.village), lower(btrim(p_name))) >= 0.4
     AND NOT EXISTS (
       SELECT 1 FROM locations l2
        WHERE l2.pin_code = g.pincode
          AND lower(l2.village_town_name) = lower(g.village))

  ORDER BY 7 DESC, 1
  LIMIT 8;
$function$;

GRANT EXECUTE ON FUNCTION app.suggest_similar_villages(text, text) TO anon, authenticated;
