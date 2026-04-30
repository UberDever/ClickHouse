-- Tags: no-random-merge-tree-settings

-- Test that TTLDropMerge does not read any rows when all data is expired.
-- When TTL removes entire parts (TTLDropMerge), the merge should not read any data
-- because the entire part is dropped without reading.

DROP TABLE IF EXISTS ttl_drop_no_read;

SET max_threads = 1, max_block_size = 1, min_insert_block_size_rows = 1;

CREATE TABLE ttl_drop_no_read
(
    key UInt64,
    d DateTime DEFAULT '2020-01-01 00:00:00'
)
ENGINE = MergeTree()
ORDER BY key
TTL d + INTERVAL 1 SECOND
SETTINGS
    remove_empty_parts = 0,
    merge_with_ttl_timeout = 0,
    -- currently, we rely on the fact that TTLDrop is prioritized over TTLDelete
    -- to force this we could add ttl_only_drop_parts = 1
    max_number_of_merges_with_ttl_in_pool = 0;

SYSTEM STOP MERGES ttl_drop_no_read;

-- Insert data with a past timestamp so all rows are expired
INSERT INTO ttl_drop_no_read (key, d) SELECT number, '2020-01-01 00:00:00' FROM numbers(100);
INSERT INTO ttl_drop_no_read (key, d) SELECT number + 100, '2020-01-01 00:00:00' FROM numbers(100);
INSERT INTO ttl_drop_no_read (key, d) SELECT number + 200, '2020-01-01 00:00:00' FROM numbers(100);

SYSTEM START MERGES ttl_drop_no_read;

OPTIMIZE TABLE ttl_drop_no_read FINAL;

SYSTEM FLUSH LOGS;

-- Check that TTLDropMerge did not read any bytes
SELECT
    '-- Checking that TTLDropMerge did not read any bytes' AS message,
    if(
        max(read_bytes) = 0,
        'OK - no bytes read during TTLDropMerge',
        'FAIL: Some bytes were read during TTLDropMerge'
    ) AS result
FROM system.part_log
WHERE
    database = currentDatabase()
    AND table = 'ttl_drop_no_read'
    AND event_type = 'MergeParts'
    AND merge_reason = 'TTLDropMerge';

DROP TABLE ttl_drop_no_read;
