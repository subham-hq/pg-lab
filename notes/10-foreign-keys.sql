-- 10-foreign-keys.sql: foreign keys and relationships
-- Source: Amigoscode PostgreSQL course (freeCodeCamp). The video uses person
--         and car; these notes use employee and laptop.
-- Docs:   https://www.postgresql.org/docs/current/ddl-constraints.html  (Foreign Keys)

-- Reset to a known state: 5 employees, 4 laptops (see the data file)
\ir ../data/employee-laptop.sql


-- The relationship ----------------------------------------------------------
-- From data/employee-laptop.sql:
--     laptop_id BIGINT REFERENCES laptop (id),
--     UNIQUE (laptop_id)
-- REFERENCES   every non-NULL laptop_id must match an existing laptop.id
-- UNIQUE       no laptop belongs to two employees, so it's one-to-one
-- NULL         allowed: an employee with no laptop. If every employee must
--              have one, add NOT NULL.
-- Both sides must be the same type: laptop.id is BIGINT, so laptop_id is too.
\d employee


-- Assigning a laptop --------------------------------------------------------

-- Setting the foreign key column links the two rows.
-- Chloe (id 3) has no laptop, and laptop 4 is free.
UPDATE employee
SET laptop_id = 4
WHERE id = 3;

-- Expected to fail: there's no laptop 999
-- UPDATE employee
-- SET laptop_id = 999
-- WHERE id = 5;
-- ERROR:  insert or update on table "employee" violates foreign key constraint "employee_laptop_id_fkey"
-- DETAIL:  Key (laptop_id)=(999) is not present in table "laptop".

-- Expected to fail: laptop 2 already belongs to employee 1
-- UPDATE employee
-- SET laptop_id = 2
-- WHERE id = 5;
-- ERROR:  duplicate key value violates unique constraint "employee_laptop_id_key"
-- DETAIL:  Key (laptop_id)=(2) already exists.


-- Deleting a laptop that's in use -------------------------------------------

-- Expected to fail: employee 1 still has laptop 2
-- DELETE FROM laptop
-- WHERE id = 2;
-- ERROR:  update or delete on table "laptop" violates foreign key constraint "employee_laptop_id_fkey" on table "employee"
-- DETAIL:  Key (id)=(2) is still referenced from table "employee".

-- Take the laptop back first, then delete it. Both in one transaction, so no
-- other session ever sees the half-done state.
BEGIN;

UPDATE employee
SET laptop_id = NULL
WHERE laptop_id = 2;

DELETE FROM laptop
WHERE id = 2;

COMMIT;

-- Expected to fail: a referenced table can't be dropped either
-- DROP TABLE laptop;
-- ERROR:  cannot drop table laptop because other objects depend on it
-- DETAIL:  constraint employee_laptop_id_fkey on table employee depends on table laptop
-- HINT:  Use DROP ... CASCADE to drop the dependent objects too.
--    That's why data/employee-laptop.sql drops employee before laptop.
--    CASCADE would "fix" it by quietly dropping the foreign key itself.


-- Beyond the video ----------------------------------------------------------

-- 1. ON DELETE decides what happens to an employee when their laptop is deleted:
--      NO ACTION (default), RESTRICT    refuse, as above
--      SET NULL                         keep the employee, set laptop_id to NULL
--      CASCADE                          delete the employee too
--    CASCADE suits rows that are part of their parent: delete an order and
--    its order lines go with it. For a laptop, SET NULL fits. Changing it
--    means replacing the constraint:
ALTER TABLE employee
    DROP CONSTRAINT employee_laptop_id_fkey,
    ADD CONSTRAINT employee_laptop_id_fkey
        FOREIGN KEY (laptop_id) REFERENCES laptop (id) ON DELETE SET NULL;

DELETE FROM laptop
WHERE id = 1;                          -- Ben's laptop

SELECT id, first_name, laptop_id
FROM employee
ORDER BY id;                           -- Ben's laptop_id is NULL now
--    RESTRICT and NO ACTION differ only in timing: NO ACTION's check can be
--    postponed to the end of the transaction, RESTRICT's can't.

-- 2. Postgres indexes the referenced column (laptop.id is a primary key), but
--    not the referencing one. Here UNIQUE (laptop_id) creates an index as a
--    side effect. A one-to-many relationship has no UNIQUE, so add one yourself:
--        CREATE INDEX ON employee (laptop_id);
--    Without it, every DELETE on laptop scans all of employee looking for
--    references, and joins on laptop_id slow down as the table grows.

-- 3. The three relationship shapes:
--      one-to-one     foreign key + UNIQUE    (employee -> laptop, here)
--      one-to-many    foreign key alone       (many employees -> one team)
--      many-to-many   a junction table        (employees <-> projects)
--    A junction table holds two foreign keys, and the pair is its primary key:
--        CREATE TABLE employee_project (
--            employee_id BIGINT REFERENCES employee (id),
--            project_id  BIGINT REFERENCES project (id),
--            PRIMARY KEY (employee_id, project_id)
--        );
