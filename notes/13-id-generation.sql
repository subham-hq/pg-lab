-- 13-id-generation.sql: sequences, identity columns, extensions, UUIDs
-- Source: Amigoscode PostgreSQL course (freeCodeCamp). The video uses person
--         and car; these notes use employee and laptop.
-- Docs:   https://www.postgresql.org/docs/current/functions-sequence.html
--         https://www.postgresql.org/docs/current/ddl-identity-columns.html
--         https://www.postgresql.org/docs/current/datatype-uuid.html
--         https://www.postgresql.org/docs/current/uuid-ossp.html

-- Reset to a known state: person has BIGSERIAL ids; employee has identity
-- ids, 1 to 5
\ir ../data/person.sql
\ir ../data/employee-laptop.sql


-- SERIAL and sequences ------------------------------------------------------
-- A sequence is a database object that hands out numbers: 1, 2, 3, ...

-- BIGSERIAL isn't a real type. It's shorthand for a BIGINT column, a sequence
-- named <table>_<column>_seq, and a default that calls nextval() on it:
\d person
-- id's default: nextval('person_id_seq'::regclass)

-- An identity column (employee.id) is the modern, standard version of the
-- same idea. It has a sequence too, employee_id_seq. (Beyond, 7 compares them.)
\d employee

-- A sequence can be read like a one-row table:
--   last_value   the last number handed out: 5, one per employee
--   is_called    whether last_value has been handed out yet
--   log_cnt      internal crash-recovery bookkeeping, not a count of calls
SELECT *
FROM employee_id_seq;

-- nextval() hands out the next number. ::regclass turns the name into the
-- sequence itself; nextval('employee_id_seq') does that cast for you.
SELECT nextval('employee_id_seq'::regclass);    -- 6
SELECT nextval('employee_id_seq'::regclass);    -- 7

-- A number handed out is never given back, so 6 and 7 are skipped for good
-- and the next insert gets 8
INSERT INTO employee (first_name, last_name)
VALUES ('Farah', 'Khan')
RETURNING id;                                   -- 8


-- Restarting a sequence -----------------------------------------------------

-- RESTART only moves the counter. It doesn't look at the ids already in the
-- table.
ALTER SEQUENCE employee_id_seq RESTART WITH 1;

-- last_value 1 with is_called false: 1 is the next number out
SELECT *
FROM employee_id_seq;

-- Expected to fail: id 1 is taken
-- INSERT INTO employee (first_name, last_name)
-- VALUES ('Gita', 'Sen');
-- ERROR:  duplicate key value violates unique constraint "employee_pkey"
-- DETAIL:  Key (id)=(1) already exists.

-- The fix: set the sequence to the highest id in use, so the next nextval()
-- returns one more. The same fix applies after loading rows that brought
-- their own ids, which never move the sequence.
SELECT setval('employee_id_seq', (SELECT MAX(id) FROM employee));    -- 8

INSERT INTO employee (first_name, last_name)
VALUES ('Gita', 'Sen')
RETURNING id;                                   -- 9

-- For an identity column the documented form is
--   ALTER TABLE employee ALTER COLUMN id RESTART WITH 1;
-- It moves the same sequence.


-- Extensions ----------------------------------------------------------------
-- An extension is an add-on package of functions, types or operators,
-- installed per database. This lists every extension that ships with your
-- server; installed_version is filled in for the ones installed here.
SELECT *
FROM pg_available_extensions
ORDER BY name;

-- \dx lists only the installed ones
\dx


-- UUIDs ---------------------------------------------------------------------
-- A UUID is a 128-bit value, written as 32 hex digits in five groups. Any
-- machine can generate one with practically no chance of a clash, without
-- asking the database for the next number.

-- uuid-ossp is an extension of UUID functions. The double quotes are needed
-- because the name has a hyphen; IF NOT EXISTS makes the line safe to re-run.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- \df lists the functions in your own schemas: the extension added ten,
-- uuid_generate_v1 to uuid_ns_x500
\df

-- v4 is random: a different value on every call
SELECT uuid_generate_v4();


-- UUIDs as primary keys -----------------------------------------------------
-- The employee/laptop relationship from 10, keyed by UUIDs instead of
-- integers. These replace the tables from data/employee-laptop.sql; the other
-- notes files reload that file, so they're unaffected.
DROP TABLE IF EXISTS employee;
DROP TABLE IF EXISTS laptop;

CREATE TABLE laptop (
    laptop_uid UUID NOT NULL PRIMARY KEY,
    brand      VARCHAR(100) NOT NULL,
    model      VARCHAR(100) NOT NULL,
    price      NUMERIC(10, 2) NOT NULL
);

CREATE TABLE employee (
    employee_uid     UUID NOT NULL PRIMARY KEY,
    first_name       VARCHAR(50) NOT NULL,
    last_name        VARCHAR(50) NOT NULL,
    gender           VARCHAR(10) NOT NULL,
    email            VARCHAR(100),
    date_of_birth    DATE NOT NULL,
    country_of_birth VARCHAR(50) NOT NULL,
    laptop_uid       UUID REFERENCES laptop (laptop_uid),
    UNIQUE (laptop_uid),
    UNIQUE (email)
);

-- Each row's key is generated as it's inserted
INSERT INTO laptop (laptop_uid, brand, model, price)
VALUES (uuid_generate_v4(), 'Apple',  'MacBook Air 13',     1099.00),
       (uuid_generate_v4(), 'Lenovo', 'ThinkPad X1 Carbon', 1549.00);

INSERT INTO employee (employee_uid, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (uuid_generate_v4(), 'Daniel', 'Carter',   'Male', 'daniel.carter@gmail.com',  DATE '1994-05-17', 'Canada'),
       (uuid_generate_v4(), 'Lucas',  'Anderson', 'Male', 'lucas.anderson@gmail.com', DATE '1989-12-09', 'Sweden');

-- Rows with UUIDs are wide. \x on shows one column per line instead.
\x on

SELECT *
FROM employee
ORDER BY email;


-- Assigning a laptop --------------------------------------------------------

-- These keys were copied from an earlier session. uuid_generate_v4() makes
-- new keys every time this file runs, so they match no row: psql prints
-- UPDATE 0, with no error. Read the count.
UPDATE employee
SET laptop_uid = '2ee2462b-4d91-40dd-985a-a4ddae164eb4'
WHERE employee_uid = '00ebd56d-b281-4d3b-aa2b-88b6ea9917a9';

-- Find rows by something that doesn't change instead. email is UNIQUE, and a
-- subquery looks up the laptop's key by its model.
UPDATE employee
SET laptop_uid = (SELECT laptop_uid FROM laptop WHERE model = 'MacBook Air 13')
WHERE email = 'daniel.carter@gmail.com'
RETURNING first_name, laptop_uid;


-- Joining on UUIDs ----------------------------------------------------------
-- The column is called laptop_uid in both tables, so USING (laptop_uid) can
-- replace ON employee.laptop_uid = laptop.laptop_uid. SELECT * then shows
-- laptop_uid once instead of twice.
SELECT *
FROM employee
LEFT JOIN laptop USING (laptop_uid)
ORDER BY email;

\x off


-- Beyond the video ----------------------------------------------------------

-- 1. Random UUIDs need no extension: gen_random_uuid() is built in
--    (Postgres 13+). uuid-ossp only matters for versions 1, 3 and 5.
SELECT gen_random_uuid();

-- 2. Random keys are slow keys. Each v4 key lands at a random spot in the
--    primary-key index, so inserts touch pages all over it: more page splits,
--    more cache misses, more WAL. UUIDv7 starts with a timestamp, so new keys
--    go at the end of the index the way sequence numbers do. Postgres 18 has
--    it built in. Three in a row share their leading digits and come out in
--    order:
SELECT uuidv7()
FROM generate_series(1, 3);

--    The trade-off: anyone holding a v7 key can read when it was made.
SELECT uuid_extract_timestamp(uuidv7());

-- 3. Let the table generate its key: put the function in the column's
--    DEFAULT, leave the column out of the INSERT, and get the key back with
--    RETURNING.
ALTER TABLE laptop ALTER COLUMN laptop_uid SET DEFAULT uuidv7();

INSERT INTO laptop (brand, model, price)
VALUES ('Dell', 'XPS 13', 1299.00)
RETURNING laptop_uid;
--    Integer ids work the same way: RETURNING id, never SELECT MAX(id)
--    afterwards. Another session may have inserted in between.

-- 4. Store UUIDs in the uuid type, not text. As text they're more than twice
--    the size: 16 bytes against 40 (36 characters plus a length header).
SELECT pg_column_size(gen_random_uuid())       AS as_uuid,
       pg_column_size(gen_random_uuid()::text) AS as_text;

--    and the uuid type checks what goes in:
-- Expected to fail: not a UUID
-- SELECT 'not-a-uuid'::uuid;
-- ERROR:  invalid input syntax for type uuid: "not-a-uuid"

-- 5. Integers or UUIDs? UUIDs can be made anywhere without asking the
--    database (in the app, in another service, offline), merge cleanly across
--    databases, and don't reveal how many rows exist or let anyone guess the
--    next id in a URL. They cost space and index speed, and they're hard to
--    read while debugging. A common middle ground: a BIGINT identity key
--    inside the database, plus a UUID column as the id the outside world
--    sees. An unguessable id still isn't access control: check permissions
--    anyway.

-- 6. A number handed out is never given back, not even by ROLLBACK (a failed
--    insert uses one up too). So ids have gaps: never use them to count rows
--    or as gap-free invoice numbers.
DROP TABLE IF EXISTS ticket;

CREATE TABLE ticket (
    id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title TEXT NOT NULL
);

BEGIN;

INSERT INTO ticket (title)
VALUES ('Screen flickers')
RETURNING id;                       -- 1

ROLLBACK;

INSERT INTO ticket (title)
VALUES ('Screen flickers')
RETURNING id;                       -- 2, not 1

-- 7. For new tables, prefer identity columns (Postgres 10+, standard SQL)
--    to BIGSERIAL. GENERATED ALWAYS refuses an id you pick yourself:
-- Expected to fail: the database picks the id
-- INSERT INTO ticket (id, title)
-- VALUES (10, 'Keyboard sticks');
-- ERROR:  cannot insert a non-DEFAULT value into column "id"
-- DETAIL:  Column "id" is an identity column defined as GENERATED ALWAYS.
-- HINT:  Use OVERRIDING SYSTEM VALUE to override.

--    BIGSERIAL accepts a hand-picked id without a word, and the sequence
--    never finds out:
INSERT INTO person (id, first_name, last_name, gender, email, date_of_birth, country_of_birth)
VALUES (1001, 'Ira', 'Sen', 'Female', NULL, DATE '1990-01-01', 'India');

--    Later nextval() reaches that number, and an ordinary insert fails:
-- Expected to fail: the sequence hands out 1001 next
-- INSERT INTO person (first_name, last_name, gender, email, date_of_birth, country_of_birth)
-- VALUES ('Ravi', 'Das', 'Male', NULL, DATE '1991-02-02', 'India');
-- ERROR:  duplicate key value violates unique constraint "person_pkey"
-- DETAIL:  Key (id)=(1001) already exists.

--    Either way, use BIGINT: an INT id runs out at 2,147,483,647.
