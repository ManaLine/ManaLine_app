-- P2 of the identity spec: the name becomes two fields, because the app has to
-- know which part is the house name to match people reliably.
--
-- Surname first, per Andhra convention and the cards customers here hold:
-- "Karri Siri Manikanta Reddy" is Karri (intiperu) + Siri Manikanta Reddy.
--
-- WHY A TRIGGER AND NOT A GENERATED COLUMN
-- full_name was the obvious candidate for GENERATED (surname || given_name),
-- and loans.amount_given sets the precedent. It was rejected on blast radius:
-- four SECURITY DEFINER functions write persons.full_name directly —
-- register_new_agent, register_new_customer, register_new_investor and
-- anonymise_person — and a generated column rejects every one of those
-- inserts. Rewriting the three registration RPCs by hand, on the path that
-- creates customers and their loans, to avoid a trigger is not a trade worth
-- making. Those four keep working untouched.
--
-- PRECEDENCE, stated once so it is never ambiguous: THE PARTS WIN. If a
-- statement supplies surname or given_name, full_name is composed from them.
-- Only when a statement touches full_name alone — every legacy writer — are
-- the parts derived from it instead. That derivation is lossless here: all 37
-- existing rows split and rejoin byte-identically, verified before this ran.
--
-- full_name_local holds the Telugu spelling. Display only. It is never
-- matched, never printed on a KYC record, and never derived from anything —
-- the person types it themselves, which is the same rule LR-004 already
-- applies to the Latin spelling.

ALTER TABLE persons
  ADD COLUMN surname         VARCHAR(100) NOT NULL DEFAULT '',
  ADD COLUMN given_name      VARCHAR(150) NOT NULL DEFAULT '',
  ADD COLUMN full_name_local VARCHAR(300);

COMMENT ON COLUMN persons.surname IS
  'House name / intiperu. First word of full_name by convention. Authoritative: full_name is composed from this.';
COMMENT ON COLUMN persons.given_name IS
  'Everything after the house name, kept as one string. May be empty for a single-name person.';
COMMENT ON COLUMN persons.full_name_local IS
  'Telugu spelling of the name. Display only — never matched, never on a KYC record, never auto-transliterated.';

CREATE OR REPLACE FUNCTION app.sync_person_name()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_trimmed TEXT;
  v_first   TEXT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.surname, '') <> '' OR COALESCE(NEW.given_name, '') <> '' THEN
      NEW.full_name := btrim(COALESCE(NEW.surname, '') || ' ' || COALESCE(NEW.given_name, ''));
      RETURN NEW;
    END IF;
  ELSE
    IF NEW.surname    IS DISTINCT FROM OLD.surname
    OR NEW.given_name IS DISTINCT FROM OLD.given_name THEN
      NEW.full_name := btrim(COALESCE(NEW.surname, '') || ' ' || COALESCE(NEW.given_name, ''));
      RETURN NEW;
    END IF;
    IF NEW.full_name IS NOT DISTINCT FROM OLD.full_name THEN
      RETURN NEW;
    END IF;
  END IF;

  -- Legacy path: only full_name was supplied, so derive the parts from it.
  v_trimmed := btrim(COALESCE(NEW.full_name, ''));
  v_first   := split_part(v_trimmed, ' ', 1);
  NEW.surname    := v_first;
  NEW.given_name := btrim(substr(v_trimmed, length(v_first) + 1));
  NEW.full_name  := v_trimmed;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_person_name
  BEFORE INSERT OR UPDATE OF full_name, surname, given_name ON persons
  FOR EACH ROW EXECUTE FUNCTION app.sync_person_name();

-- Backfill. Splitting on the first space is the Andhra convention, and it is
-- exact for every row present: none has leading, trailing or doubled spaces,
-- and none is a single word.
UPDATE persons
   SET surname    = split_part(btrim(full_name), ' ', 1),
       given_name = btrim(substr(btrim(full_name),
                                 length(split_part(btrim(full_name), ' ', 1)) + 1));
