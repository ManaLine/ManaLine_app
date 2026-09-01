-- The "Panagal" row at PIN 517640 recorded its state as "Andhrapradesh".
-- Every other locations row, and every one of the 768,529 directory rows,
-- writes "Andhra Pradesh".
--
-- NOT COSMETIC. manaReferenceOptions narrows the district and mandal pickers
-- by matching the chosen state EXACTLY against lgd_villages. A row whose
-- state matches nothing in the directory can never be narrowed, so anybody
-- editing that address gets an empty district list and is pushed back into
-- free text -- which is how the row came to exist in the first place. One
-- hand-typed value quietly reproduces itself.
--
-- The district stays Tirupati. That is right: Srikalahasti mandal moved from
-- Chittoor to Tirupati in the 2022 reorganisation, and the directory carries
-- BOTH names for every village at this PIN, so Tirupati and Chittoor are each
-- legitimate answers. Confirmed with the Owner.
--
-- WHAT THIS DELIBERATELY DOES NOT DO: merge "Panagal" into
-- "Panagallu (Rural)". They are almost certainly the same settlement -- same
-- PIN, same mandal, and "Panagal" appears nowhere in the directory, so it was
-- typed by hand. But "almost certainly" is not a basis for rewriting the
-- addresses of nineteen customers, which is what Panagallu (Rural) carries.
-- The Owner has confirmed Panagal is a correct name for the place; both rows
-- stay, both are covered by the Uranduru area, and collection reaches every
-- customer on either. A merge needs somebody who knows the village to say so,
-- not an inference from a spelling.
UPDATE locations
   SET state = 'Andhra Pradesh'
 WHERE state = 'Andhrapradesh';
