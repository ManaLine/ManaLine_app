-- The workspace chooser's second product card still transliterated the OLD
-- English name ("Chits") in every language: మానా చిట్స్, माना चिट्स and so on.
-- The Telugu normalisation pass did not catch it because it contained no
-- చేతి to replace — it was a different wrong word.
UPDATE ui_translations
SET english = 'MANA Cheeti — coming soon — version 2',
    telugu  = 'మానా చీటీ — త్వరలో — వెర్షన్ 2',
    hindi   = 'माना चीटी — जल्द आ रहा है — संस्करण 2',
    tamil   = 'மானா சீட்டி — விரைவில் — பதிப்பு 2',
    kannada = 'ಮಾನಾ ಚೀಟಿ — ಶೀಘ್ರದಲ್ಲಿ — ಆವೃತ್ತಿ 2'
WHERE translation_key = 'mana_chits_coming_soon';
