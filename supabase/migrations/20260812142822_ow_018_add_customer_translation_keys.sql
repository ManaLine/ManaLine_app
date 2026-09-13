-- Three keys the merge of claude/ui-shell-overhaul needs on OW-018.
--
-- That branch introduced the "add a customer" flow (pick an existing customer
-- or enter a new person inline) before this screen was translation-wired, so
-- it carried hardcoded English. main had the wiring but not the flow. The
-- merge kept the branch's behaviour and main's wiring, which leaves these
-- three labels without keys — and a missing key renders as the raw key
-- string on screen, which is the failure mode this project has hit before.
--
-- Restored from supabase_migrations.schema_migrations on 2026-09-13. The row
-- had been applied to production and the local file never written, which is
-- how a key that is live in the database reads as missing to any guard that
-- scans the migration folder. The body is verbatim, not rewritten.
INSERT INTO ui_translations (translation_key, english, telugu, hindi, tamil, kannada) VALUES
  ('add_a_customer',    'Add a Customer',    'కస్టమర్‌ను జోడించండి',   'ग्राहक जोड़ें',      'வாடிக்கையாளரைச் சேர்',   'ಗ್ರಾಹಕರನ್ನು ಸೇರಿಸಿ'),
  ('existing_customer', 'Existing Customer', 'ఇప్పటికే ఉన్న కస్టమర్', 'मौजূदा ग्राहक',      'ஏற்கனவே உள்ள வாடிக்கையாளர்', 'ಅಸ್ತಿತ್ವದಲ್ಲಿರುವ ಗ್ರಾಹಕ'),
  ('new_person',        'New Person',        'కొత్త వ్యక్తి',           'नया व्यक्ति',        'புதிய நபர்',              'ಹೊಸ ವ್ಯಕ್ತಿ')
ON CONFLICT (translation_key) DO UPDATE SET
  english = EXCLUDED.english,
  telugu  = EXCLUDED.telugu,
  hindi   = EXCLUDED.hindi,
  tamil   = EXCLUDED.tamil,
  kannada = EXCLUDED.kannada;
