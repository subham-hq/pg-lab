-- 05-nulls.sql: COALESCE, NULLIF
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/functions-conditional.html

-- Reset to a known state
\ir ../data/person.sql

-- psql shows NULL as a blank. Make it visible (Beyond, 7).
\pset null '(null)'


-- COALESCE ------------------------------------------------------------------

-- Returns its first argument that isn't NULL
SELECT COALESCE(1);                     -- 1
SELECT COALESCE(NULL, NULL, 1, 10);     -- 1

-- A default for people with no email. Real emails pass through unchanged.
SELECT first_name, COALESCE(email, 'Email not provided') AS email
FROM person
ORDER BY id
LIMIT 20;


-- NULLIF --------------------------------------------------------------------

-- NULLIF(a, b) returns NULL if a = b, otherwise a
SELECT NULLIF(10, 19);     -- 10
SELECT NULLIF(0, 0);       -- NULL

-- Expected to fail: no dividing by zero
-- SELECT 10 / 0;
-- ERROR:  division by zero

-- Turn the 0 into NULL first. Anything divided by NULL is NULL, so no error.
SELECT 10 / NULLIF(0, 0);                  -- NULL
SELECT COALESCE(10 / NULLIF(0, 0), 0);     -- 0


-- Beyond the video ----------------------------------------------------------

-- 1. NULL means "unknown". Compare anything with it and the answer is unknown
--    too (NULL), never true or false. IS NULL is the test that works.
SELECT NULL = NULL;      -- NULL
SELECT NULL <> 1;        -- NULL
SELECT NULL IS NULL;     -- true

--    WHERE keeps a row only when its condition is true, so = NULL finds nobody:
SELECT COUNT(*)
FROM person
WHERE email = NULL;      -- 0

SELECT COUNT(*)
FROM person
WHERE email IS NULL;

-- 2. IS DISTINCT FROM is a NULL-safe comparison: two NULLs count as the same.
SELECT NULL IS DISTINCT FROM NULL;     -- false
SELECT 1 IS DISTINCT FROM NULL;        -- true
--    Useful for "did this value change?", where NULL -> 'x' has to count.

-- 3. NOT IN with a NULL in the list never returns a row. 3 NOT IN (1, NULL)
--    means 3 <> 1 AND 3 <> NULL: true AND unknown, which is unknown.
SELECT 'kept' WHERE 3 NOT IN (1, 2);        -- one row
SELECT 'kept' WHERE 3 NOT IN (1, NULL);     -- no rows
--    NOT IN (SELECT column ...) does the same if that column holds a NULL.
--    NOT EXISTS doesn't have this trap.

-- 4. COALESCE's arguments must share one type. A text default for a number fails:
-- Expected to fail: 'N/A' isn't a number
-- SELECT COALESCE(NULL::numeric, 'N/A');
-- ERROR:  invalid input syntax for type numeric: "N/A"
--    Convert first: COALESCE(price::text, 'N/A').

-- 5. ORDER BY treats NULL as larger than every value: last when ascending,
--    first when descending. NULLS FIRST / NULLS LAST overrides that.
SELECT first_name, email
FROM person
ORDER BY email NULLS FIRST, id
LIMIT 5;

-- 6. NULLIF also cleans up "empty" values. NULLIF(TRIM(email), '') turns a
--    blank or all-spaces email into a real NULL; handy when importing data.
SELECT NULLIF(TRIM('   '), '');     -- NULL

-- 7. Put \pset null '(null)' in ~/.psqlrc and every psql session shows NULLs.
