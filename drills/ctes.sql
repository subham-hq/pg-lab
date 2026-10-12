-- ctes.sql: subqueries and CTEs drill, six queries on Pagila
-- Source: PostgreSQL phase, session 2: CMU 15-445 #02 (nested queries,
--         LATERAL, CTEs) and the docs' "WITH Queries". Written after the
--         lecture, then run against the data and reviewed; 2c, 3b, 7 and 8
--         were added in the review. The first version and each fix are in
--         git: git log -p -- drills/ctes.sql
-- Data:   Pagila 4.1.1 (devrimgunduz/pagila @ 9baf49c), database "pagila".
--         Results and plans checked on PostgreSQL 18.
-- Docs:   https://www.postgresql.org/docs/current/queries-with.html
--         https://www.postgresql.org/docs/current/functions-subquery.html
-- Run:    psql pagila -v ON_ERROR_STOP=1 -f drills/ctes.sql
--
-- Revision sheet (query numbers in brackets)
-- Subqueries
--   * A scalar subquery returns one column and at most one row. No rows
--     gives NULL; two or more is an error when the query runs (1).
--   * Uncorrelated: runs once, and EXPLAIN shows an InitPlan (1).
--     Correlated: reads the outer row, so unless the planner can turn it
--     into a join, it runs once per outer row: SubPlan, loops=999 (3a).
--   * IN and EXISTS are semi-joins: each outer row comes back once, however
--     many matches it has. A JOIN returns one row per match (2).
--   * EXISTS only checks that a row exists; its select list is ignored, so
--     write SELECT 1 (2b).
--   * A name resolves in the nearest query level first, then outward. Give
--     each level its own alias and qualify every column (2b).
--   * NOT EXISTS is the safe anti-join. NOT IN returns no rows at all once
--     the subquery returns a NULL (7).
--   * LATERAL lets a subquery in FROM read the row to its left. With
--     ORDER BY ... LIMIT n it gives the top n per row (3b).
-- CTEs
--   * WITH name AS (...) names a query for one statement. Each CTE can read
--     the ones above it, so a long query reads as a list of steps (6b).
--   * Since PostgreSQL 12 a CTE used once is inlined, planned as if it were
--     a subquery; one used twice is computed once and read twice (5).
--     MATERIALIZED and NOT MATERIALIZED override that (8).
--   * WITH RECURSIVE: an anchor, UNION ALL, then a step that reads only the
--     previous step's rows. It ends when a step returns no rows (4).
-- No error, wrong answer
--   * LIMIT through a tie: which tied rows you get depends on the plan (6).
--   * A column the inner table doesn't have binds to the outer query (2b).
--   * NOT IN against a NULL keeps nothing (7).
--   * No ORDER BY, no order. Every ORDER BY here ends on a unique column,
--     except under WITH TIES, which needs the ties (6).
-- Asked in interviews: NOT IN and NULLs (7), latest row per group (3), CTE
-- materialization before and after PostgreSQL 12 (8), top n with ties (6).
--
-- CTE or subquery? They usually get the same plan (EXPLAIN 1a and 1b: line
-- for line identical), so pick the one that reads better:
--   CTE       a result used twice (5), recursion (4), a chain of steps (6b)
--   Subquery  one value or one filter (1a, 2a), or one that reads the outer
--             row (3a): a CTE at the top can't see the main query's rows


-- 1. Films longer than the average film --------------------------------------
-- The subquery doesn't use the outer row, so it runs once (EXPLAIN:
-- InitPlan) and its one value, AVG(length) = 115.272, is compared with every
-- film. A scalar subquery may return at most one row. No rows gives NULL,
-- and length > NULL is never true (0 films); more than one row fails at run
-- time:
--   SELECT film_id FROM film WHERE length > (SELECT length FROM film);
--   ERROR:  more than one row returned by a subquery used as an expression
-- Review: one clause per line, and ORDER BY film_id. Without an ORDER BY the
-- order is whatever the plan happens to produce.

-- 1a. Subquery

SELECT
    film_id,
    title,
    length
FROM film
WHERE length > (
    SELECT AVG(length)
    FROM film
)
ORDER BY film_id;
-- 489 rows

-- 1b. The same filter as a CTE
-- average_length is used once, so it's inlined: EXPLAIN prints exactly 1a's
-- plan, with no CTE Scan (8 shows how to check).

WITH average_length AS (
    SELECT AVG(length) AS avg_length
    FROM film
)
SELECT
    film_id,
    title,
    length
FROM film
WHERE length > (
    SELECT avg_length
    FROM average_length
)
ORDER BY film_id;
-- 489 rows


-- 2. Customers who rented a Horror film --------------------------------------
-- IN and EXISTS are semi-joins: each customer comes back once, however many
-- Horror rentals they have. The same chain written as JOINs returns 7,315
-- rows, one per Horror rental, for 951 customers, and would need DISTINCT.
-- 2a and 2b get the same plan: the planner turns nested IN and nested
-- EXISTS alike into joins that return each customer once. "EXISTS is faster
-- than IN" comes from older optimizers; in PostgreSQL, EXPLAIN settles it.
-- (NOT IN is a different story: see 7.)
-- Review: customer_id added to the output and the ORDER BY. 14 names in this
-- list belong to more than one customer (AMARA JOHNSON is 612, 642 and 854),
-- and names alone can't tell those rows apart.
-- CONCAT skips NULLs; first_name || ' ' || last_name would be NULL if either
-- part were. Both columns are NOT NULL here, so either is fine.

-- 2a. IN, four levels deep
-- Read it from the inside out: Horror's category_id, its films, their copies
-- in inventory, the rentals of those copies, the customers who rented them.

SELECT
    customer_id,
    CONCAT(first_name, ' ', last_name) AS full_name
FROM customer
WHERE customer_id IN (
    SELECT customer_id
    FROM rental
    WHERE inventory_id IN (
        SELECT inventory_id
        FROM inventory
        WHERE film_id IN (
            SELECT film_id
            FROM film_category
            WHERE category_id IN (
                SELECT category_id
                FROM category
                WHERE name = 'Horror'
            )
        )
    )
)
ORDER BY
    full_name,
    customer_id;
-- 951 rows

-- 2b. Nested EXISTS
-- Review: the innermost alias was c, the same as customer's. It worked: a
-- name resolves in the nearest query level first, and there c is category.
-- But c then meant two tables, and that level could no longer reach the
-- customer:
--   ... FROM category AS c WHERE c.customer_id = ...
--   ERROR:  column c.customer_id does not exist
--   DETAIL:  There is a column named "customer_id" in table "c", but it
--   cannot be referenced from this part of the query.
-- Renamed it cat, qualified cat.name, and every level now selects 1.
-- The opposite slip gives no error at all: a column the inner table doesn't
-- have resolves to the outer query. inventory has no customer_id, so this
-- compares each customer with itself and keeps all 999:
--   SELECT COUNT(*) FROM customer
--   WHERE customer_id IN (SELECT customer_id FROM inventory);
-- A unique alias per level rules out the first slip; qualifying every
-- column (i.customer_id) turns the second into an error.

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name
FROM customer AS c
WHERE EXISTS (
    SELECT 1
    FROM rental AS r
    WHERE c.customer_id = r.customer_id AND EXISTS (
        SELECT 1
        FROM inventory AS i
        WHERE r.inventory_id = i.inventory_id AND EXISTS (
            SELECT 1
            FROM film_category AS fc
            WHERE i.film_id = fc.film_id AND EXISTS (
                SELECT 1
                FROM category AS cat
                WHERE fc.category_id = cat.category_id AND cat.name = 'Horror'
            )
        )
    )
)
ORDER BY
    full_name,
    c.customer_id;
-- 951 rows

-- 2c. One EXISTS with the joins inside (added in review)
-- Reads top to bottom like a JOIN, without the duplicates, and plans like 2b
-- give or take one step. 7a is this query with NOT.

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name
FROM customer AS c
WHERE EXISTS (
    SELECT 1
    FROM rental AS r
    JOIN inventory AS i
        ON i.inventory_id = r.inventory_id
    JOIN film_category AS fc
        ON fc.film_id = i.film_id
    JOIN category AS cat
        ON cat.category_id = fc.category_id
    WHERE
        r.customer_id = c.customer_id
        AND cat.name = 'Horror'
)
ORDER BY
    full_name,
    c.customer_id;
-- 951 rows


-- 3. Each customer's most recent rental --------------------------------------

-- 3a. Correlated subquery
-- The subquery reads c.customer_id, so it runs once per customer: in EXPLAIN
-- ANALYZE the nodes under its SubPlan show loops=999. PostgreSQL rewrites
-- MAX(rental_date) as "newest rental_date, LIMIT 1" and walks the index on
-- (rental_date, inventory_id, customer_id) backwards from the newest rental
-- until it meets one of this customer's. customer_id is that index's third
-- column, so the walk checks it entry by entry; it can't jump to it.
-- Quick here only because everyone who rents has a rental in the data's
-- last ten months, so each walk is short. For 647 and 978, who never rented,
-- it goes through all 51,805 entries. An index on rental (customer_id,
-- rental_date) would go straight to each customer's newest rental:
-- multicolumn indexes, session 7.
-- MAX(...) = rental_date returns every rental at that exact time, so a tie
-- would give a customer two rows. None here: 997 rows for 997 customers.
-- The inner JOIN drops 647 and 978; 3b keeps them.
-- Review: kept as written.

SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    r.rental_id,
    r.rental_date
FROM customer AS c
JOIN rental AS r
    ON c.customer_id = r.customer_id
WHERE r.rental_date = (
    SELECT MAX(r2.rental_date)
    FROM rental AS r2
    WHERE r2.customer_id = c.customer_id
)
ORDER BY c.customer_id;
-- 997 rows

-- 3b. LEFT JOIN LATERAL (added in review)
-- LATERAL lets a subquery in FROM read the row to its left. It runs per
-- customer like 3a, with the same backward index walk, but it can ORDER BY
-- and LIMIT: LIMIT 3 would give each customer's latest three rentals.
-- rental_id DESC breaks a tie on rental_date, so it's always one row.
-- LEFT JOIN keeps customers with no rentals, as NULLs. ON true, because the
-- WHERE inside has already done the matching.
-- Latest row per group, four ways, all agreeing on this data: correlated MAX
-- (3a), LATERAL ... LIMIT 1 (3b), DISTINCT ON (customer_id) with ORDER BY
-- customer_id, rental_date DESC (PostgreSQL only), and ROW_NUMBER() = 1
-- (window functions, session 3).

SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    lr.rental_id,
    lr.rental_date
FROM customer AS c
LEFT JOIN LATERAL (
    SELECT
        r.rental_id,
        r.rental_date
    FROM rental AS r
    WHERE r.customer_id = c.customer_id
    ORDER BY
        r.rental_date DESC,
        r.rental_id DESC
    LIMIT 1
) AS lr
    ON true
ORDER BY c.customer_id;
-- 999 rows: 3a's 997, plus 647 and 978 with NULL rental_id and rental_date


-- 4. Dates 2026-01-01 to 2026-01-10 with a recursive CTE ---------------------
-- The anchor (the SELECT before UNION ALL) makes the first row. Each step
-- reads only the rows the previous step made and adds one day. The
-- recursion ends when a step returns no rows, so the WHERE is the brake. It
-- tests the row the step starts from: 2026-01-09 passes and makes 01-10;
-- 01-10 fails and nothing more is made. With <= you'd get 11 rows, up to
-- 01-11. PostgreSQL has no recursion limit: without the WHERE it runs until
-- you cancel it.
-- UNION instead of UNION ALL also drops rows it has already made, which is
-- one way to stop a walk around a cycle in a graph.
-- date + INTERVAL '1 day' is a timestamp, hence the ::date; date + 1 is
-- already a date.
-- Recursion earns its keep on trees and graphs: an org chart, a category
-- tree, routes. A plain run of dates is simpler with generate_series:
--   SELECT DATE '2026-01-01' + n AS d FROM generate_series(0, 9) AS n;
-- Review: one clause per line, SELECT d rather than *, ORDER BY d.

WITH RECURSIVE dates AS (
    SELECT '2026-01-01'::date AS d
    UNION ALL
    SELECT (d + INTERVAL '1 day')::date
    FROM dates
    WHERE d < '2026-01-10'
)
SELECT d
FROM dates
ORDER BY d;
-- 10 rows


-- 5. Customers who paid more than the average paying customer ----------------
-- customer_totals is used twice, in FROM and in the subquery, so PostgreSQL
-- computes it once and reads it twice: EXPLAIN shows one "CTE
-- customer_totals" and two "CTE Scan on customer_totals". With subqueries,
-- the GROUP BY over payment would be written, and run, twice.
-- The average is over the 997 customers with payments (171.48), as the
-- question asks: customers who never paid aren't in customer_totals.
-- Review: one clause per line; ct.total qualified (in a two-table query a
-- bare column makes the reader look up where it's from); the subquery's
-- unused alias (AS average) dropped; ORDER BY, biggest spender first.

WITH customer_totals AS (
    SELECT
        customer_id,
        SUM(amount) AS total
    FROM payment
    GROUP BY customer_id
)
SELECT
    ct.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name,
    ct.total
FROM customer_totals AS ct
JOIN customer AS c
    ON ct.customer_id = c.customer_id
WHERE ct.total > (
    SELECT AVG(total)
    FROM customer_totals
)
ORDER BY
    ct.total DESC,
    ct.customer_id;
-- 592 rows: KARL SEAL (526) first with 358.12


-- 6. The 10 most-rented films ------------------------------------------------
-- Review fix: four films tie at 102 rentals for places 9-12 (film_id 358,
-- 382, 730, 911). LIMIT 10 kept whichever two the sort put first, so the two
-- versions disagreed: in the review run 6a's 10th film was RIDGEMONT
-- SUBMARINE and 6b's was GRIT CLOCKWORK. No error, and the answer can change
-- whenever the plan does.
-- FETCH FIRST 10 ROWS WITH TIES (PostgreSQL 13+) also returns every row that
-- ties with the 10th: 12 rows. It compares all the ORDER BY columns, so a
-- unique tie-breaker like film_id leaves nothing tied and gives exactly 10
-- again. Choose the rows with WITH TIES, then sort them for display (6b).
-- Before writing any "top 10", decide whether ties are in.

-- 6a. Join, then group

SELECT
    i.film_id,
    f.title,
    COUNT(*) AS total_rentals
FROM rental AS r
JOIN inventory AS i
    ON r.inventory_id = i.inventory_id
JOIN film AS f
    ON i.film_id = f.film_id
GROUP BY
    i.film_id,
    f.title
ORDER BY total_rentals DESC
FETCH FIRST 10 ROWS WITH TIES;
-- 12 rows: CAT CONEHEADS leads with 123. Films on the same count (four at
-- 104, four at 102) come in no fixed order: there's no tie-breaker to use.

-- 6b. Chained CTEs: count, keep the top 10 with ties, then add titles
-- Each CTE is a named step that reads the one above it. Only the 12 winners
-- are joined to film; the first version joined all 958 rented films.
-- Review: split into two steps (WITH TIES, then the display sort), and the
-- CTE renamed: total_rentals was also the name of one of its columns.

WITH film_rentals AS (
    SELECT
        i.film_id,
        COUNT(*) AS total_rentals
    FROM rental AS r
    JOIN inventory AS i
        ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
),
top_films AS (
    SELECT
        film_id,
        total_rentals
    FROM film_rentals
    ORDER BY total_rentals DESC
    FETCH FIRST 10 ROWS WITH TIES
)
SELECT
    tf.film_id,
    f.title,
    tf.total_rentals
FROM top_films AS tf
JOIN film AS f
    ON tf.film_id = f.film_id
ORDER BY
    tf.total_rentals DESC,
    tf.film_id;
-- 12 rows, in the same order every run


-- 7. Customers who never rented a Horror film (added in review) --------------
-- The opposite of 2: an anti-join keeps the outer rows that have no match.

-- 7a. NOT EXISTS: the one to reach for
-- EXPLAIN: Hash Anti Join. It's 2c with NOT.

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name
FROM customer AS c
WHERE NOT EXISTS (
    SELECT 1
    FROM rental AS r
    JOIN inventory AS i
        ON i.inventory_id = r.inventory_id
    JOIN film_category AS fc
        ON fc.film_id = i.film_id
    JOIN category AS cat
        ON cat.category_id = fc.category_id
    WHERE
        r.customer_id = c.customer_id
        AND cat.name = 'Horror'
)
ORDER BY c.customer_id;
-- 48 rows: 999 customers minus the 951 in 2, with 647 and 978 among them

-- 7b. The NOT IN trap
-- x NOT IN (a, b) means x <> a AND x <> b. Against a NULL, x <> NULL is NULL
-- (unknown), so the test is never true and no row passes: 1 NOT IN (2, NULL)
-- is NULL, not true. rental.customer_id is NOT NULL, so NOT IN gives 48
-- today; a nullable column or a LEFT JOIN inside the subquery would quietly
-- make it 0. not_in_with_null fakes that with UNION ALL SELECT NULL.
-- Because of those rules NOT IN can't be planned as an anti-join: EXPLAIN
-- shows a filter over a (hashed) SubPlan, and when the subquery is too big
-- to hash, it's scanned again for every outer row.
-- horror_renters is used twice, so it's a CTE: computed once (5).

WITH horror_renters AS (
    SELECT r.customer_id
    FROM rental AS r
    JOIN inventory AS i
        ON i.inventory_id = r.inventory_id
    JOIN film_category AS fc
        ON fc.film_id = i.film_id
    JOIN category AS cat
        ON cat.category_id = fc.category_id
    WHERE cat.name = 'Horror'
)
SELECT
    COUNT(*) FILTER (
        WHERE c.customer_id NOT IN (
            SELECT customer_id
            FROM horror_renters
        )
    ) AS not_in,
    COUNT(*) FILTER (
        WHERE c.customer_id NOT IN (
            SELECT customer_id
            FROM horror_renters
            UNION ALL
            SELECT NULL
        )
    ) AS not_in_with_null
FROM customer AS c;
-- not_in 48, not_in_with_null 0


-- 8. Is a CTE an optimization fence? (added in review) -----------------------
-- Session 2's trap. Before PostgreSQL 12 every CTE was computed on its own,
-- in full, and a WHERE outside it couldn't get in: a "fence". Since 12 a CTE
-- that's used once, isn't recursive and has no side effects is inlined:
-- planned as a subquery, so outer filters are pushed inside it.
-- 8a, inlined: film_id = 1 is applied to inventory itself. Only film 1's 8
-- copies and their 81 rentals are read, and there's no CTE Scan. On 18 it
-- even uses the index on (store_id, film_id) with no store_id given: a skip
-- scan, hence Index Searches: 3 (session 7's trap).
-- 8b, MATERIALIZED: all 51,805 rentals are joined and counted into 958
-- groups, then the CTE Scan's filter throws 957 away. Same answer; compare
-- the Buffers and Execution Time lines.
-- MATERIALIZED forces the fence when you want one; NOT MATERIALIZED inlines
-- a CTE that's used twice, which then runs twice.
-- ANALYZE runs the query and shows actual rows; COSTS OFF and TIMING OFF
-- hide the estimates and per-node timings that change from run to run.

-- 8a. Inlined (the default)

EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
WITH film_rentals AS (
    SELECT
        i.film_id,
        COUNT(*) AS total_rentals
    FROM rental AS r
    JOIN inventory AS i
        ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
)
SELECT
    film_id,
    total_rentals
FROM film_rentals
WHERE film_id = 1;
-- No CTE Scan; the filter is on inventory, and the Nested Loop returns 81

-- 8b. MATERIALIZED

EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
WITH film_rentals AS MATERIALIZED (
    SELECT
        i.film_id,
        COUNT(*) AS total_rentals
    FROM rental AS r
    JOIN inventory AS i
        ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
)
SELECT
    film_id,
    total_rentals
FROM film_rentals
WHERE film_id = 1;
-- CTE Scan on film_rentals with Filter: (film_id = 1) and Rows Removed by
-- Filter: 957; below it, the Hash Join returns 51805
