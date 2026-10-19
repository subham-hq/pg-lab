-- Seed script for PostgreSQL
-- Creates: 100 users, 10,000 issues, 1,000,000 comments (1% archived)

-- Optional: speed-ups for seeding (session-local)
-- SET synchronous_commit = off;
-- SET work_mem = '256MB';

BEGIN;

-- 1) Tables (run this part only if you don't already have them)
CREATE TABLE IF NOT EXISTS users (
  id          serial PRIMARY KEY,
  handle      text        NOT NULL UNIQUE,
  created_at  timestamptz NOT NULL DEFAULT now()
);


CREATE TABLE IF NOT EXISTS issues (
  id          serial PRIMARY KEY,
  user_id     int      NOT NULL REFERENCES users(id),
  status      text        NOT NULL CHECK (status IN ('open', 'closed')),
  priority    int         NOT NULL CHECK (priority BETWEEN 1 AND 5),
  title       text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS comments (
  id          serial PRIMARY KEY,
  issue_id    int      NOT NULL REFERENCES issues(id),
  user_id     int      NOT NULL REFERENCES users(id),
  body        text        NOT NULL,
  archived    boolean     NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- 2) Clear existing data (keeps IDs contiguous so random ranges work)
TRUNCATE TABLE comments, issues, users RESTART IDENTITY;

-- 3) Create 100 random users
INSERT INTO users (handle, created_at)
SELECT
  format('user_%s_%s', gs, substr(md5(random()::text), 1, 6)) AS handle,
  now() - (random() * interval '365 days')                    AS created_at
FROM generate_series(1, 100) AS gs;

-- 4) Create 10,000 random issues (random creator, random open/closed)
INSERT INTO issues (user_id, status, priority, title, created_at, updated_at)
SELECT
  (1 + floor(random() * 100))::bigint                                  AS user_id,
  CASE WHEN random() < 0.65 THEN 'open' ELSE 'closed' END              AS status,
  (1 + floor(random() * 5))::int                                       AS priority,
  format('Issue #%s - %s', gs, substr(md5(random()::text), 1, 10))      AS title,
  -- spread issues over the last year
  (now() - (random() * interval '365 days'))                           AS created_at,
  -- updated_at some time after created_at (up to 30 days later)
  (now() - (random() * interval '365 days'))
    + (random() * interval '30 days')                                  AS updated_at
FROM generate_series(1, 10000) AS gs;

-- 5) Create 1,000,000 random comments (random issue_id, user_id; 1% archived)
INSERT INTO comments (issue_id, user_id, body, archived, created_at)
SELECT
  (1 + floor(random() * 10000))::bigint                                AS issue_id,
  (1 + floor(random() * 100))::bigint                                  AS user_id,
  -- short-ish random-ish body
  format('Comment %s: %s', gs, substr(md5(random()::text), 1, 32))      AS body,
  (random() < 0.01)                                                    AS archived,
  -- distribute comments across the last year (so "last month" queries have data)
  (now() - (random() * interval '365 days'))                           AS created_at
FROM generate_series(1, 1000000) AS gs;

COMMIT;

-- Optional indexes for the query patterns you listed (recommended for your demo)
-- CREATE INDEX IF NOT EXISTS ix_comments_user_created
--   ON comments (user_id, created_at DESC, id DESC);
--
-- CREATE INDEX IF NOT EXISTS ix_comments_issue_created
--   ON comments (issue_id, created_at ASC, id ASC);
--
-- CREATE INDEX IF NOT EXISTS ix_comments_issue_user_created
--   ON comments (issue_id, user_id, created_at DESC, id DESC);
