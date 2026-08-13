-- Profile photo menu: upload vs re-take, and viewing the registration
-- live capture that an upload no longer destroys.
INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada) VALUES
  ('upload_photo', 'Upload a Photo', 'ఫోటో అప్‌లోడ్ చేయండి', 'फ़ोटो अपलोड करें', 'புகைப்படத்தைப் பதிவேற்று', 'ಫೋಟೋ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ'),
  ('take_photo', 'Take a Photo', 'ఫోటో తీయండి', 'फ़ोटो लें', 'புகைப்படம் எடு', 'ಫೋಟೋ ತೆಗೆಯಿರಿ'),
  ('view_live_photo', 'View Live Photo', 'లైవ్ ఫోటో చూడండి', 'लाइव फ़ोटो देखें', 'நேரடி புகைப்படத்தைப் பார்', 'ಲೈವ್ ಫೋಟೋ ನೋಡಿ'),
  ('live_photo_from_registration_note', 'Taken at registration. Cannot be changed.',
   'నమోదు సమయంలో తీయబడింది. మార్చలేరు.',
   'पंजीकरण के समय ली गई। बदली नहीं जा सकती।',
   'பதிவின்போது எடுக்கப்பட்டது. மாற்ற முடியாது.',
   'ನೋಂದಣಿ ಸಮಯದಲ್ಲಿ ತೆಗೆದದ್ದು. ಬದಲಾಯಿಸಲಾಗುವುದಿಲ್ಲ.'),
  ('photo_unavailable', 'Photo could not be loaded.', 'ఫోటో లోడ్ కాలేదు.', 'फ़ोटो लोड नहीं हो सकी।', 'புகைப்படத்தை ஏற்ற முடியவில்லை.', 'ಫೋಟೋ ಲೋಡ್ ಆಗಲಿಲ್ಲ.')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english, telugu = EXCLUDED.telugu,
  hindi = EXCLUDED.hindi, tamil = EXCLUDED.tamil, kannada = EXCLUDED.kannada;
