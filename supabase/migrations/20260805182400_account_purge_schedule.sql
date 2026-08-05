-- Nightly, ten minutes after the soft-delete purge (which runs 20:45 UTC =
-- 02:15 IST). Staggered rather than simultaneous so two cascade-heavy jobs do
-- not contend, and late enough that no field agent is mid-collection.
SELECT cron.schedule(
  'purge-due-accounts',
  '55 20 * * *',
  $$SELECT app.purge_due_accounts();$$
);
