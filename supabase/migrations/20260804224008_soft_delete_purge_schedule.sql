CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Nightly at 02:15 IST. pg_cron schedules in UTC, so 20:45 UTC.
SELECT cron.schedule(
  'purge-expired-soft-deletes',
  '45 20 * * *',
  $cron$SELECT app.purge_expired_deletes(30);$cron$
);
