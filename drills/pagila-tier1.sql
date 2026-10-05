-- Cold, 8 queries: top 10 customers by payments · films never rented · revenue per store per month · actors in 30+ films ·
-- films per category · customers who rented in only one month · late returns · most-rented film per category

-- top 10 customers by payments

SELECT c.customer_id AS CUST_ID,
    c.first_name || ' ' || c.last_name AS CUSTOMER_NAME,
    SUM(p.amount) AS TOTAL_AMOUNT
FROM payment AS p
JOIN customer AS c
    ON p.customer_id = c.customer_id
GROUP BY
    c.customer_id,
    c.first_name,
    c.last_name
ORDER BY TOTAL_AMOUNT DESC
LIMIT 10;


-- films never rented

SELECT f.title AS TITLE
FROM film AS f
WHERE NOT EXISTS (
    SELECT 1
    FROM inventory AS i
    JOIN rental AS r
        ON r.inventory_id = i.inventory_id
    WHERE i.film_id = f.film_id 
)
ORDER BY TITLE;

-- revenue per store per month
SELECT
    TO_CHAR(txn_month, 'Month YYYY') AS month_year,
    store_id,
    revenue
FROM (
    SELECT
        DATE_TRUNC('month', p.payment_date) AS txn_month,
        st.store_id,
        SUM(p.amount) AS revenue
    FROM payment AS p
    JOIN staff AS st
        ON p.staff_id = st.staff_id
    GROUP BY
        DATE_TRUNC('month', p.payment_date),
        st.store_id
) AS monthly_revenue
ORDER BY
    store_id,
    txn_month;

-- actors in 30+ films

SELECT
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
ORDER BY film_count DESC;

-- films per category

SELECT c.name AS category,
    COUNT(*) AS no_of_films
FROM category AS c
JOIN film_category as fc
    ON c.category_id = fc.category_id
GROUP BY
    c.category_id,
    c.name
ORDER BY c.name;

-- customers who rented in only one month

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
    DISTINCT DATE_TRUNC('month', r.rental_date)
) = 1;

-- late returns

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
    r.rental_date + f.rental_duration * INTERVAL '1 day';

-- most-rented film per category

WITH film_rentals AS (
    SELECT
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
        c.name,
        f.film_id,
        f.title
),
ranked_films AS (
    SELECT
        category,
        title,
        rental_count,
        RANK() OVER (
            PARTITION BY category
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
ORDER BY category;