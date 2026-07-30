-- MANA LINE — Diagnostic: find duplicate villages (same name, different pincodes)
-- Run this in SQL Editor and send me the results — I'll build the actual
-- cleanup/merge script based on what's really there, rather than guess.

-- Query A: villages appearing under more than one distinct pincode
SELECT village_town_name, array_agg(DISTINCT pin_code) AS pincodes, count(*) AS row_count
FROM locations
GROUP BY village_town_name
HAVING count(DISTINCT pin_code) > 1
ORDER BY village_town_name;

-- Query B: full detail for the specific villages seen in testing screenshots
-- (Srikalahasti, Panagallu, Someswaram, Uranduru) — confirms exactly which
-- rows exist and their real pin_code/mandal/district values
SELECT location_id, pin_code, village_town_name, mandal, district, state, status
FROM locations
WHERE village_town_name IN ('Srikalahasti', 'Panagallu (Rural)', 'Someswaram', 'Uranduru')
ORDER BY village_town_name, pin_code;

-- Query C: any operating_areas already referencing one of the (possibly
-- duplicate) location_id rows above — IMPORTANT to check before deleting
-- anything, since a location_id already in use by a real operating_area
-- can't just be deleted outright (FK constraint would block it, or worse,
-- silently orphan data if that constraint is ever relaxed later)
SELECT oa.operating_area_id, oa.business_id, l.location_id, l.pin_code, l.village_town_name
FROM operating_areas oa
JOIN locations l ON l.location_id = oa.location_id
WHERE l.village_town_name IN ('Srikalahasti', 'Panagallu (Rural)', 'Someswaram', 'Uranduru');
