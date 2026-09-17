-- The Telugu for could_not_load_pull_to_retry, written a minute earlier, had a
-- Devanagari "ल" (U+0932) in the middle of "చేయలేకపోయాం" -- a Hindi letter
-- inside a Telugu word. It renders as a fallback glyph or a tofu box depending
-- on the handset's fonts, and it sits in the one sentence somebody reads when
-- something has already gone wrong.
--
-- Caught by re-reading what I had written rather than by any test. Nothing in
-- this codebase checks that a Telugu column contains Telugu, which is worth
-- knowing: every other translation this session went in unverified in exactly
-- the same way. Swept the whole table afterwards for Devanagari, Tamil and
-- Kannada letters in the telugu column -- this was the only one.
UPDATE ui_translations
   SET telugu = 'ఈ జాబితాను లోడ్ చేయలేకపోయాం. మళ్లీ ప్రయత్నించడానికి కిందికి లాగండి.'
 WHERE translation_key = 'could_not_load_pull_to_retry';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM ui_translations
              WHERE translation_key = 'could_not_load_pull_to_retry'
                AND telugu LIKE '%' || U&'\0932' || '%') THEN
    RAISE EXCEPTION 'the Devanagari letter is still there';
  END IF;
END $$;
