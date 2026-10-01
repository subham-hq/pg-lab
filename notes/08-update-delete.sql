-- 08-update-delete.sql: UPDATE and DELETE
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/dml.html

-- Reset to a known state
\ir ../data/person.sql


-- DELETE --------------------------------------------------------------------

-- Without WHERE, every row goes. Inside a transaction you can look at the
-- result and undo it with ROLLBACK.
BEGIN;

DELETE FROM person;                 -- psql prints DELETE and how many rows went

SELECT COUNT(*)
FROM person;                        -- 0

ROLLBACK;

SELECT COUNT(*)
FROM person;                        -- every row is back

-- With WHERE, only the matching rows go
DELETE FROM person
WHERE id = 1000;                    -- DELETE 1


-- UPDATE --------------------------------------------------------------------

UPDATE person
SET email = 'omar@gmail.com'
WHERE id = 1;

-- These two find the row by email. Email has no UNIQUE constraint on this
-- freshly loaded table, so anyone else with omar@gmail.com would change too.
UPDATE person
SET first_name = 'Omar'
WHERE email = 'omar@gmail.com';

UPDATE person
SET last_name = 'Smith'
WHERE email = 'omar@gmail.com';

-- Better: one statement, matched on the primary key, which hits at most one row
UPDATE person
SET first_name = 'Omar',
    last_name  = 'Smith',
    email      = 'omar@gmail.com'
WHERE id = 1;


-- Beyond the video ----------------------------------------------------------

-- 1. Before a risky UPDATE or DELETE, run its WHERE as a SELECT and check the
--    count. Afterwards, read the count psql prints (UPDATE 1, DELETE 1). If it
--    says 1000 when you expected 1 and you're inside BEGIN, ROLLBACK.
SELECT COUNT(*)
FROM person
WHERE country_of_birth = 'Norway';

-- 2. RETURNING shows the rows a statement changed, in the same round trip:
UPDATE person
SET email = NULL
WHERE id = 2
RETURNING id, first_name, email;

DELETE FROM person
WHERE id = 3
RETURNING *;

-- 3. SET can use the row's current values, so there's no read-then-write:
UPDATE person
SET first_name = UPPER(first_name)
WHERE id = 4
RETURNING id, first_name;
--    The same shape raises prices: SET price = price * 1.05

-- 4. TRUNCATE empties a table far faster than DELETE: it throws away the data
--    files instead of removing rows one at a time. But it can't take a WHERE,
--    skips row-level triggers, and blocks every other session's reads and
--    writes until the transaction ends. In Postgres it can be rolled back:
BEGIN;

TRUNCATE person;

SELECT COUNT(*)
FROM person;                        -- 0

ROLLBACK;

-- 5. Neither UPDATE nor DELETE frees space right away. Postgres keeps old row
--    versions so other transactions can still read them (MVCC): an UPDATE
--    writes a new version of the row, and the old one stays until VACUUM
--    removes it. More on this with transactions and isolation.
