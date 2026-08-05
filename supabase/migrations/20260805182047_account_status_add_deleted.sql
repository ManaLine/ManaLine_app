-- Terminal state for the 90-day purge. Its own migration because ALTER TYPE
-- ... ADD VALUE cannot be used by DML in the same transaction that adds it.
ALTER TYPE account_status_enum ADD VALUE IF NOT EXISTS 'Deleted';
