-- ============================================================
-- 01-basics.sql · freeCodeCamp "Learn PostgreSQL" · part 1
-- Database: lab
-- Check the whole file runs clean (from the pg-lab folder):
--   psql lab -v ON_ERROR_STOP=1 -f notes/01-basics.sql > /dev/null && echo "runs clean"
-- ============================================================


-- ── 1. psql essentials ───────────────────────────────────────
-- Backslash commands belong to psql (the client). The server never sees them.
--   \l              list databases
--   \c lab          connect to database "lab" (Postgres has no USE; you reconnect)
--   \conninfo       show where I'm connected
--   \dt             list tables
--   \d person       describe one table
--   \i file.sql     run a file (path relative to where psql was started)
--   \ir file.sql    run a file (path relative to the current script)
--   \?              every psql command        \h SELECT   help for one SQL command
--   \q              quit
--
-- Connecting from the shell (psql --help lists every option):
--   psql lab                                  local socket, default port
--   psql -h localhost -p 5432 -U subham lab   over TCP: host, port, user
--   -w  never prompt for a password     -W  force a password prompt


-- ── 2. Databases ─────────────────────────────────────────────
--   CREATE DATABASE lab;
--   DROP DATABASE lab;    -- permanent. Can't drop the one you're connected to: \c subham first


-- ── 3. Tables ────────────────────────────────────────────────
-- v1, my first table, with no constraints. id INT has no default, so inserted rows
-- got id = NULL, and nothing stopped duplicates. Kept for reference, not run.
--
--   CREATE TABLE person (
--       id            INT,
--       first_name    VARCHAR(50),
--       last_name     VARCHAR(50),
--       gender        VARCHAR(7),
--       date_of_birth DATE
--   );
--
-- The real table + 1000 rows come from Mockaroo: data/person.sql.
-- Its first line is DROP TABLE IF EXISTS person; so this file is safe to re-run.
\ir ../data/person.sql


-- ── 4. INSERT ────────────────────────────────────────────────
-- Column list and VALUES line up one-to-one. Text goes in 'single quotes'.
INSERT INTO person (first_name, last_name, email, gender, date_of_birth, country_of_birth)
VALUES ('Jake', 'Jones', 'jake@gmail.com', 'Male', DATE '1988-01-09', 'India');
-- 'Male', not 'MALE': text comparison is case-sensitive, so 'MALE' never matches gender = 'Male'


-- ── 5. SELECT ────────────────────────────────────────────────
SELECT * FROM person;
SELECT first_name, last_name FROM person;


-- ── 6. ORDER BY (ascending by default) ───────────────────────
SELECT * FROM person ORDER BY country_of_birth;
SELECT * FROM person ORDER BY country_of_birth DESC;
SELECT * FROM person ORDER BY id, email;   -- 2nd column only breaks ties; id has none, so email never matters here


-- ── 7. DISTINCT (removes duplicate rows from the result) ─────
SELECT DISTINCT country_of_birth
FROM person
ORDER BY country_of_birth;


-- ── 8. WHERE with AND / OR ───────────────────────────────────
-- AND binds tighter than OR, so these parentheses change the answer
SELECT *
FROM person
WHERE gender = 'Female'
  AND (country_of_birth = 'Poland' OR country_of_birth = 'China');


-- ── 9. Comparison operators (each returns true or false) ─────
SELECT 1 = 2;
SELECT 1 > 2;
SELECT 1 <> 2;    -- "not equal"; != works too


-- ── 10. LIMIT, OFFSET, FETCH ─────────────────────────────────
-- A table has no built-in order. Without ORDER BY, "the first 10" is whatever
-- Postgres happens to read first, and that can change. Always sort before paging.
SELECT * FROM person ORDER BY id LIMIT 10;
SELECT * FROM person ORDER BY id OFFSET 5 LIMIT 5;          -- skip 5, take 5
SELECT * FROM person ORDER BY id FETCH FIRST 5 ROWS ONLY;   -- SQL-standard spelling of LIMIT


-- ── 11. IN (shorthand for several ORs on one column) ─────────
SELECT *
FROM person
WHERE country_of_birth IN ('China', 'Brazil', 'France');
