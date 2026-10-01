-- 11-joins.sql: INNER JOIN, LEFT JOIN
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/queries-table-expressions.html  (Joined Tables)

-- Reset to a known state: 5 employees, 4 laptops.
-- Chloe and Elena have no laptop; laptop 4 (Framework) belongs to nobody.
\ir ../data/employee-laptop.sql


-- INNER JOIN ----------------------------------------------------------------

-- Only rows that match on both sides: employees who have a laptop.
-- A plain JOIN is an INNER JOIN.
SELECT *
FROM employee
JOIN laptop ON employee.laptop_id = laptop.id
ORDER BY employee.id;

-- Pick the columns you need and name them. Employee 1's laptop:
SELECT laptop.brand AS laptop_brand,
       laptop.model AS laptop_model,
       employee.first_name
FROM employee
JOIN laptop ON employee.laptop_id = laptop.id
WHERE employee.id = 1;


-- LEFT JOIN -----------------------------------------------------------------

-- Every employee, plus their laptop if they have one. For Chloe and Elena the
-- laptop columns come back NULL.
SELECT *
FROM employee
LEFT JOIN laptop ON employee.laptop_id = laptop.id
ORDER BY employee.id;


-- Beyond the video ----------------------------------------------------------

-- 1. Table aliases keep joins readable. Once a table has an alias, use it.
SELECT e.first_name, l.brand, l.model
FROM employee AS e
LEFT JOIN laptop AS l ON l.id = e.laptop_id
ORDER BY e.id;

-- 2. Both tables have an id column, so a bare id is ambiguous.
-- Expected to fail: which id?
-- SELECT id
-- FROM employee
-- JOIN laptop ON employee.laptop_id = laptop.id;
-- ERROR:  column reference "id" is ambiguous
--    SELECT * returns two columns named id. Fine for exploring; in application
--    code, list the columns you need.

-- 3. Finding rows with no match (an anti-join). Laptops nobody has:
SELECT l.id, l.brand, l.model
FROM laptop AS l
LEFT JOIN employee AS e ON e.laptop_id = l.id
WHERE e.id IS NULL
ORDER BY l.id;

--    NOT EXISTS asks the same question, often more clearly:
SELECT l.id, l.brand, l.model
FROM laptop AS l
WHERE NOT EXISTS (
    SELECT 1
    FROM employee AS e
    WHERE e.laptop_id = l.id
)
ORDER BY l.id;

--    Employees without a laptop need no join at all: WHERE laptop_id IS NULL.

-- 4. The LEFT JOIN trap. A WHERE condition on the right-hand table removes the
--    rows where that table is NULL, which quietly turns the LEFT JOIN into an
--    inner join:
SELECT e.first_name, l.brand
FROM employee AS e
LEFT JOIN laptop AS l ON l.id = e.laptop_id
WHERE l.brand = 'Apple'
ORDER BY e.id;                      -- only Ben

--    In ON, the condition only decides which laptops get attached. Every
--    employee stays, and only the Apple laptop shows up:
SELECT e.first_name, l.brand
FROM employee AS e
LEFT JOIN laptop AS l ON l.id = e.laptop_id AND l.brand = 'Apple'
ORDER BY e.id;                      -- all 5 employees
--    Both are valid; they answer different questions. Know which one you mean.

-- 5. FULL JOIN keeps unmatched rows from both sides:
--    5 employees + the laptop nobody has = 6 rows
SELECT e.first_name, l.brand, l.model
FROM employee AS e
FULL JOIN laptop AS l ON l.id = e.laptop_id
ORDER BY e.id, l.id;

--    CROSS JOIN pairs every row with every row: 5 x 4 = 20. A JOIN with the
--    wrong ON condition can multiply rows the same way.
SELECT COUNT(*)
FROM employee
CROSS JOIN laptop;

-- 6. In a one-to-many join, each row on the "one" side repeats once per match,
--    so summing one of its columns after the join counts it several times.
--    Here UNIQUE (laptop_id) makes it one-to-one, so that can't happen.

-- 7. Joins are fast when the ON columns are indexed: laptop.id by the primary
--    key, employee.laptop_id by the UNIQUE constraint. EXPLAIN shows which join
--    method Postgres chose; that's the indexing drill.
