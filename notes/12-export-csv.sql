-- 12-export-csv.sql: exporting query results to CSV, and loading them back
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/app-psql.html  (\copy)
--         https://www.postgresql.org/docs/current/sql-copy.html

-- Reset to a known state
\ir ../data/employee-laptop.sql

-- Exported files go to /tmp, never into the repo.


-- Export to CSV -------------------------------------------------------------

-- The query to export
SELECT *
FROM employee
LEFT JOIN laptop ON employee.laptop_id = laptop.id
ORDER BY employee.id;

-- The video's version. \copy is a psql command, so it has to fit on one line.
-- CSV already means comma-separated, so DELIMITER ',' is optional. With no
-- ORDER BY, the rows land in the file in no particular order.
\copy (SELECT * FROM employee LEFT JOIN laptop ON employee.laptop_id = laptop.id) TO '/tmp/pg-lab-results.csv' DELIMITER ',' CSV HEADER;

-- Cleaner: a temporary view keeps the \copy line short, naming the columns
-- avoids a header with two columns called id, and ORDER BY fixes the row order.
CREATE TEMP VIEW employee_laptop AS
SELECT e.id AS employee_id, e.first_name, e.last_name, l.brand, l.model
FROM employee AS e
LEFT JOIN laptop AS l ON l.id = e.laptop_id;

\copy (SELECT * FROM employee_laptop ORDER BY employee_id) TO '/tmp/pg-lab-employee-laptop.csv' WITH (FORMAT csv, HEADER)


-- Beyond the video ----------------------------------------------------------

-- 1. \copy vs COPY. With \copy, psql asks the server for the rows and writes
--    the file on YOUR machine. COPY ... TO '/path' (no backslash) is plain
--    SQL: the server writes the file on ITS own disk, so it needs superuser or
--    the pg_write_server_files role. On your laptop they're the same machine;
--    on a hosted database (RDS, Railway, ...) only \copy works.

-- 2. The same command loads a CSV into a table, the direction you'll use most.
--    COPY is the fastest way to bulk-load data, far faster than thousands of
--    single-row INSERTs.
CREATE TEMP TABLE employee_laptop_import (
    employee_id BIGINT,
    first_name  TEXT,
    last_name   TEXT,
    brand       TEXT,
    model       TEXT
);

\copy employee_laptop_import FROM '/tmp/pg-lab-employee-laptop.csv' WITH (FORMAT csv, HEADER)

SELECT *
FROM employee_laptop_import
ORDER BY employee_id;

-- 3. NULLs survive the round trip. In CSV, NULL is written as an empty field
--    and an empty string as "", so the two stay different. Chloe and Elena
--    came back with a NULL brand and model:
SELECT employee_id, first_name
FROM employee_laptop_import
WHERE brand IS NULL
ORDER BY employee_id;

-- 4. For a quick export from the shell, psql has a CSV output mode:
--      psql lab --csv -c "SELECT * FROM laptop" > /tmp/laptops.csv

-- 5. Security: if an exported file will be opened in Excel or Google Sheets,
--    a value starting with =, +, - or @ can run there as a formula (CSV
--    injection). Exports of user-typed text meant for spreadsheets need those
--    values neutralised first.
