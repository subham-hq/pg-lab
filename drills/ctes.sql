-- Find all films whose length is greater than the average length of all films

-- Using Nested Subquery

SELECT film_id, title, length FROM film WHERE length > (SELECT AVG(length) FROM film);

-- Using CTE

WITH average_length AS (
    SELECT AVG(length) AS avg_length
    FROM film
)
SELECT film_id, title, length
FROM film
WHERE length > (
    SELECT avg_length
    FROM average_length
);

-- Find all customers who have rented at least one film in the Horror category

-- Using IN

SELECT CONCAT(first_name, ' ', last_name) AS full_name
FROM customer
WHERE customer_id
IN (
    SELECT customer_id
    FROM rental
    WHERE inventory_id
    IN (
        SELECT inventory_id
        FROM inventory
        WHERE film_id
        IN (
            SELECT film_id
            FROM film_category
            WHERE category_id
            IN (
                SELECT category_id
                FROM category
                WHERE name = 'Horror'
            )
        )
    )
)
ORDER BY full_name;

-- Using EXISTS

SELECT CONCAT(first_name, ' ', last_name) AS full_name
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
                SELECT category_id
                FROM category AS c
                WHERE fc.category_id = c.category_id AND name = 'Horror'
            )
        )
    )
)
ORDER BY full_name;

-- Find the most recent rental made by each customer (Correlated Subquery)

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


-- Write a PostgreSQL query that generates a series of dates from January 1, 2026, to January 10, 2026, using a recursive CTE.

WITH RECURSIVE dates AS (
    SELECT '2026-01-01'::date AS d
    UNION ALL
    SELECT (d + INTERVAL '1 day')::date FROM dates WHERE d < '2026-01-10'
)
SELECT * FROM dates;

-- Find customers whose total payment amount is greater than the average total spending per paying customer.

WITH customer_totals AS (SELECT customer_id, SUM(amount) as total
        FROM payment
        GROUP BY customer_id
        )
SELECT ct.customer_id, CONCAT(c.first_name,' ', c.last_name) AS full_name, ct.total
FROM customer_totals AS ct
JOIN customer AS c
ON ct.customer_id = c.customer_id
WHERE total > (SELECT AVG(total) AS average
    FROM customer_totals
);

-- Find the 10 most frequently rented films in the Pagila database

SELECT i.film_id, f.title, COUNT(*) AS total_rentals
FROM rental AS r
JOIN inventory AS i
ON
    r.inventory_id = i.inventory_id
JOIN film AS f
ON
    i.film_id = f.film_id
GROUP BY
    i.film_id,
    f.title
ORDER BY
    total_rentals DESC
LIMIT 10;

WITH total_rentals AS (
    SELECT i.film_id, COUNT(*) AS total_rentals
    FROM rental AS r
    JOIN inventory AS i
    ON
        r.inventory_id = i.inventory_id
    GROUP BY
        i.film_id
)
SELECT tr.film_id, f.title, tr.total_rentals
FROM total_rentals AS tr
JOIN film AS f
ON
    tr.film_id = f.film_id
ORDER BY tr.total_rentals DESC
LIMIT 10;