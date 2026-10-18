-- windows.sql: window functions drill, ten queries on Pagila
-- Source: PostgreSQL phase, session 3: CMU 15-445 #02 (window functions)
--         and the docs' "Window Functions" tutorial. Written after the
--         lecture, then run against the data and reviewed. 1, 2b and 7-11
--         were added in the review, and the sections are now in topic
--         order. The first version and every fix are in git:
--         git log -p -- drills/windows.sql
-- Data:   Pagila 4.1.1 (devrimgunduz/pagila @ 9baf49c), database "pagila".
--         Results checked on PostgreSQL 18, in UTC and in IST.
-- Docs:   https://www.postgresql.org/docs/current/tutorial-window.html
--         https://www.postgresql.org/docs/current/functions-window.html
--         https://www.postgresql.org/docs/current/sql-expressions.html
--         (the part "Window Function Calls" covers frames and defaults)
-- Run:    psql pagila -v ON_ERROR_STOP=1 -f drills/windows.sql
--
-- GROUP BY vs a window function, in one sentence:
--   GROUP BY folds each group into one row; a window function keeps every
--   row and adds a value computed over a set of related rows, its window.
--
-- How OVER (...) reads: function() OVER (PARTITION BY a ORDER BY b frame)
--   PARTITION BY  splits the rows into groups that are handled separately,
--                 like GROUP BY, but no row disappears
--   ORDER BY      orders the rows inside each group. Ranking and LAG/LEAD
--                 need it, and it turns SUM or AVG into a running one
--   frame         which rows around the current one an aggregate looks
--                 at, e.g. ROWS BETWEEN 2 PRECEDING AND CURRENT ROW (9)
--
-- Revision sheet (query numbers in brackets)
-- Ranking
--   * ROW_NUMBER numbers every row, ties too: 1, 2, 3, 4. RANK gives ties
--     the same number and then skips: 1, 2, 2, 4. DENSE_RANK doesn't skip:
--     1, 2, 2, 3 (1).
--   * Top n per group: rank inside a CTE or subquery, filter outside it.
--     WHERE runs before window functions, so it can't use them (2).
--   * Ties at the cut-off: ROW_NUMBER keeps exactly n rows, RANK keeps the
--     ties (2).
-- Looking at other rows
--   * LAG(x) is x from the previous row of the partition, LEAD(x) from the
--     next one. The first row has no previous row, so LAG gives NULL (4, 5).
-- Running and moving totals
--   * SUM(x) OVER (ORDER BY ...) is a running total. Without ORDER BY it's
--     the whole partition's total, repeated on every row (6, 8).
--   * With ORDER BY, the default frame is RANGE BETWEEN UNBOUNDED PRECEDING
--     AND CURRENT ROW, and RANGE takes in every row tied with the current
--     one (7).
--   * ROWS counts rows; RANGE with an offset counts values, such as
--     INTERVAL '2 months' PRECEDING (9).
-- Buckets and patterns
--   * NTILE(n) deals the ordered rows into n groups of nearly equal size
--     (10).
--   * Gaps and islands: subtract a row number from a running sequence.
--     Every unbroken run gets the same difference, so GROUP BY it (11).
-- No error, wrong answer
--   * ROW_NUMBER at a tie silently drops one of the tied rows (2a).
--   * LAG looks one row back, not one month back: a missing month would be
--     compared with two months earlier (4).
--   * An alias with a column's name changes what ORDER BY sorts on (6).
--   * Without a unique ORDER BY in OVER, running totals jump on ties and
--     LAST_VALUE returns the current row (7).
--   * NTILE can put equal values into different buckets (10).
-- The order a query is worked out in:
--   FROM, WHERE, GROUP BY, HAVING, window functions, SELECT list, DISTINCT,
--   ORDER BY, LIMIT. So a window can use an aggregate (SUM(SUM(x)) OVER ()
--   in 10), but WHERE can't use a window function (2).
-- Every ORDER BY, inside OVER and at the end, finishes on a unique column,
-- except where a query needs the ties (2b, 7, 11).
-- Asked in interviews: top n per group (2), running totals and the frame
-- trap (6, 7), change over time with LAG (4), gaps and islands (11), and
-- ROW_NUMBER vs RANK vs DENSE_RANK (1).


-- 1. ROW_NUMBER vs RANK vs DENSE_RANK (added in review) ----------------------
-- The comparison table from the first version, now runnable: five scores
-- with a tie at 90.
--
--   score | ROW_NUMBER | RANK | DENSE_RANK
--   ------+------------+------+-----------
--     100 |          1 |    1 |          1
--      90 |          2 |    2 |          2
--      90 |          3 |    2 |          2
--      80 |          4 |    4 |          3
--      70 |          5 |    5 |          4
--
-- ROW_NUMBER  a unique, sequential number for every row, even for ties.
-- RANK        ties share a number, and the next number skips (2, 2, 4):
--             rank n means n - 1 rows come before this one.
-- DENSE_RANK  ties share a number and nothing is skipped (2, 2, 3): dense
--             rank n means n - 1 different values come before this one.
-- Remember: ROW_NUMBER 1, 2, 3, 4, 5; RANK 1, 2, 2, 4, 5; DENSE_RANK 1, 2,
-- 2, 3, 4.
-- ROW_NUMBER puts tied rows in an arbitrary order unless the ORDER BY has a
-- tie-breaker. The two 90s here are identical, so that order can't be seen.
-- WINDOW w names the window once, so the three functions can share it.

SELECT
    score,
    ROW_NUMBER() OVER w AS row_num,
    RANK() OVER w AS rank,
    DENSE_RANK() OVER w AS dense_rank
FROM (VALUES (100), (90), (90), (80), (70)) AS scores (score)
WINDOW w AS (ORDER BY score DESC)
ORDER BY
    score DESC,
    row_num;
-- 5 rows, the same as the table


-- 2. Top 3 films per category ------------------------------------------------
-- Count each film's rentals once (film_rentals), rank the films inside each
-- category (ranked_films), then keep ranks 1-3. The rank has to be filtered
-- outside the query that computes it, because WHERE runs before window
-- functions:
--   SELECT film_id FROM film WHERE ROW_NUMBER() OVER (ORDER BY film_id) <= 3;
--   ERROR:  window functions are not allowed in WHERE
-- A film can be in up to three categories, so it can be in more than one
-- top 3: DEER VIRGINIAN tops Foreign, Sci-Fi and Travel.
-- Review: the CTE was called total_rentals, the same as its column (the same
-- slip as ctes.sql 6b), now film_rentals. The final ORDER BY was only the
-- category name, so the three films of a category could come out in any
-- order; it now ends on the rank. Columns listed instead of SELECT *, and
-- name shown as category.

-- 2a. ROW_NUMBER: exactly 3 films per category
-- film_id breaks ties, so the result is the same on every run, but it
-- settles a tie by id, not by anything that matters. Two categories have a
-- tie at 3rd place, and ROW_NUMBER drops one film from each:
-- Drama keeps DANCING FEVER and drops STREETCAR INTENTIONS (100 rentals
-- each), Horror keeps GILMORE BOILED and drops RIDGEMONT SUBMARINE (102
-- each). No warning is given. 2b keeps them.

WITH film_rentals AS (
    SELECT
        i.film_id,
        COUNT(*) AS total_rentals
    FROM rental AS r
    JOIN inventory AS i
        ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
),
ranked_films AS (
    SELECT
        c.category_id,
        c.name AS category,
        fr.film_id,
        f.title,
        fr.total_rentals,
        ROW_NUMBER() OVER (
            PARTITION BY c.category_id
            ORDER BY fr.total_rentals DESC, fr.film_id
        ) AS film_rank
    FROM film_rentals AS fr
    JOIN film AS f
        ON fr.film_id = f.film_id
    JOIN film_category AS fc
        ON fr.film_id = fc.film_id
    JOIN category AS c
        ON fc.category_id = c.category_id
)
SELECT
    category,
    film_rank,
    film_id,
    title,
    total_rentals
FROM ranked_films
WHERE film_rank <= 3
ORDER BY
    category,
    category_id,
    film_rank;
-- 48 rows, 16 categories x 3. Action: CAT CONEHEADS (123), SEABISCUIT PUNK
-- (96), IDOLS SNATCHERS (92)

-- 2b. RANK: top 3 with ties (added in review)
-- The same steps, ranked both ways. Filtering on RANK keeps every film tied
-- at 3rd place; row_num shows what ROW_NUMBER would have said, and the two
-- rows with row_num 4 are the films 2a dropped. RANK's ORDER BY has no
-- tie-breaker on purpose: it would break the very ties RANK should keep.
-- Neither answer is wrong. Decide whether ties count before writing any
-- "top n", the same question as ctes.sql 6.

WITH film_rentals AS (
    SELECT
        i.film_id,
        COUNT(*) AS total_rentals
    FROM rental AS r
    JOIN inventory AS i
        ON r.inventory_id = i.inventory_id
    GROUP BY i.film_id
),
ranked_films AS (
    SELECT
        c.category_id,
        c.name AS category,
        fr.film_id,
        f.title,
        fr.total_rentals,
        RANK() OVER (
            PARTITION BY c.category_id
            ORDER BY fr.total_rentals DESC
        ) AS film_rank,
        ROW_NUMBER() OVER (
            PARTITION BY c.category_id
            ORDER BY fr.total_rentals DESC, fr.film_id
        ) AS row_num
    FROM film_rentals AS fr
    JOIN film AS f
        ON fr.film_id = f.film_id
    JOIN film_category AS fc
        ON fr.film_id = fc.film_id
    JOIN category AS c
        ON fc.category_id = c.category_id
)
SELECT
    category,
    film_rank,
    row_num,
    film_id,
    title,
    total_rentals
FROM ranked_films
WHERE film_rank <= 3
ORDER BY
    category,
    category_id,
    row_num;
-- 50 rows: Drama and Horror have four films each; their row_num 4 films are
-- STREETCAR INTENTIONS and RIDGEMONT SUBMARINE


-- 3. Actors ranked by film count within each category ------------------------
-- DENSE_RANK, so actors with the same count share a rank and the next count
-- gets the next rank (1, 1, 2, 2, 3). RANK would answer "how many actors are
-- ahead of me?" instead: in Action it climbs to 179, DENSE_RANK only to 10.
-- Window functions run after GROUP BY, so OVER can order by an aggregate.
-- The subquery isn't required: DENSE_RANK() OVER (PARTITION BY
-- c.category_id ORDER BY COUNT(*) DESC) works in the same SELECT as the
-- GROUP BY. The subquery is easier to read, so it stays.
-- Grouping by a.actor_id and still selecting the actor's names works
-- because actor_id is actor's primary key: each group has one name.
-- Review:
--   * actor_id added to the output: actors 101 and 110 are both SUSAN
--     DAVIS, and both appear in all 16 categories.
--   * film dropped from the joins: film_actor.film_id joins film_category
--     directly, and film added nothing.
--   * COUNT(*) instead of COUNT(DISTINCT f.film_id): (actor_id, film_id) and
--     (film_id, category_id) are both primary keys, so a film can't repeat
--     within one actor and category. Same counts in all 3,149 groups.
--   * ORDER BY dropped from the subquery (only the outer ORDER BY decides
--     the output order); actor_id ends the final one, since actors tied on
--     a rank could otherwise come out in any order.
--   * rank renamed actor_rank (rank is also a function's name); name shown
--     as category.

SELECT
    category,
    actor_id,
    actor_name,
    film_count,
    DENSE_RANK() OVER (
        PARTITION BY category_id
        ORDER BY film_count DESC
    ) AS actor_rank
FROM (
    SELECT
        c.category_id,
        c.name AS category,
        a.actor_id,
        CONCAT(a.first_name, ' ', a.last_name) AS actor_name,
        COUNT(*) AS film_count
    FROM actor AS a
    JOIN film_actor AS fa
        ON a.actor_id = fa.actor_id
    JOIN film_category AS fc
        ON fa.film_id = fc.film_id
    JOIN category AS c
        ON fc.category_id = c.category_id
    GROUP BY
        c.category_id,
        c.name,
        a.actor_id
) AS actor_film_counts
ORDER BY
    category,
    category_id,
    actor_rank,
    actor_id;
-- 3,149 rows. Action starts with ANGELA HUDSON (65) and MATTHEW CARREY
-- (181), both at rank 1 with 10 films


-- 4. Month-over-month revenue change per store -------------------------------
-- monthly_revenue is tier-1 query 3: a store earns the payments for its own
-- copies, and months are cut in UTC. LAG(revenue) then brings the previous
-- month's revenue onto each row, separately for each store (PARTITION BY
-- store_id). A store's first month has no previous row, so previous_revenue
-- and the change are NULL there.
-- LAG looks one row back, not one calendar month back. If a store had a
-- month with no payments, LAG would compare with two months earlier. Both
-- stores have all 55 months here; when there are gaps, build the months
-- first with generate_series and LEFT JOIN the revenue onto them.
-- January 2022 only has payments from the 23rd, so February's jump
-- (+3,497.80 for store 1) is the calendar, not growth.
-- GROUP BY txn_month uses the SELECT alias. PostgreSQL allows that;
-- standard SQL doesn't.
-- Review: the two nested subqueries became named steps; previous_month
-- renamed previous_revenue (it holds revenue, not a month); pct_change
-- added, with NULLIF so a month with zero revenue can't divide by zero.

WITH monthly_revenue AS (
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
),
with_previous AS (
    SELECT
        txn_month,
        store_id,
        revenue,
        LAG(revenue) OVER (
            PARTITION BY store_id
            ORDER BY txn_month
        ) AS previous_revenue
    FROM monthly_revenue
)
SELECT
    TO_CHAR(txn_month, 'FMMonth YYYY') AS month_year,
    store_id,
    revenue,
    previous_revenue,
    revenue - previous_revenue AS revenue_change,
    ROUND(
        100.0 * (revenue - previous_revenue) / NULLIF(previous_revenue, 0),
        1
    ) AS pct_change
FROM with_previous
ORDER BY
    txn_month,
    store_id;
-- 110 rows, 2 stores x 55 months. February 2022, store 1: 5,121.02 against
-- 1,623.22, +3,497.80 (+215.5%)


-- 5. Days between a customer's consecutive rentals ---------------------------
-- LAG(rental_date) puts the customer's previous rental time on each row.
-- PARTITION BY customer_id starts again for every customer, so each first
-- rental gets NULL: no previous rental exists (997 of them, one for each
-- customer who rented).
-- Subtracting two timestamps gives an INTERVAL, such as '2 days 23:04:46'.
-- EXTRACT(EPOCH FROM interval) turns it into seconds, dividing by 86400
-- turns seconds into fractional days, and ROUND(value, 1) keeps one
-- decimal. (EXTRACT returns numeric since PostgreSQL 14, which is why
-- ROUND(x, 1) is allowed here.)
-- EPOCH measures the real time that passed. Casting both timestamps to
-- DATE ignores the time of day and counts calendar days instead, and those
-- depend on the session time zone: for 18,100 of the 50,808 gaps the
-- whole-day count differs between UTC and IST.
-- TO_CHAR is for display only. Calculate and sort on the real timestamps.
--
-- Tie-breaker: ORDER BY rental_date, rental_id (inside OVER and at the end)
-- makes the order deterministic. When two rentals have the same
-- rental_date, rental_date alone can't say which comes first; rental_id
-- can, because it is unique. Example:
--   rental 101 -> Jan 1, 10:00 AM
--   rental 102 -> Jan 1, 10:00 AM
-- Without rental_id, LAG may treat either one as first. With it, 101 comes
-- before 102. This isn't hypothetical: 24 rentals have exactly the same
-- rental_date as the customer's previous rental. They show days_between
-- 0.0, as does any gap under 72 minutes after rounding (712 rows in all).
-- Important: a tie-breaker makes the result consistent and repeatable. It
-- doesn't tell you which rental really happened first; the timestamps say
-- they happened at the same moment.
-- Review: formatting only. The subquery became a CTE so the query reads top
-- to bottom.

WITH rental_history AS (
    SELECT
        customer_id,
        rental_id,
        rental_date,
        LAG(rental_date) OVER (
            PARTITION BY customer_id
            ORDER BY rental_date, rental_id
        ) AS previous_rental
    FROM rental
)
SELECT
    customer_id,
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
        EXTRACT(EPOCH FROM (rental_date - previous_rental)) / 86400,
        1
    ) AS days_between
FROM rental_history
ORDER BY
    customer_id,
    rental_date,
    rental_id;
-- 51,805 rows. Customer 1's first rental (76) has NULLs; the next one (573)
-- came 3.0 days later


-- 6. Running spend per customer ----------------------------------------------
-- SUM(amount) OVER (PARTITION BY customer ORDER BY time) adds up each
-- customer's payments in time order, so every row shows the total so far.
-- Two ORDER BYs, two jobs. The one inside OVER decides the order in which
-- amounts are added up; the one at the end decides how the rows are shown.
-- Use the same chronological order in both, or the running total seems to
-- jump around.
-- Order by payment_date first, then payment_id as a tie-breaker for
-- payments at the same moment. payment_id isn't in time order (customer
-- 1's first payment is 29000, the next 28999), so it only makes the order
-- repeatable.
-- ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW adds the payments one at
-- a time, from the customer's first payment up to the current one. With a
-- unique ORDER BY like this one, the default frame gives the same totals;
-- the difference shows up as soon as the ORDER BY has ties, see 7.
-- Review: running_total was cummilitive_amount, and paid_on was
-- payment_date. An alias with a column's name is a trap: in ORDER BY a bare
-- name means the output column first, so ORDER BY payment_date would have
-- sorted the text, putting 'Apr 12, 2022' before 'Feb 4, 2022'. The first
-- version sorted correctly only because it wrote p.payment_date. Customer
-- columns now come first.

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    p.payment_id,
    TO_CHAR(
        p.payment_date AT TIME ZONE 'UTC',
        'Mon FMDD, YYYY'
    ) AS paid_on,
    p.amount,
    SUM(p.amount) OVER (
        PARTITION BY c.customer_id
        ORDER BY p.payment_date, p.payment_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_total
FROM customer AS c
JOIN payment AS p
    ON c.customer_id = p.customer_id
ORDER BY
    c.customer_id,
    p.payment_date,
    p.payment_id;
-- 51,061 rows. MARY SMITH (1) goes 4.99, 9.98, 13.97, 18.96, ...


-- 7. The default frame trap (added in review) --------------------------------
-- Session 3's trap. With ORDER BY inside OVER and no frame written, the
-- frame is RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW. RANGE works
-- by value, so "current row" means this row and every row tied with it.
-- Customer 781 made two payments at the same moment, 2026-07-28 23:59:59
-- (seven customers did, all at that last timestamp in the data):
--   * default_frame orders by payment_date alone, so both tied rows get the
--     total after both: 34.87 twice, and 31.88 never appears.
--   * rows_frame counts rows, so it does reach 31.88, then 34.87. Which of
--     the two tied rows comes first is still arbitrary, so the 31.88 can
--     land on either one.
--   * with_tiebreaker adds payment_id. Nothing is tied any more, so even
--     the default frame steps one row at a time, in a fixed order.
--   * LAST_VALUE "looks broken": the default frame ends at the current
--     row, so the last value in it is the row's own amount. To get the
--     customer's last payment, stretch the frame to UNBOUNDED FOLLOWING.
--     FIRST_VALUE works either way, because the frame always starts at the
--     first row.

SELECT
    payment_id,
    payment_date AT TIME ZONE 'UTC' AS paid_at_utc,
    amount,
    SUM(amount) OVER (
        ORDER BY payment_date
    ) AS default_frame,
    SUM(amount) OVER (
        ORDER BY payment_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS rows_frame,
    SUM(amount) OVER (
        ORDER BY payment_date, payment_id
    ) AS with_tiebreaker,
    FIRST_VALUE(amount) OVER (
        ORDER BY payment_date, payment_id
    ) AS first_amount,
    LAST_VALUE(amount) OVER (
        ORDER BY payment_date, payment_id
    ) AS last_default,
    LAST_VALUE(amount) OVER (
        ORDER BY payment_date, payment_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_amount
FROM payment
WHERE customer_id = 781
ORDER BY
    payment_date,
    payment_id;
-- 13 rows. Last two rows: default_frame 34.87 and 34.87, with_tiebreaker
-- 31.88 and 34.87. last_default repeats each row's amount; last_amount is
-- 2.99 everywhere, the amount of the last payment (102062)


-- 8. Year-to-date revenue and each month's share of its year (added) ---------
-- One window with ORDER BY and one without, over the same partition:
--   SUM(revenue) OVER (PARTITION BY year ORDER BY month)
--     a running total that starts again every January
--   SUM(revenue) OVER (PARTITION BY year)
--     the whole year's total, repeated on every month of that year
-- This is the GROUP BY difference in action: every month keeps its own row
-- and still knows its year's total. txn_month is unique, so the default
-- frame is safe here (7).
-- The data is lopsided in 2022: February to July bring in about 9,700 to
-- 11,400 a month, August only 278.17, and from September revenue settles
-- near 2,000 a month. 2026 stops in July, so its shares are of seven
-- months.

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', payment_date AT TIME ZONE 'UTC') AS txn_month,
        SUM(amount) AS revenue
    FROM payment
    GROUP BY txn_month
)
SELECT
    TO_CHAR(txn_month, 'FMMonth YYYY') AS month_year,
    revenue,
    SUM(revenue) OVER (
        PARTITION BY DATE_TRUNC('year', txn_month)
        ORDER BY txn_month
    ) AS year_to_date,
    ROUND(
        100.0 * revenue
        / SUM(revenue) OVER (PARTITION BY DATE_TRUNC('year', txn_month)),
        1
    ) AS pct_of_year
FROM monthly_revenue
ORDER BY txn_month;
-- 55 rows. Each December's year_to_date is the year's total (76,367.30 for
-- 2022), and a year's pct_of_year adds up to 100, give or take rounding


-- 9. Three-month moving average of revenue per store (added in review) -------
-- A frame that slides: each row averages its own month and up to two months
-- before it, which smooths out a single odd month.
-- RANGE BETWEEN INTERVAL '2 months' PRECEDING AND CURRENT ROW works by the
-- calendar: it takes the rows whose month is at most two months before
-- this one. ROWS BETWEEN 2 PRECEDING AND CURRENT ROW would take the two
-- rows before, which is the same only while no month is missing (true
-- here).
-- months_in_avg shows the frame is shorter at the start: January 2022
-- averages one month and February two, so those aren't 3-month averages.
-- WINDOW last_3_months names the window once for both functions.

WITH monthly_revenue AS (
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
)
SELECT
    TO_CHAR(txn_month, 'FMMonth YYYY') AS month_year,
    store_id,
    revenue,
    ROUND(AVG(revenue) OVER last_3_months, 2) AS moving_avg_3m,
    COUNT(*) OVER last_3_months AS months_in_avg
FROM monthly_revenue
WINDOW last_3_months AS (
    PARTITION BY store_id
    ORDER BY txn_month
    RANGE BETWEEN INTERVAL '2 months' PRECEDING AND CURRENT ROW
)
ORDER BY
    store_id,
    txn_month;
-- 110 rows. Store 1, March 2022: the average of 1,623.22, 5,121.02 and
-- 5,479.06 is 4,074.43


-- 10. Paying customers in four spend quartiles (added in review) -------------
-- NTILE(4) deals the ordered rows into 4 groups of nearly equal size: 997
-- customers become 250, 249, 249 and 249 (the first groups take the extra).
-- It splits by row count, not by value, so equal totals can land in
-- different quartiles: three customers spent exactly 206.38 (376, 443,
-- 596), and they are split between quartiles 2 and 3. customer_id in the
-- ORDER BY at least makes that split repeatable.
-- The outer query is a GROUP BY over the window's result. In
-- SUM(SUM(total)) OVER (), the inner SUM is a quartile's revenue and the
-- outer one adds all four: a window over an aggregate, which works because
-- window functions run after GROUP BY.
-- For percentiles rather than buckets, PERCENT_RANK() and CUME_DIST() give
-- each row's position as a fraction between 0 and 1.

WITH customer_totals AS (
    SELECT
        customer_id,
        SUM(amount) AS total
    FROM payment
    GROUP BY customer_id
),
quartiles AS (
    SELECT
        customer_id,
        total,
        NTILE(4) OVER (ORDER BY total DESC, customer_id) AS spend_quartile
    FROM customer_totals
)
SELECT
    spend_quartile,
    COUNT(*) AS customers,
    MAX(total) AS highest,
    MIN(total) AS lowest,
    SUM(total) AS revenue,
    ROUND(100.0 * SUM(total) / SUM(SUM(total)) OVER (), 1) AS pct_of_revenue
FROM quartiles
GROUP BY spend_quartile
ORDER BY spend_quartile;
-- 4 rows. The top quartile (250 customers) brings in 39.4% of the revenue,
-- the bottom one 6.2%


-- 11. Longest streaks of consecutive rental months (added in review) ---------
-- Gaps and islands. Islands are unbroken runs, here months in a row with
-- at least one rental; gaps are the breaks between them. The trick: number
-- each customer's months 1, 2, 3, ... (rn) and subtract that from a month
-- counter (month_no). Inside a run both go up by 1, so the difference stays
-- the same; after a gap month_no jumps ahead and the difference changes.
-- GROUP BY the difference, and each group is one streak. Customer 70:
--   month    month_no  rn  month_no - rn
--   2022-09     24273   5          24268
--   2022-10     24274   6          24268   May to Oct 2022: one island
--   2022-12     24276   7          24269   November missing: new island
--   2023-01     24277   8          24269
-- month_no = year * 12 + month, so consecutive months differ by exactly 1,
-- across New Year too (December 2022 is 24276, January 2023 is 24277).
-- Months are cut in UTC. The data has no rentals at all in March and April
-- 2022, so no streak can cross them.
-- WITH TIES keeps both streaks tied at 16 months for 10th place. As in
-- ctes.sql 6, its ORDER BY has no tie-breaker; the final ORDER BY has one.

WITH rental_months AS (
    SELECT DISTINCT
        customer_id,
        DATE_TRUNC('month', rental_date AT TIME ZONE 'UTC') AS rental_month
    FROM rental
),
numbered AS (
    SELECT
        customer_id,
        rental_month,
        EXTRACT(YEAR FROM rental_month) * 12
            + EXTRACT(MONTH FROM rental_month) AS month_no,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY rental_month
        ) AS rn
    FROM rental_months
),
streaks AS (
    SELECT
        customer_id,
        MIN(rental_month) AS first_month,
        MAX(rental_month) AS last_month,
        COUNT(*) AS months
    FROM numbered
    GROUP BY
        customer_id,
        month_no - rn
),
longest AS (
    SELECT
        customer_id,
        first_month,
        last_month,
        months
    FROM streaks
    ORDER BY months DESC
    FETCH FIRST 10 ROWS WITH TIES
)
SELECT
    l.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    TO_CHAR(l.first_month, 'Mon YYYY') AS streak_start,
    TO_CHAR(l.last_month, 'Mon YYYY') AS streak_end,
    l.months
FROM longest AS l
JOIN customer AS c
    ON l.customer_id = c.customer_id
ORDER BY
    l.months DESC,
    l.customer_id;
-- 11 rows. CHRISTINA RAMIREZ (70) rented every month from Jun 2023 to Dec
-- 2024: 19 months in a row
