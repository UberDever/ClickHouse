-- Tags: no-random-merge-tree-settings

-- Test that TTLDeleteMerge respects max_parts_to_merge_at_once setting.
-- When merging parts with expired TTL, the merge should not include more than
-- max_parts_to_merge_at_once parts in intermediate merges.

DROP TABLE IF EXISTS ttl_delete_max_parts;

CREATE TABLE ttl_delete_max_parts
(
    key UInt64,
    d DateTime DEFAULT '2020-01-01 00:00:00'
)
ENGINE = MergeTree()
ORDER BY key
TTL d + INTERVAL 1 SECOND DELETE
SETTINGS
    max_parts_to_merge_at_once = 3,
    merge_with_ttl_timeout = 0,
    min_parts_to_merge_at_once = 100; -- Disable regular merges so we only test TTL merges

SYSTEM STOP MERGES ttl_delete_max_parts;

-- Insert parts with both expired and non-expired rows so it triggers TTLDeleteMerge instead of TTLDropMerge
INSERT INTO ttl_delete_max_parts (key, d) VALUES (1, '2020-01-01 00:00:00'), (2, '2030-01-01 00:00:00');
INSERT INTO ttl_delete_max_parts (key, d) VALUES (3, '2020-01-01 00:00:00'), (4, '2030-01-01 00:00:00');
INSERT INTO ttl_delete_max_parts (key, d) VALUES (5, '2020-01-01 00:00:00'), (6, '2030-01-01 00:00:00');
INSERT INTO ttl_delete_max_parts (key, d) VALUES (7, '2020-01-01 00:00:00'), (8, '2030-01-01 00:00:00');
INSERT INTO ttl_delete_max_parts (key, d) VALUES (9, '2020-01-01 00:00:00'), (10, '2030-01-01 00:00:00');
INSERT INTO ttl_delete_max_parts (key, d) VALUES (11, '2020-01-01 00:00:00'), (12, '2030-01-01 00:00:00');
INSERT INTO ttl_delete_max_parts (key, d) VALUES (13, '2020-01-01 00:00:00'), (14, '2030-01-01 00:00:00');
INSERT INTO ttl_delete_max_parts (key, d) VALUES (15, '2020-01-01 00:00:00'), (16, '2030-01-01 00:00:00');
INSERT INTO ttl_delete_max_parts (key, d) VALUES (17, '2020-01-01 00:00:00'), (18, '2030-01-01 00:00:00');
INSERT INTO ttl_delete_max_parts (key, d) VALUES (19, '2020-01-01 00:00:00'), (20, '2030-01-01 00:00:00');

SYSTEM START MERGES ttl_delete_max_parts;

-- Run OPTIMIZE TABLE multiple times to force TTL merges.
-- Since min_parts_to_merge_at_once = 100, regular merges are disabled.
-- TTL merges will only happen once per part (since expired rows are deleted).
OPTIMIZE TABLE ttl_delete_max_parts;
OPTIMIZE TABLE ttl_delete_max_parts;
OPTIMIZE TABLE ttl_delete_max_parts;
OPTIMIZE TABLE ttl_delete_max_parts;
OPTIMIZE TABLE ttl_delete_max_parts;
OPTIMIZE TABLE ttl_delete_max_parts;
OPTIMIZE TABLE ttl_delete_max_parts;
OPTIMIZE TABLE ttl_delete_max_parts;
OPTIMIZE TABLE ttl_delete_max_parts;
OPTIMIZE TABLE ttl_delete_max_parts;

SYSTEM FLUSH LOGS;

-- Check that merged parts respect max_parts_to_merge_at_once = 3
-- We also check that count() > 0 to ensure TTLDeleteMerge actually happened
SELECT
    if(
        count() > 0 AND max(length(merged_from)) <= 3,
        'OK - all merged parts respect max_parts_to_merge_at_once limit',
        'FAIL - some merged parts exceed max_parts_to_merge_at_once limit or no merges happened'
    ) AS result
FROM system.part_log
WHERE
    database = currentDatabase()
    AND table = 'ttl_delete_max_parts'
    AND event_type = 'MergeParts'
    AND merge_reason = 'TTLDeleteMerge';

DROP TABLE ttl_delete_max_parts;
