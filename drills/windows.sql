-- Top 3 Films per Category

WITH total_rentals AS (
    SELECT i.film_id, COUNT(*) AS total_rentals
    FROM rental AS r
    JOIN inventory AS i
        ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
),
    ranked_films AS (
    SELECT tr.film_id, f.title, c.name, tr.total_rentals, ROW_NUMBER() OVER (
    PARTITION BY c.category_id
    ORDER BY tr.total_rentals DESC, tr.film_id
    ) AS film_rank
    FROM total_rentals AS tr
    JOIN film AS f
        ON tr.film_id = f.film_id
    JOIN film_category AS fc
        ON tr.film_id = fc.film_id
    JOIN category AS c
        ON fc.category_id = c.category_id
)
SELECT *
FROM ranked_films
WHERE film_rank <= 3
ORDER BY name ASC;



-- ### ROW_NUMBER() vs RANK() vs DENSE_RANK()

-- | Score | ROW_NUMBER() | RANK() | DENSE_RANK() |
-- |---|---|---|---|
-- | 100 | 1 | 1 | 1 |
-- | 90 | 2 | 2 | 2 |
-- | 90 | 3 | 2 | 2 |
-- | 80 | 4 | 4 | 3 |
-- | 70 | 5 | 5 | 4 |

-- **Key differences:**
-- - `ROW_NUMBER()` → Unique sequential numbers, even for ties.
-- - `RANK()` → Same rank for ties, skips subsequent ranks.
-- - `DENSE_RANK()` → Same rank for ties, never skips ranks.

-- **SQL Example:**
-- ```sql
-- SELECT
--     score,
--     ROW_NUMBER() OVER (ORDER BY score DESC) AS row_num,
--     RANK() OVER (ORDER BY score DESC) AS rank,
--     DENSE_RANK() OVER (ORDER BY score DESC) AS dense_rank
-- FROM scores;
-- ```

-- **Remember:**
-- - `ROW_NUMBER()` → 1, 2, 3, 4, 5
-- - `RANK()` → 1, 2, 2, 4, 5
-- - `DENSE_RANK()` → 1, 2, 2, 3, 4

-- **Note:** `ROW_NUMBER()` assigns arbitrary order between tied scores unless you specify a tie-breaker.


-- Month-over-Month Revenue Change per Store

SELECT
    month_year,
    store_id,
    revenue,
    previous_month,
    revenue - previous_month AS revenue_change
FROM (
    SELECT
        txn_month,
        TO_CHAR(txn_month, 'FMMonth YYYY') AS month_year,
        store_id,
        revenue,
        LAG(revenue) OVER (
            PARTITION BY store_id
            ORDER BY txn_month
        ) AS previous_month
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
            i.store_id,
            txn_month
    ) AS monthly_revenue
) AS revenue_comparison
ORDER BY txn_month, store_id;

-- running spend per customer

SELECT TO_CHAR(
    p.payment_date AT TIME ZONE 'UTC',
    'Mon FMDD, YYYY'
) AS payment_date,
    c.customer_id,
    p.payment_id,
    CONCAT(c.first_name, ' ',  c.last_name) AS name,
    p.amount,
    SUM(p.amount) OVER(
    PARTITION BY c.customer_id
    ORDER BY p.payment_date, p.payment_id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cummilitive_amount
FROM customer AS c
JOIN payment AS p
    ON c.customer_id = p.customer_id
ORDER BY c.customer_id, p.payment_date, p.payment_id;

-- NOTE:
-- For running totals, ORDER BY inside OVER() determines
-- the order in which values are accumulated.
-- The final ORDER BY determines how rows are displayed.
-- Both should use the same chronological order.
--
-- Always order by payment_date first, then payment_id
-- as a tie-breaker for identical timestamps.
--
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
-- ensures each payment is added individually, from
-- the first payment up to the current payment.


-- days between a customer's consecutive rentals
SELECT customer_id,
    rental_id,
    TO_CHAR(
    rental_date AT TIME ZONE 'UTC',
    'Mon FMDD, YYYY'
    ) AS current_rental_date,
    TO_CHAR(
    previous_rental AT TIME ZONE 'UTC',
    'Mon FMDD, YYYY'
    ) AS previous_rental_date,
    ROUND(
        EXTRACT(
        EPOCH FROM (rental_date - previous_rental)
        ) / 86400,
        1) AS days_between
FROM (
    SELECT customer_id,
        rental_id,
        rental_date,
        LAG(rental_date) OVER(PARTITION BY customer_id ORDER BY rental_date, rental_id) AS previous_rental
    FROM rental
) AS rental_history
ORDER BY customer_id, rental_date, rental_id;

-- NOTE:
-- LAG() retrieves the previous row's value within a partition.
-- PARTITION BY customer_id resets the calculation for each customer.
-- ORDER BY rental_date, rental_id ensures chronological ordering
-- and handles identical timestamps using rental_id as a tie-breaker.
--
-- Subtracting two timestamps produces an INTERVAL.
-- EXTRACT(EPOCH FROM interval) converts it into seconds.
-- Dividing by 86400 converts seconds into fractional days.
-- ROUND(value, 1) rounds the result to one decimal place.
--
-- Casting timestamps to DATE ignores the time component,
-- whereas EPOCH calculates the actual elapsed time.
--
-- The first rental of each customer returns NULL because
-- no previous rental exists.
--
-- TO_CHAR() formats dates for display only.
-- Always use actual timestamps for calculations and sorting.

-- TIE-BREAKER:
-- ORDER BY rental_date, rental_id ensures deterministic ordering.
--
-- If two rentals have identical rental_date timestamps,
-- PostgreSQL cannot determine their relative order from
-- rental_date alone.
--
-- rental_id acts as a tie-breaker because it uniquely
-- identifies each rental.
--
-- Example:
-- Rental 101 → Jan 1, 10:00 AM
-- Rental 102 → Jan 1, 10:00 AM
--
-- Without rental_id, LAG() may select either rental first.
-- With rental_id, rental 101 comes before rental 102.
--
-- IMPORTANT:
-- A tie-breaker ensures consistent, predictable results.
-- It does not necessarily indicate which rental happened
-- first when the timestamps are identical.


-- actors ranked by film count within category

SELECT name,
    actor,
    film_count,
    DENSE_RANK() OVER(PARTITION BY category_id ORDER BY film_count DESC) AS rank
FROM (
    SELECT c.category_id,
        c.name,
        a.actor_id,
        CONCAT(a.first_name, ' ', a.last_name) AS actor,
        COUNT(DISTINCT f.film_id) AS film_count
    FROM actor AS a
    JOIN film_actor AS fa
        ON a.actor_id = fa.actor_id
    JOIN film AS f
        ON fa.film_id = f.film_id
    JOIN film_category AS fc
        ON f.film_id = fc.film_id
    JOIN category AS c
        ON fc.category_id = c.category_id
    GROUP BY c.category_id, c.name, a.actor_id
    ORDER BY c.name
) AS actor_film_counts
ORDER BY name, rank;


