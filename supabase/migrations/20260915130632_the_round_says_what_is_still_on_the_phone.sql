-- The banner on the collection round, and the two things it can mean.
--
-- Deliberately TWO sentences rather than one with a number in it. A collection
-- still waiting for a signal needs nothing from anybody -- it will go. One the
-- server REFUSED needs a person, and at minute-scale that person is usually
-- still standing in front of the customer. If both read the same, the one that
-- needs attention gets none.
--
-- Neither says "error". A queued collection is not a failure: the money is
-- accounted for, the entry is on the phone, and it will go. The word an agent
-- reads here decides whether they walk back to a customer and collect twice.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('outbox_banner_waiting_note',
 '{count} collections are still on this phone. Tap to see them.',
 '{count} వసూళ్లు ఇంకా ఈ ఫోన్‌లోనే ఉన్నాయి. చూడటానికి నొక్కండి.'),
('outbox_banner_refused_note',
 '{count} collections were not saved. Tap to fix them.',
 '{count} వసూళ్లు సేవ్ కాలేదు. సరిచేయడానికి నొక్కండి.')
ON CONFLICT (translation_key) DO NOTHING;
