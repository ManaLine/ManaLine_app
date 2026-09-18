-- The QR and UPI display, design document 2.2.1.
--
-- 'show_to_pay' is what the AGENT taps, so it is written from the agent's
-- side of the transaction -- they are showing it to somebody else, not
-- looking at it themselves.
--
-- 'upi_id_hint' carries a real example rather than a format description. An
-- Owner typing their own handle recognises "siri@okhdfcbank" instantly and
-- would have to decode "vpa@psp".
--
-- 'qr_keep_it_sharp' exists because the failure it prevents is silent. A QR
-- squeezed too hard still LOOKS like a QR and simply will not scan, and
-- nobody finds out until a customer is standing at a door with their phone
-- open. The app already refuses anything over 1 MB; this says why a sharp
-- original matters.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
('show_to_pay',        'Show To Pay',        'చెల్లించడానికి చూపండి'),
('payment_qr',         'Payment QR',         'చెల్లింపు QR'),
('upi_ids',            'UPI IDs',            'UPI IDలు'),
('upi_id',             'UPI ID',             'UPI ID'),
('add_upi_id',         'Add UPI ID',         'UPI ID జోడించండి'),
('upi_id_hint',        'e.g. siri@okhdfcbank', 'ఉదా. siri@okhdfcbank'),
('upi_id_invalid',     'A UPI ID looks like name@bank.',
                       'UPI ID name@bank లా ఉంటుంది.'),
('upload_qr',          'Upload QR',          'QR అప్‌లోడ్ చేయండి'),
('replace_qr',         'Replace QR',         'QR మార్చండి'),
('remove_qr',          'Remove QR',          'QR తీసివేయండి'),
('qr_keep_it_sharp',
 'Use the sharpest copy you have, under 1 MB. A blurred QR still looks right and will not scan.',
 'మీ దగ్గర ఉన్న స్పష్టమైన కాపీని వాడండి, 1 MB లోపు. అస్పష్టమైన QR చూడటానికి బాగానే ఉంటుంది కానీ స్కాన్ కాదు.'),
('no_payment_details_yet',
 'No QR or UPI ID has been added for this business yet.',
 'ఈ వ్యాపారానికి ఇంకా QR లేదా UPI ID జోడించలేదు.'),
('ask_owner_to_add_qr',
 'Ask the Owner to add one in Business Management.',
 'వ్యాపార నిర్వహణలో జోడించమని యజమానిని అడగండి.'),
('copied',              'Copied',            'కాపీ చేయబడింది'),
('payment_details',     'Payment Details',   'చెల్లింపు వివరాలు')
ON CONFLICT (translation_key) DO NOTHING;
