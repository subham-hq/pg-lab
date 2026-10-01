-- 04-expressions.sql: arithmetic operators, ROUND, aliases
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/functions-math.html

-- Reset to a known state
\ir ../data/car.sql


-- Arithmetic operators ------------------------------------------------------

SELECT 10 + 2 AS TOTAL;             -- 12, in a column named total (Beyond, 5)
SELECT 10 * 2 / 2 - 10 + 1000;      -- 1000: 10 * 2 / 2 is 10 first, then 10 - 10 + 1000
SELECT 10 % 3;                      -- 1: % gives the remainder


-- Arithmetic on columns, and ROUND ------------------------------------------

-- price * 0.10 is 10% of the price: the discount, not the discounted price
SELECT id, make, model, price, price * 0.10 AS discount
FROM car
ORDER BY id
LIMIT 10;

-- ROUND(x, 2) keeps two decimal places. The price after the discount is
-- price - discount.
SELECT id, make, model, price,
       ROUND(price * 0.10, 2)         AS discount,
       ROUND(price - price * 0.10, 2) AS discounted_price
FROM car
ORDER BY id
LIMIT 10;


-- Aliases -------------------------------------------------------------------

-- AS renames a column in the result. AS is optional, but writing it protects
-- you from a missing comma: SELECT make model quietly returns make, renamed
-- to model.
SELECT id, make AS car_company
FROM car
ORDER BY id
LIMIT 10;


-- Beyond the video ----------------------------------------------------------

-- 1. Integer / integer is integer division: the fraction is thrown away.
SELECT 5 / 2;                  -- 2, not 2.5
SELECT 5 / 2.0;                -- 2.5000000000000000: one NUMERIC side makes it exact
SELECT 5::numeric / 2;         -- the same, with a cast
--    The classic percentage bug: the division happens before the * 100.
SELECT 1 / 3 * 100;            -- 0
SELECT 100.0 * 1 / 3;          -- 33.3333333333333333

-- 2. NUMERIC is exact decimal. REAL and DOUBLE PRECISION are binary floating
--    point, which can't store 0.1 exactly:
SELECT 0.1 + 0.2;                                        -- 0.3
SELECT 0.1::double precision + 0.2::double precision;    -- 0.30000000000000004
--    Money goes in NUMERIC, never a float: the same reason you use Decimal
--    in Python.

-- 3. ROUND depends on the type. NUMERIC rounds a half away from zero; DOUBLE
--    PRECISION rounds a half to the nearest even number:
SELECT ROUND(2.5::numeric), ROUND(2.5::double precision);    -- 3 and 2

-- 4. A SELECT alias doesn't exist yet when WHERE runs (03, Beyond 1).
-- Expected to fail: WHERE can't see the alias
-- SELECT make AS car_company
-- FROM car
-- WHERE car_company = 'Ford';
-- ERROR:  column "car_company" does not exist
--    ORDER BY runs after SELECT, so ORDER BY car_company does work.

-- 5. Unquoted names are folded to lowercase, so AS TOTAL above made a column
--    called total. Double quotes keep the case, but then the name needs quotes
--    everywhere, forever. Stick to lower_snake_case and you never need them.
SELECT 10 + 2 AS "TOTAL";

-- 6. Dividing by zero is an error, not infinity. 05-nulls shows how to avoid it.
