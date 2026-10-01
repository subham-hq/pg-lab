-- 07-constraints.sql: primary keys, UNIQUE, CHECK
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/ddl-constraints.html

-- Reset to a known state
\ir ../data/person.sql
\ir ../data/car.sql

-- \d lists a table's columns, indexes and constraints
\d person


-- PRIMARY KEY ---------------------------------------------------------------
-- A primary key is NOT NULL + UNIQUE: every row has one and no two rows share
-- it. Postgres names this one person_pkey and enforces it with a unique index.

-- Expected to fail: id 1 is taken
-- INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
-- VALUES (1, 'Jake', 'Jones', 'Male', 'jake@example.com', DATE '1990-01-10', 'India');
-- ERROR:  duplicate key value violates unique constraint "person_pkey"
-- DETAIL:  Key (id)=(1) already exists.

-- Drop the primary key and the same insert works: now two rows have id 1
ALTER TABLE person DROP CONSTRAINT person_pkey;

INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (1, 'Jake', 'Jones', 'Male', 'jake@example.com', DATE '1990-01-10', 'India');

SELECT id, first_name, last_name, email
FROM person
WHERE id = 1;

-- Expected to fail: the key can't come back while a duplicate exists
-- ALTER TABLE person ADD PRIMARY KEY (id);
-- ERROR:  could not create unique index "person_pkey"
-- DETAIL:  Key (id)=(1) is duplicated.

-- Delete only the extra row (WHERE id = 1 alone would delete both), then put
-- the key back
DELETE FROM person
WHERE id = 1
  AND email = 'jake@example.com';

ALTER TABLE person ADD PRIMARY KEY (id);


-- UNIQUE --------------------------------------------------------------------

-- Look for duplicates before adding the constraint. A row with a blank email
-- here is all the NULLs grouped together. That isn't a real duplicate:
-- UNIQUE lets any number of NULLs through.
SELECT email, COUNT(*)
FROM person
GROUP BY email
HAVING COUNT(*) > 1;

ALTER TABLE person ADD CONSTRAINT unique_email_address UNIQUE (email);

-- Demo rows from here on use ids above 1000, clear of the Mockaroo rows.
-- (Normally you leave id out and let Postgres assign it; 13 covers how.)
INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (1001, 'Jake', 'Jones', 'Male', 'jake@example.com', DATE '1990-01-10', 'India');

-- Expected to fail: that email is taken now
-- INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
-- VALUES (1002, 'Jacob', 'Jones', 'Male', 'jake@example.com', DATE '1991-02-11', 'India');
-- ERROR:  duplicate key value violates unique constraint "unique_email_address"
-- DETAIL:  Key (email)=(jake@example.com) already exists.

-- Two people with no email: allowed, because NULL never equals NULL
INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (1002, 'Ann', 'Lee', 'Female', NULL, DATE '1995-05-05', 'India'),
       (1003, 'Raj', 'Das', 'Male', NULL, DATE '1996-06-06', 'India');

-- A constraint is removed by name
ALTER TABLE person DROP CONSTRAINT unique_email_address;


-- CHECK ---------------------------------------------------------------------
-- A rule every row has to pass. Adding one to a table that already has rows
-- checks all of them first, so look at the data before you constrain it:
SELECT gender, COUNT(*)
FROM person
GROUP BY gender
ORDER BY gender;

-- The video's rule only goes in if every row above is 'Female' or 'Male'.
-- Mockaroo's current Gender type also generates values like 'Non-binary', and
-- on that data the ALTER stops with:
--   ERROR:  check constraint "gender_constraint" of relation "person" is violated by some row
-- ALTER TABLE person ADD CONSTRAINT gender_constraint CHECK (gender = 'Female' OR gender = 'Male');

-- A rule that has to hold for every car: a price can't be negative
ALTER TABLE car ADD CONSTRAINT price_not_negative CHECK (price >= 0);

-- Expected to fail: breaks the rule (psql also prints the failing row)
-- UPDATE car
-- SET price = -1
-- WHERE id = 1;
-- ERROR:  new row for relation "car" violates check constraint "price_not_negative"


-- Beyond the video ----------------------------------------------------------

-- 1. Name constraints yourself (ADD CONSTRAINT name ...). The name is what
--    the error shows, so a clear one tells you, and your application, which
--    rule broke. Unnamed, Postgres picks one: person_pkey, person_email_key,
--    car_price_check.

-- 2. A CHECK only rejects false. NULL counts as unknown, so it gets through.
--    This rule looks like it forces an @ into every email...
ALTER TABLE person ADD CONSTRAINT email_has_at CHECK (email LIKE '%@%');

--    ...but a row with no email goes straight in. Requiring a value is
--    NOT NULL's job, not CHECK's.
INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (1004, 'Sam', 'Roy', 'Male', NULL, DATE '1997-07-07', 'India');

-- 3. Constraints are the last line of defence. If the application asks "is
--    this email free?" and then inserts, two requests can both get "yes" and
--    both insert. Only the database can really enforce UNIQUE; the application
--    turns the constraint error into a friendly message.

-- 4. CHECK is for rules that are always true: a price can't be negative, an
--    end date can't come before its start date. A list of allowed values that
--    may grow (statuses, categories, genders) fits better in its own table
--    with a foreign key (10). Adding a value is then an INSERT, not a schema
--    change.

-- 5. On a big production table, ADD CONSTRAINT scans every row while holding
--    a lock that blocks all reads and writes. The safer two-step: add it
--    NOT VALID (applies to new rows only, nearly instant), then VALIDATE it,
--    which checks the old rows without blocking reads or writes.
ALTER TABLE car ADD CONSTRAINT model_not_blank CHECK (model <> '') NOT VALID;
ALTER TABLE car VALIDATE CONSTRAINT model_not_blank;

-- 6. Postgres 15+ can make UNIQUE treat NULLs as equal:
--      UNIQUE NULLS NOT DISTINCT (email)
--    Then at most one row may have a NULL email.

-- Everything this file added to person
\d person
