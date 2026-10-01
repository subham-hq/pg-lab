-- 02-filtering.sql: BETWEEN, LIKE / ILIKE
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/functions-comparison.html
--         https://www.postgresql.org/docs/current/functions-matching.html

-- Reset to a known state
\ir ../data/person.sql


-- BETWEEN -------------------------------------------------------------------

-- Inclusive at both ends: the same as >= start AND <= end.
-- Someone born on 2015-01-01 is in the result.
SELECT *
FROM person
WHERE date_of_birth BETWEEN DATE '2000-01-01' AND DATE '2015-01-01'
ORDER BY date_of_birth;


-- LIKE and ILIKE ------------------------------------------------------------
-- Two wildcards:
--   %   any run of characters, including none
--   _   exactly one character
-- Everything else is literal, the dot included.

-- No wildcard, so this means email = '@.com': no rows
SELECT *
FROM person
WHERE email LIKE '@.com';

-- Ends with @gmail.com
SELECT *
FROM person
WHERE email LIKE '%@gmail.com';

-- Contains "google." anywhere
SELECT *
FROM person
WHERE email LIKE '%google.%';

-- Ends with "google." plus exactly two characters: google.de, google.ca.
-- google.co.jp has five after the dot, so it's left out.
SELECT *
FROM person
WHERE email LIKE '%google.__';

-- LIKE is case-sensitive: 'P%' finds Peru, Poland, Portugal...; 'p%' finds nothing
SELECT *
FROM person
WHERE country_of_birth LIKE 'P%';

-- ILIKE ignores case, so 'p%' finds the same countries
SELECT *
FROM person
WHERE country_of_birth ILIKE 'p%';


-- Beyond the video ----------------------------------------------------------

-- 1. BETWEEN and timestamps. A DATE bound means midnight, so anything later
--    on the end date falls outside the range:
SELECT TIMESTAMP '2015-01-01 09:30' BETWEEN DATE '2000-01-01' AND DATE '2015-01-01';  -- false

--    The habit that avoids it: half-open ranges, start <= x < end. This reads
--    as "born 2000 through 2014", works the same for DATE and TIMESTAMP, and
--    back-to-back ranges (one per month, say) never overlap or leave a gap.
SELECT *
FROM person
WHERE date_of_birth >= DATE '2000-01-01'
  AND date_of_birth <  DATE '2015-01-01'
ORDER BY date_of_birth;

-- 2. NOT LIKE leaves out NULLs as well. For a NULL email, LIKE and NOT LIKE
--    both give NULL (unknown), and WHERE drops unknown rows. So the gmail and
--    not-gmail counts don't add up to the total; the NULL count is the gap.
--    05-nulls explains why.
SELECT COUNT(*)
FROM person;

SELECT COUNT(*)
FROM person
WHERE email LIKE '%@gmail.com';

SELECT COUNT(*)
FROM person
WHERE email NOT LIKE '%@gmail.com';

SELECT COUNT(*)
FROM person
WHERE email IS NULL;

-- 3. To match a real % or _, put a backslash in front of it:
SELECT 'first_name' LIKE '%\_%';    -- true: contains an underscore
SELECT 'firstname' LIKE '%\_%';     -- false
SELECT 'firstname' LIKE '%_%';      -- true: a bare _ matches any one character

-- 4. Speed. A normal B-tree index can't help a pattern that starts with %
--    ('%@gmail.com'), so Postgres reads every row. A fixed prefix ('P%') can
--    use an index built with text_pattern_ops, and the pg_trgm extension can
--    index '%anything%' searches. This comes back in the indexing drill.

-- 5. ILIKE isn't standard SQL. LOWER(column) LIKE 'p%' works in any database.
--    For harder patterns, Postgres has regular expressions: ~ is
--    case-sensitive, ~* ignores case.
SELECT *
FROM person
WHERE country_of_birth ~* '^p';     -- same rows as ILIKE 'p%'
