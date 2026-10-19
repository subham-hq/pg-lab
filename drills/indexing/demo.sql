-- docker run --name pg18 -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=appdb -p 5432:5432 -d postgres:18

explain analyze
select *
from comments
where user_id = 1;

-- 20ms
-- 5ms

drop index ix_comments_user_id;
drop index ix_comments_issue_id;

create index ix_comments_user_id
on comments (user_id);

explain analyze
select count(*)
from comments
where user_id = 1;

-- 19ms --> 0.7ms

explain analyze
select *
from comments
where issue_id = 1;

-- 18ms --> 0.1ms

drop index ix_comments_issue_id;

create index ix_comments_issue_id
on comments (issue_id);

explain analyze
select count(*)
from comments
where issue_id = 1
  and user_id = 2;

 -- 19ms --> 0.6ms

EXPLAIN ANALYZE
SELECT *
FROM comments
WHERE issue_id = 1
  AND user_id = 2
  AND created_at >= NOW() - INTERVAL '1 month'
ORDER BY created_at DESC;

-- 21ms --> 0.6ms --> 0.02ms

CREATE INDEX ix_comments_issue_id_user_id_created_at
ON comments (issue_id, user_id, created_at);

SELECT
  schemaname,
  relname  AS table_name,
  indexrelname AS index_name,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
  pg_relation_size(indexrelid) AS index_size_bytes
FROM pg_stat_user_indexes
ORDER BY index_size_bytes DESC;