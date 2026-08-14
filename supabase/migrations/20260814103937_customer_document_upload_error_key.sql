-- AG-004's document upload needed a failure message of its own. The nearest
-- existing key was 'could_not_read' ("Could Not Read"), which describes the
-- wrong half of the operation — the file read fine, the upload is what failed,
-- usually because can_upload_documents is off for that Agent.
insert into ui_translations (translation_key, english, telugu) values
  ('could_not_upload_document_note',
   'Could not upload the document: {error}',
   'పత్రాన్ని అప్‌లోడ్ చేయలేకపోయాము: {error}')
on conflict (translation_key) do nothing;
