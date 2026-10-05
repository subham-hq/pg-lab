-- pagila-tier1.sql: Tier-1 drill, eight queries on Pagila written cold
-- Source: PostgreSQL phase, session 1. Written with no notes and no video,
--         then run against the data and reviewed. The cold version and each
--         fix are in git: git log -p -- drills/pagila-tier1.sql
-- Data:   Pagila 4.1.1 (devrimgunduz/pagila @ 9baf49c), database "pagila"
-- Run:    psql pagila -v ON_ERROR_STOP=1 -f drills/pagila-tier1.sql
--
-- What the review taught (details at each query):
--   * A query can run without an error and still answer the wrong question.
--     Check a number against something independent before trusting it (3).
--   * DATE_TRUNC on a timestamptz cuts months in the session's TimeZone, so
--     the same query gave different totals in IST and in UTC (3, 6).
--   * Every ORDER BY ends on a unique column, so ties can't reorder the output.
--   * Unquoted names fold to lowercase: AS CUST_ID came back as cust_id.


-- 1. Top 10 customers by total paid ------------------------------------------
-- Review: lowercase aliases; customer_id breaks ties, so the top 10 can't
-- change between runs. 10th and 11th are close (311.18 vs 311.11), not tied.

SELECT
    c.customer_id AS cust_id,
    c.first_name || ' ' || c.last_name AS customer_name,
    SUM(p.amount) AS total_amount
FROM payment AS p
JOIN customer AS c
    ON p.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name
ORDER BY
    total_amount DESC,
    c.customer_id
LIMIT 10;
-- 10 rows: KARL SEAL (526) leads with 358.12


-- 2. Films never rented ------------------------------------------------------
-- NOT EXISTS, not NOT IN: one NULL inside a NOT IN subquery empties the whole
-- result. All 42 films here have no copies in inventory at all; none was
-- stocked and then left on the shelf. The query catches both cases.
-- Review: dropped the alias (AS TITLE came back as title anyway).

SELECT f.title
FROM film AS f
WHERE NOT EXISTS (
    SELECT 1
    FROM inventory AS i
    JOIN rental AS r
        ON r.inventory_id = i.inventory_id
    WHERE i.film_id = f.film_id
)
ORDER BY f.title;
-- 42 rows


-- 3. Revenue per store per month ---------------------------------------------
-- A store earns the payments for its own copies: payment -> rental ->
-- inventory.store_id, the same path as the schema's sales_by_store view.
-- Review fixes:
--   * Store: the cold version credited the store of the staff member who took
--     the payment. In this data the only two cashiers (staff 1 and 2) are
--     assigned to stores 25 and 33, which own no stock and have no customers,
--     so every payment went to the wrong store. No error, wrong numbers.
--     Check: SELECT * FROM sales_by_store; each store's months add up to its
--     total (store 1: 85,765.04, store 2: 85,197.35).
--   * Time zone: DATE_TRUNC on a timestamptz cuts months in the session's
--     TimeZone. In IST, 381 payments move to the next month and 105 of the
--     110 rows change. AT TIME ZONE 'UTC' turns payment_date into UTC
--     wall-clock time first: the month boundaries payment is partitioned on.
--   * Label: 'Month' pads to 9 characters ('May       2022'); FM removes it.
-- Sorting on txn_month (a timestamp), not month_year (text), keeps calendar
-- order. As text, April would come before January.

SELECT
    TO_CHAR(txn_month, 'FMMonth YYYY') AS month_year,
    store_id,
    revenue
FROM (
    SELECT
        DATE_TRUNC('month', p.payment_date AT TIME ZONE 'UTC') AS txn_month,
        i.store_id,
        SUM(p.amount) AS revenue
    FROM payment AS p
    JOIN rental AS r
        ON r.rental_id = p.rental_id
    JOIN inventory AS i
        ON i.inventory_id = r.inventory_id
    GROUP BY
        DATE_TRUNC('month', p.payment_date AT TIME ZONE 'UTC'),
        i.store_id
) AS monthly_revenue
ORDER BY
    store_id,
    txn_month;
-- 110 rows: 2 stores x 55 months, January 2022 to July 2026


-- 4. Actors in 30+ films -----------------------------------------------------
-- COUNT(*) counts films because film_actor's key is (actor_id, film_id).
-- Grouping by actor_id, not the name, matters: actors 101 and 110 are both
-- SUSAN DAVIS. Grouped by name they'd merge into one 54-film actor; 101 has
-- 33 films and is on this list, 110 has 21.
-- Review: actor_id shown, so same-name actors can be told apart, and used as
-- the tie-breaker (the 72 actors share only 12 different film counts).

SELECT
    a.actor_id,
    a.first_name || ' ' || a.last_name AS actor_name,
    COUNT(*) AS film_count
FROM actor AS a
JOIN film_actor AS fa
    ON fa.actor_id = a.actor_id
GROUP BY
    a.actor_id,
    a.first_name,
    a.last_name
HAVING COUNT(*) >= 30
ORDER BY
    film_count DESC,
    a.actor_id;
-- 72 rows


-- 5. Films per category ------------------------------------------------------
-- The counts add up to 2,367, not 1,000: in Pagila 4.x a film can be in up to
-- three categories.
-- Review: LEFT JOIN with COUNT(fc.film_id), so a category with no films shows
-- 0 instead of vanishing (COUNT(*) would count its NULL row as 1). Every
-- category has films today, so the output didn't change.

SELECT
    c.name AS category,
    COUNT(fc.film_id) AS no_of_films
FROM category AS c
LEFT JOIN film_category AS fc
    ON c.category_id = fc.category_id
GROUP BY
    c.category_id,
    c.name
ORDER BY
    c.name,
    c.category_id;
-- 16 rows


-- 6. Customers who rented in only one month ----------------------------------
-- DATE_TRUNC keeps the year, so January 2023 and January 2024 stay separate
-- months; EXTRACT(MONTH ...) would merge them. The 2 customers who never
-- rented have zero months, and the inner join rightly leaves them out.
-- Review: months cut in UTC (see 3), and an ORDER BY.

SELECT
    c.customer_id AS cust_id,
    c.first_name || ' ' || c.last_name AS customer_name
FROM customer AS c
JOIN rental AS r
    ON r.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name
HAVING COUNT(
    DISTINCT DATE_TRUNC('month', r.rental_date AT TIME ZONE 'UTC')
) = 1
ORDER BY c.customer_id;
-- 7 rows, each with one or two rentals in a single month of April-July 2026


-- 7. Late returns ------------------------------------------------------------
-- Late = returned more than rental_duration days after renting, the same rule
-- the schema's get_customer_balance() uses to charge late fees.
-- 241 rentals were never returned. Their return_date is NULL, NULL > x is
-- unknown, and WHERE drops them. That's right for "returned late"; "still out
-- and overdue" is a different question, which needs return_date IS NULL.
-- Review: ORDER BY added. 7b was added in review: the drill plan asked for a
-- count, and 27,750 rows are hard to read.

SELECT
    r.rental_id,
    r.customer_id,
    f.title,
    r.rental_date,
    r.return_date,
    f.rental_duration
FROM rental AS r
JOIN inventory AS i
    ON r.inventory_id = i.inventory_id
JOIN film AS f
    ON i.film_id = f.film_id
WHERE
    r.return_date >
    r.rental_date + f.rental_duration * INTERVAL '1 day'
ORDER BY r.rental_id;
-- 27,750 rows

-- 7b. The same rule as a count, and as a share of the rentals returned.
-- is_late is worked out once per rental, then counted twice.

SELECT
    COUNT(*) FILTER (WHERE is_late) AS late_returns,
    COUNT(*) AS returned,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_late) / COUNT(*), 1) AS late_pct
FROM (
    SELECT
        r.return_date >
        r.rental_date + f.rental_duration * INTERVAL '1 day' AS is_late
    FROM rental AS r
    JOIN inventory AS i
        ON r.inventory_id = i.inventory_id
    JOIN film AS f
        ON i.film_id = f.film_id
    WHERE r.return_date IS NOT NULL
) AS returned_rentals;
-- late_returns 27750, returned 51564, late_pct 53.8


-- 8. Most-rented film per category -------------------------------------------
-- RANK() keeps ties, so a category with two films sharing first place shows
-- both: Animation (GILMORE BOILED, GRIT CLOCKWORK: 102) and New (CURTAIN
-- VIDEOTAPE, FORWARD TEMPLE: 101). ROW_NUMBER() would silently keep one.
-- A film can top more than one category: DEER VIRGINIAN tops three.
-- Review: group and partition by category_id, not the name (names have no
-- UNIQUE constraint); title breaks ties in the final ORDER BY.

WITH film_rentals AS (
    SELECT
        c.category_id,
        c.name AS category,
        f.film_id,
        f.title,
        COUNT(r.rental_id) AS rental_count
    FROM category AS c
    JOIN film_category AS fc
        ON c.category_id = fc.category_id
    JOIN film AS f
        ON fc.film_id = f.film_id
    JOIN inventory AS i
        ON f.film_id = i.film_id
    JOIN rental AS r
        ON i.inventory_id = r.inventory_id
    GROUP BY
        c.category_id,
        c.name,
        f.film_id,
        f.title
),
ranked_films AS (
    SELECT
        category,
        film_id,
        title,
        rental_count,
        RANK() OVER (
            PARTITION BY category_id
            ORDER BY rental_count DESC
        ) AS film_rank
    FROM film_rentals
)
SELECT
    category,
    title,
    rental_count
FROM ranked_films
WHERE film_rank = 1
ORDER BY
    category,
    title,
    film_id;
-- 18 rows for 16 categories: the two ties above
