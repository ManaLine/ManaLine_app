-- The Owner has to be able to read what a merge will do before doing it.
--
-- 'merge_villages_note' names the three tables that move and says plainly that
-- the money does not, because that is the question anybody would have and the
-- answer is not obvious from a screen showing two village names.
--
-- 'merge_keeps' / 'merge_drops' are labels on the two sides of the choice
-- rather than "from" and "to". An Owner is deciding WHICH NAME SURVIVES on
-- every receipt and every round from now on, not a direction of travel.
INSERT INTO ui_translations (translation_key, english, telugu) VALUES
  ('merge_villages', 'Merge Villages', 'గ్రామాలను విలీనం చేయండి'),
  ('merge_villages_note',
   'Two entries for one village split its customers across two names. Merging moves everybody onto one. Their loans, collections and account history are not touched, and neither is who collects from them.',
   'ఒకే గ్రామానికి రెండు నమోదులు ఉంటే కస్టమర్లు రెండు పేర్ల మధ్య విడిపోతారు. విలీనం అందరినీ ఒకే పేరుపైకి తెస్తుంది. వారి రుణాలు, వసూళ్లు, ఖాతా చరిత్ర మారవు, వసూలు చేసేవారు కూడా మారరు.'),
  ('merge_keeps', 'Keep this one', 'దీన్ని ఉంచండి'),
  ('merge_drops', 'Move these people', 'వీరిని తరలించండి'),
  ('merge_swap', 'Swap', 'మార్చండి'),
  ('merge_confirm_question', 'Merge these two villages?', 'ఈ రెండు గ్రామాలను విలీనం చేయాలా?'),
  ('merge_confirm_note',
   '{count} people move from {from} to {to}. {from} stops being offered when anybody types a village.',
   '{count} మంది {from} నుంచి {to}కి మారతారు. ఎవరైనా గ్రామం టైప్ చేసినప్పుడు {from} ఇకపై కనిపించదు.'),
  ('merged_note', '{count} people now live in {to}.', '{count} మంది ఇప్పుడు {to}లో ఉన్నారు.'),
  ('no_duplicate_villages',
   'No village on this book looks like it has been entered twice.',
   'ఈ పుస్తకంలో ఏ గ్రామమూ రెండుసార్లు నమోదైనట్టు కనిపించడం లేదు.'),
  ('people_here', '{count} people', '{count} మంది'),
  ('merge_blocked', 'Cannot be merged', 'విలీనం చేయలేరు')
ON CONFLICT (translation_key) DO UPDATE
  SET english = EXCLUDED.english,
      telugu  = EXCLUDED.telugu;

DO $$
DECLARE v_n INT;
BEGIN
  SELECT count(*) INTO v_n FROM ui_translations
   WHERE translation_key IN ('merge_villages','merge_villages_note','merge_keeps',
                             'merge_drops','merge_swap','merge_confirm_question',
                             'merge_confirm_note','merged_note',
                             'no_duplicate_villages','people_here','merge_blocked')
     AND COALESCE(telugu,'') <> '';
  IF v_n <> 11 THEN
    RAISE EXCEPTION 'expected 11 translated keys, found %', v_n;
  END IF;
END $$;
