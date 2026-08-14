-- customer_documents.file_url had nowhere to point.
--
-- The table's policies (agent covering the customer with can_upload_documents,
-- Owner of the business, the customer themselves) have existed since the table
-- did, but no bucket was ever created, so AG-004's Upload Document action wrote
-- the literal string 'stub-file-url' into file_url. Nothing failed; the row
-- just described a file that did not exist. Zero such rows exist yet.
--
-- member-documents (0037) is person-scoped and gated on
-- app.owner_owns_member_folder, so an Agent cannot write to it. These are
-- customer-scoped and Agents are the ones in the field holding the phone, so
-- this bucket mirrors the TABLE's policies rather than reusing that one.
--
-- Path convention: '<customer_id>/<document-type-slug>-<epoch>.jpg'.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('customer-documents', 'customer-documents', false, 1048576, ARRAY['image/jpeg'])
ON CONFLICT (id) DO NOTHING;

-- The folder name is untrusted input from the client, so it is matched against
-- the uuid shape BEFORE casting. A bare ::uuid on a non-uuid folder raises
-- 22P02 inside policy evaluation, which surfaces as an opaque failure on every
-- row rather than a clean permission denial.
CREATE OR REPLACE FUNCTION app.customer_id_from_object_name(p_name TEXT)
RETURNS UUID
LANGUAGE SQL
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN (storage.foldername(p_name))[1] ~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    THEN ((storage.foldername(p_name))[1])::UUID
  END;
$$;

CREATE POLICY customer_documents_bucket_agent_write ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'customer-documents'
    AND app.agent_covers_customer(app.customer_id_from_object_name(name))
    AND app.agent_permission(
          app.business_id_for_customer(app.customer_id_from_object_name(name)),
          'can_upload_documents')
  );

CREATE POLICY customer_documents_bucket_agent_read ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'customer-documents'
    AND app.agent_covers_customer(app.customer_id_from_object_name(name))
    AND app.agent_permission(
          app.business_id_for_customer(app.customer_id_from_object_name(name)),
          'can_view_customers')
  );

CREATE POLICY customer_documents_bucket_owner_all ON storage.objects
  FOR ALL
  USING (
    bucket_id = 'customer-documents'
    AND app.is_owner(app.business_id_for_customer(app.customer_id_from_object_name(name)))
  )
  WITH CHECK (
    bucket_id = 'customer-documents'
    AND app.is_owner(app.business_id_for_customer(app.customer_id_from_object_name(name)))
  );

CREATE POLICY customer_documents_bucket_self_read ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'customer-documents'
    AND app.is_own_customer_row(app.customer_id_from_object_name(name))
  );
