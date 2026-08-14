-- The platform's own Terms & Conditions and Privacy Policy, versioned.
--
-- There was nowhere to put these. The only T&C surface was a single
-- ui_translations row (`terms_body`), which is not somewhere a 27,700-character
-- legal document can live, and agreement_acceptances is unrelated — its
-- agreement_id points at business_agreements, the owner-to-investor contracts,
-- and it demands an OTP per acceptance.
--
-- VERSIONED because clause 2.4 commits us to it: terms may be updated, and
-- continued use constitutes acceptance of the revised terms. That promise is
-- only auditable if we can say which version a person accepted and when.
-- Rows are never edited in place — a new version is a new row.

CREATE TABLE legal_documents (
  document_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_type        TEXT NOT NULL CHECK (doc_type IN ('Terms', 'Privacy')),
  version         TEXT NOT NULL,
  effective_date  DATE NOT NULL,
  -- 'English' / 'Telugu', matching preferred_language_enum's labels rather
  -- than ISO codes, so it lines up with what ManaLanguage.enumValue sends.
  locale          TEXT NOT NULL DEFAULT 'English',
  title           TEXT NOT NULL,
  -- The readable text, rendered in-app. Markdown so headings and clause
  -- numbering survive without shipping an HTML renderer.
  body_markdown   TEXT NOT NULL,
  -- Object path inside the 'legal-documents' bucket. The downloadable PDF is
  -- the authoritative artefact; body_markdown is the same content made
  -- readable on a phone.
  pdf_path        TEXT,
  is_current      BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'Asia/Kolkata'),
  UNIQUE (doc_type, version, locale)
);

-- Exactly one current version per type and language. A partial unique index
-- rather than a trigger: "there is one live copy of the terms" is a fact about
-- the data, so the database should be the thing that refuses to hold two.
CREATE UNIQUE INDEX legal_documents_one_current
  ON legal_documents (doc_type, locale)
  WHERE is_current;

CREATE TABLE legal_acceptances (
  acceptance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id     BIGINT NOT NULL REFERENCES persons(person_id) ON DELETE CASCADE,
  document_id   UUID NOT NULL REFERENCES legal_documents(document_id),
  accepted_at   TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'Asia/Kolkata'),
  -- One acceptance per person per document version. Re-accepting the same
  -- version is not a new fact.
  UNIQUE (person_id, document_id)
);

ALTER TABLE legal_documents   ENABLE ROW LEVEL SECURITY;
ALTER TABLE legal_acceptances ENABLE ROW LEVEL SECURITY;

-- Readable by anyone, signed in or not. LR-004 has to show the terms to
-- someone who is registering and therefore has no session yet, and refusing to
-- show a person the contract before they agree to it would be indefensible.
CREATE POLICY legal_documents_public_read ON legal_documents
  FOR SELECT USING (true);

-- A person's acceptances are their own. Not owner-visible: whether someone
-- accepted the PLATFORM's terms is between them and us, and an Owner has no
-- business reading it.
CREATE POLICY legal_acceptances_self_read ON legal_acceptances
  FOR SELECT USING (person_id = app.current_person_id());

CREATE POLICY legal_acceptances_self_insert ON legal_acceptances
  FOR INSERT WITH CHECK (person_id = app.current_person_id());

-- Private bucket. The PDF is not a secret, but a public bucket is an
-- unauthenticated URL that outlives any decision to withdraw a version.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('legal-documents', 'legal-documents', false, 10485760, ARRAY['application/pdf'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY legal_documents_pdf_read ON storage.objects
  FOR SELECT USING (bucket_id = 'legal-documents');
