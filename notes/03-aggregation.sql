-- 03-aggregation.sql: GROUP BY, HAVING, MIN / MAX / AVG / SUM
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/queries-table-expressions.html
--         https://www.postgresql.org/docs/current/functions-aggregate.html

-- Reset to a known state
\ir ../data/person.sql
\ir ../data/car.sql


-- GROUP BY ------------------------------------------------------------------

-- One result row per country. COUNT(*) counts the rows in each group.
SELECT country_of_birth, COUNT(*)
FROM person
GROUP BY country_of_birth
ORDER BY country_of_birth;


-- HAVING --------------------------------------------------------------------

-- WHERE filters rows before they're grouped; HAVING filters whole groups after.
-- > 5 means 6 or more. For "at least 5", write >= 5.
SELECT country_of_birth, COUNT(*)
FROM person
GROUP BY country_of_birth
HAVING COUNT(*) > 5
ORDER BY country_of_birth;


-- MIN / MAX / AVG -----------------------------------------------------------

SELECT MAX(price)
FROM car;

SELECT MIN(price)
FROM car;

-- AVG of a NUMERIC column gives a NUMERIC with many decimal places
SELECT AVG(price)
FROM car;

-- ROUND(x) rounds to a whole number; ROUND(x, 2) keeps two decimals
SELECT ROUND(AVG(price))
FROM car;

-- Cheapest car of each make and model: one group per make + model pair
SELECT make, model, MIN(price)
FROM car
GROUP BY make, model
ORDER BY make, model;

-- Most expensive car of each make and model
SELECT make, model, MAX(price)
FROM car
GROUP BY make, model
ORDER BY make, model;

-- Average price per make
SELECT make, ROUND(AVG(price))
FROM car
GROUP BY make
ORDER BY make;


-- SUM -----------------------------------------------------------------------

SELECT SUM(price)
FROM car;

SELECT make, SUM(price)
FROM car
GROUP BY make
ORDER BY make;


-- Beyond the video ----------------------------------------------------------

-- 1. Postgres evaluates a query in this order, not the order it's written in:
--      FROM -> WHERE -> GROUP BY -> HAVING -> SELECT -> ORDER BY -> LIMIT
--    That explains most rules in this file. WHERE runs before grouping, so it
--    can't use COUNT(*); HAVING can. SELECT runs late, so WHERE can't see a
--    SELECT alias, but ORDER BY can.

-- 2. Every column in SELECT must be in GROUP BY or inside an aggregate.
--    Otherwise there's no single value to show for the group.
-- Expected to fail: one row per make, but which model?
-- SELECT make, model, MAX(price)
-- FROM car
-- GROUP BY make;
-- ERROR:  column "car.model" must appear in the GROUP BY clause or be used in an aggregate function
--    One exception: after GROUP BY a table's primary key, you may select that
--    table's other columns, because the key already pins down a single row.

-- 3. COUNT(*) counts rows. COUNT(column) counts non-NULL values.
--    COUNT(DISTINCT column) counts different non-NULL values.
SELECT COUNT(*)                         AS people,
       COUNT(email)                     AS with_email,
       COUNT(DISTINCT country_of_birth) AS countries
FROM person;

-- 4. Aggregates skip NULLs. With no rows at all, SUM, AVG, MIN and MAX return
--    NULL, not 0. COUNT is the exception and returns 0.
SELECT SUM(price), COUNT(*)
FROM car
WHERE price < 0;                    -- no car matches: SUM is NULL, COUNT is 0

SELECT COALESCE(SUM(price), 0)
FROM car
WHERE price < 0;                    -- 0, for when a report needs a number

-- 5. FILTER: several conditional counts in one pass over the table
SELECT COUNT(*) FILTER (WHERE gender = 'Female') AS female,
       COUNT(*) FILTER (WHERE gender = 'Male')   AS male,
       COUNT(*) FILTER (WHERE email IS NULL)     AS no_email
FROM person;

-- 6. Sort by the aggregate to answer "which countries are most common?".
--    The second sort key breaks ties. Without it, which of several tied
--    countries makes the top 5 can change from run to run.
SELECT country_of_birth, COUNT(*) AS people
FROM person
GROUP BY country_of_birth
ORDER BY people DESC, country_of_birth
LIMIT 5;

-- 7. GROUP BY collapses each group into one row. A window function keeps
--    every row and puts the group's value beside it. Each car, next to the
--    average price for its make (window functions get their own file later):
SELECT make, model, price,
       ROUND(AVG(price) OVER (PARTITION BY make), 2) AS make_avg_price
FROM car
ORDER BY make, price DESC, id
LIMIT 10;
