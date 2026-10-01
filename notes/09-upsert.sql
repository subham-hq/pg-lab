-- 09-upsert.sql: ON CONFLICT DO NOTHING / DO UPDATE
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/sql-insert.html  (ON CONFLICT Clause)

-- Reset to a known state
\ir ../data/person.sql


-- ON CONFLICT DO NOTHING ----------------------------------------------------

-- Expected to fail: id 2 already exists
-- INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
-- VALUES (2, 'Russ', 'Ruddoch', 'Male', 'rruddoch7@hhs.gov', DATE '1952-09-25', 'Norway');
-- ERROR:  duplicate key value violates unique constraint "person_pkey"
-- DETAIL:  Key (id)=(2) already exists.

-- Same insert, but skip the row instead of failing. psql prints INSERT 0 0;
-- the second number is the row count, so nothing went in.
INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (2, 'Russ', 'Ruddoch', 'Male', 'rruddoch7@hhs.gov', DATE '1952-09-25', 'Norway')
ON CONFLICT (id) DO NOTHING;

-- The column in ON CONFLICT (...) needs a UNIQUE or PRIMARY KEY constraint.
-- Expected to fail: email has no unique constraint on this freshly loaded table
-- INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
-- VALUES (2, 'Russ', 'Ruddoch', 'Male', 'rruddoch7@hhs.gov', DATE '1952-09-25', 'Norway')
-- ON CONFLICT (email) DO NOTHING;
-- ERROR:  there is no unique or exclusion constraint matching the ON CONFLICT specification


-- ON CONFLICT DO UPDATE (upsert) --------------------------------------------

-- On a conflict, update the existing row instead. EXCLUDED is the row you
-- tried to insert, and only the columns listed in SET change. (A new email
-- here, so the change is visible.)
INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (2, 'Russ', 'Ruddoch', 'Male', 'russ.ruddoch@gmail.com', DATE '1952-09-25', 'Norway')
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email;

SELECT id, first_name, last_name, email
FROM person
WHERE id = 2;                       -- the new email; every other column unchanged

-- Several columns at once
INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (2, 'Russell', 'Ruddoch', 'Male', 'russell.ruddoch@gmail.com', DATE '1952-09-25', 'Norway')
ON CONFLICT (id) DO UPDATE
SET email      = EXCLUDED.email,
    last_name  = EXCLUDED.last_name,
    first_name = EXCLUDED.first_name;

SELECT id, first_name, last_name, email
FROM person
WHERE id = 2;


-- Beyond the video ----------------------------------------------------------

-- 1. Upsert on what you actually know. Keying on id only works if you already
--    know the row's id. Usually you know something real, like an email, and
--    the database owns the id. Give that column a unique constraint:
ALTER TABLE person ADD CONSTRAINT person_email_key UNIQUE (email);

--    (Demo ids start above 1000, clear of the Mockaroo rows.) RETURNING shows
--    id 2: the email matched row 2, so row 2 was updated and the 1001 you
--    passed was never used.
INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (1001, 'Russ', 'Ruddoch', 'Male', 'russell.ruddoch@gmail.com', DATE '1952-09-25', 'Norway')
ON CONFLICT (email) DO UPDATE
SET first_name = EXCLUDED.first_name
RETURNING id, first_name, email;

-- 2. Why not "SELECT first, INSERT if nothing came back"? Two requests can run
--    that SELECT at the same moment, both see nothing, and both INSERT.
--    ON CONFLICT checks and writes in one atomic step, so that race can't happen.

-- 3. DO UPDATE ... WHERE skips updates that change nothing: fewer writes, and
--    RETURNING tells you whether anything happened. first_name is already
--    'Russ', so this prints INSERT 0 0 and returns no rows:
INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (1001, 'Russ', 'Ruddoch', 'Male', 'russell.ruddoch@gmail.com', DATE '1952-09-25', 'Norway')
ON CONFLICT (email) DO UPDATE
SET first_name = EXCLUDED.first_name
WHERE person.first_name IS DISTINCT FROM EXCLUDED.first_name
RETURNING id, first_name;

-- 4. One statement can't upsert the same key twice. It's common when loading
--    a file that repeats rows; de-duplicate the input first.
-- Expected to fail: both rows want the same email
-- INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
-- VALUES (1002, 'Ann', 'Lee', 'Female', 'ann@example.com', DATE '1995-05-05', 'India'),
--        (1003, 'Ann', 'Lee', 'Female', 'ann@example.com', DATE '1995-05-05', 'India')
-- ON CONFLICT (email) DO UPDATE
-- SET first_name = EXCLUDED.first_name;
-- ERROR:  ON CONFLICT DO UPDATE command cannot affect row a second time
-- HINT:  Ensure that no rows proposed for insertion within the same command have duplicate constrained values.

-- 5. When the id comes from a sequence, every attempt uses up a number, even
--    one that ends in DO NOTHING or an update. Gaps in ids are normal (13).

-- 6. Postgres 15+ also has MERGE, the SQL-standard way to insert, update or
--    delete in one statement. For a plain upsert, ON CONFLICT is simpler, and
--    safer under load: if another session inserts the same key at the same
--    moment, MERGE can still fail with a unique violation.
