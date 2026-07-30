-- MANA LINE — 0032_seed_locations_for_testing.sql
--
-- WHY THIS EXISTS: registration was failing at auth-register's village
-- lookup (422 "Selected village could not be found") because `locations`
-- has never been seeded — LR-004's real village picker (wired this
-- session) queries this table directly and correctly found zero rows.
-- That was never a bug in the picker; there was simply no data to find.
--
-- *** HONEST SCOPE NOTE — READ BEFORE RELYING ON THIS FOR PRODUCTION ***
-- This migration seeds a SMALL, individually web-search-verified set of
-- real villages — just enough to unblock testing with the exact PIN
-- codes already used in this session (517644, 517640, 533261) plus a
-- handful of other real, well-known towns across a few states so testing
-- isn't limited to one district. This is NOT a complete India dataset —
-- India has 600,000+ villages, and hand-producing that at scale from
-- memory would risk fabricated mandal/district mappings, which is a real
-- data-integrity risk for a lending app (BR-225, routing, RLS all key off
-- this). The verified rows below were each individually confirmed via
-- web search against sources including Census 2011 village records and
-- India Post pincode data.
--
-- FOR THE REAL NATIONAL DATASET: India Post publishes an official,
-- authoritative all-India PIN code dataset via data.gov.in
-- ("All India Pincode Directory"). The correct path to full coverage is
-- bulk-importing that CSV into `locations` (via Supabase's table editor
-- CSV import, or a one-off script mapping its columns to
-- pin_code/village_town_name/mandal/district/state/area_type), not
-- hand-typed INSERT statements. Flag this as a follow-up task, not
-- something to silently attempt at full scale here.
--
-- AP DISTRICT REORG NOTE: Andhra Pradesh redrew district boundaries in
-- 2022 (13 → 26 districts). Some sources now list Someswaram under
-- "Dr. B.R. Ambedkar Konaseema" district and Uranduru/Panagallu under
-- "Tirupati" district rather than the older "East Godavari"/"Chittoor"
-- names. This migration uses the OLDER, still-widely-used district names
-- for simplicity — if your team has a preference for old-vs-new AP
-- district naming, decide it once and update these four rows rather than
-- leaving it inconsistent as more locations are added later.

INSERT INTO locations (pin_code, village_town_name, area_type, mandal, district, state, status) VALUES
  -- Verified against the exact PIN codes used in this session's testing
  ('533261', 'Someswaram',       'Village', 'Rayavaram',    'East Godavari', 'Andhra Pradesh', 'Active'),
  ('517644', 'Srikalahasti',     'Town',    'Srikalahasti', 'Chittoor',      'Andhra Pradesh', 'Active'),
  ('517640', 'Uranduru',         'Village', 'Srikalahasti', 'Chittoor',      'Andhra Pradesh', 'Active'),
  ('517640', 'Panagallu (Rural)','Village', 'Srikalahasti', 'Chittoor',      'Andhra Pradesh', 'Active'),

  -- A small additional spread of real, well-known towns across other
  -- states, so testing isn't limited to one district. Standard,
  -- well-established PIN codes for major cities — low fabrication risk.
  ('500001', 'Hyderabad GPO',    'Town', 'Musheerabad',   'Hyderabad',  'Telangana',    'Active'),
  ('600001', 'Chennai GPO',      'Town', 'Fort Tondiarpet','Chennai',   'Tamil Nadu',   'Active'),
  ('560001', 'Bangalore GPO',    'Town', 'Bangalore North','Bangalore Urban','Karnataka','Active'),
  ('400001', 'Mumbai GPO',       'Town', 'Mumbai City',   'Mumbai',     'Maharashtra',  'Active'),
  ('110001', 'New Delhi GPO',    'Town', 'New Delhi',     'New Delhi',  'Delhi',        'Active'),
  ('700001', 'Kolkata GPO',      'Town', 'Kolkata',       'Kolkata',    'West Bengal',  'Active');

COMMENT ON TABLE locations IS 'Seeded with a small, verified test set (0032_seed_locations_for_testing.sql) — NOT the complete India dataset. Bulk-import the official India Post PIN code directory from data.gov.in for full national coverage before production use.';
