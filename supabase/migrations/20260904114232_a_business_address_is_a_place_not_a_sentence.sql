-- Creating a business asked for its address in one free-text box. Two people
-- typing the same place produced two different addresses, neither carried a
-- PIN, and neither could be matched to anything.
--
-- It uses the registration process now: door number, then PIN plus at least
-- three letters of the village, picked from the LGD reference and composed
-- into "D.No 12, Dommarametta, Renigunta, Tirupati, Andhra Pradesh - 517536".
--
-- The picked village is deliberately NOT written into `locations`. A
-- registered office is not an operating area, and creating a row for one would
-- put a place into the operating directory that no collection round visits.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('door_no_street_field',
 'Door No / Street',
 'ఇంటి నంబరు / వీధి')
ON CONFLICT (translation_key) DO NOTHING;
