-- The Terms & Privacy document ships as a bundled asset, so the table records
-- WHICH VERSION shipped rather than carrying a second copy of the text.
--
-- Bundling was the deliberate choice: these are field users on 2G in villages,
-- and the one document a person is entitled to read before agreeing to it must
-- not depend on having a signal. The cost is that changing the terms needs a
-- new build; the row below is what makes that auditable, because an acceptance
-- points at a version and a version names the file that was on the handset.
--
-- body_markdown therefore becomes nullable — it was written on the assumption
-- the text would live here and be rendered in-app. asset_path replaces
-- pdf_path as the location that actually matters; pdf_path stays for a future
-- hosted copy and is deliberately left NULL for now.
ALTER TABLE legal_documents
  ALTER COLUMN body_markdown DROP NOT NULL,
  ADD COLUMN asset_path TEXT;

COMMENT ON COLUMN legal_documents.asset_path IS
  'Path of the PDF bundled in the APK, e.g. assets/legal/<file>.pdf. The authoritative artefact.';
COMMENT ON COLUMN legal_documents.body_markdown IS
  'Optional in-app readable text. NULL when the bundled PDF is the whole document.';

-- Two rows, one file. LR-004 asks for the Terms and the Privacy Policy as
-- separate tick-boxes, so acceptance has to be recordable separately even
-- though both are printed in the same PDF.
INSERT INTO legal_documents
  (doc_type, version, effective_date, locale, title, asset_path, is_current)
VALUES
  ('Terms',   '1.0', DATE '2026-05-22', 'English',
   'MANALINE Terms & Conditions',
   'assets/legal/MANALINE_Terms_and_Privacy_v1.0.pdf', true),
  ('Privacy', '1.0', DATE '2026-05-22', 'English',
   'MANALINE Privacy Policy',
   'assets/legal/MANALINE_Terms_and_Privacy_v1.0.pdf', true);
