-- A real bug, found by running the function rather than reading it: asking for
-- "Akkurthi" at 517536 returned Akkurthy TWICE. lgd_villages carries a row per
-- (village, mandal, district), and 517536 spans the Chittoor/Tirupati split,
-- so every village there appears twice. Offering one village as two choices
-- invites somebody to pick the wrong district for a place that has only one.
--
-- DISTINCT ON keeps the best-scoring row per name, in-use first so an existing
-- location wins over its directory twin. The district split is still a real
-- choice, but it belongs in pin_administrative_options where the person is
-- choosing a district, not smuggled into a list of village names.
--
-- (The version of this migration applied to production also carried a
-- paragraph claiming there was no demonstrated duplicate in the data, on the
-- grounds that lgd_villages has no village named Ichchapuram. That reasoning
-- was wrong twice over: the Owner confirms ichapuram and Ichchapuram are the
-- same town, and the absence of a directory row is exactly why it was
-- hand-entered. The near-match check is prevention for a case that is real.)
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
  SELECT DISTINCT ON (lower(c.village))
         c.village, c.mandal, c.district, c.state, c.location_id, c.in_use, c.score
    FROM (
      -- Villages already in use come first: those carry a real location_id,
      -- and reusing one is what stops a split.
      SELECT l.village_town_name::text AS village, l.mandal::text AS mandal,
             l.district::text AS district, l.state::text AS state,
             l.location_id, true AS in_use,
             extensions.similarity(lower(l.village_town_name), lower(btrim(p_name))) AS score
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
    ) c
   ORDER BY lower(c.village), c.in_use DESC, c.score DESC
$function$;

GRANT EXECUTE ON FUNCTION app.suggest_similar_villages(text, text) TO anon, authenticated;
