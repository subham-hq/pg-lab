-- 06-dates-and-times.sql: NOW(), intervals, EXTRACT, AGE
-- Source: Amigoscode PostgreSQL course (freeCodeCamp)
-- Docs:   https://www.postgresql.org/docs/current/functions-datetime.html
--         https://www.postgresql.org/docs/current/datatype-datetime.html

-- Reset to a known state
\ir ../data/person.sql


-- Timestamps and dates ------------------------------------------------------

SELECT NOW();            -- timestamp with time zone (timestamptz)
SELECT NOW()::DATE;      -- just the date; CURRENT_DATE gives the same
SELECT NOW()::TIME;      -- just the time of day


-- Adding and subtracting ----------------------------------------------------

SELECT NOW() - INTERVAL '1 YEAR';
SELECT NOW() - INTERVAL '1 YEAR 3 MONTHS 10 DAYS';
SELECT NOW()::DATE + INTERVAL '10 DAYS';    -- DATE + INTERVAL gives a timestamp
SELECT NOW()::DATE + 10;                    -- DATE + integer adds days and stays a DATE


-- Extracting fields ---------------------------------------------------------

SELECT EXTRACT(YEAR FROM NOW());
SELECT EXTRACT(CENTURY FROM NOW());
SELECT EXTRACT(DAY FROM NOW());      -- day of the month
SELECT EXTRACT(DOW FROM NOW());      -- day of the week: 0 = Sunday ... 6 = Saturday


-- AGE -----------------------------------------------------------------------

-- AGE(later, earlier) returns an interval in years, months and days.
-- NOW() includes the time of day, so the result has hours and seconds too.
SELECT first_name, last_name, gender, AGE(NOW(), date_of_birth) AS age
FROM person
ORDER BY id
LIMIT 10;

-- With one argument, AGE counts up to today at midnight: whole days only.
-- EXTRACT pulls out just the years.
SELECT first_name, date_of_birth,
       AGE(date_of_birth)                    AS age,
       EXTRACT(YEAR FROM AGE(date_of_birth)) AS age_in_years
FROM person
ORDER BY id
LIMIT 10;


-- Beyond the video ----------------------------------------------------------

-- 1. NOW() is frozen at the start of the transaction: every statement in it
--    sees the same value. clock_timestamp() is the actual current time.
BEGIN;
SELECT NOW(), clock_timestamp();
SELECT pg_sleep(1);
SELECT NOW(), clock_timestamp();    -- NOW() hasn't moved; clock_timestamp() has
COMMIT;

-- 2. timestamptz stores one absolute moment (in UTC internally) and shows it
--    in the session's time zone. The same moment, shown in two zones:
SHOW TIME ZONE;
SET TIME ZONE 'UTC';
SELECT TIMESTAMPTZ '2026-10-01 18:00:00+05:30';    -- 2026-10-01 12:30:00+00
SET TIME ZONE 'Asia/Kolkata';
SELECT TIMESTAMPTZ '2026-10-01 18:00:00+05:30';    -- 2026-10-01 18:00:00+05:30
RESET TIME ZONE;
--    Use timestamptz for anything that happened at a real moment. A plain
--    timestamp has no zone, so 18:00 in Kolkata and 18:00 in London look the same.

-- 3. Months have different lengths, so month arithmetic clamps to the last
--    valid day, and going forward then back doesn't bring you home:
SELECT DATE '2026-01-31' + INTERVAL '1 month';                         -- 2026-02-28 00:00:00
SELECT DATE '2026-01-31' + INTERVAL '1 month' - INTERVAL '1 month';    -- 2026-01-28 00:00:00

-- 4. DATE - DATE is a whole number of days. TIMESTAMP - TIMESTAMP is an interval.
SELECT DATE '2026-12-25' - DATE '2026-10-01';                          -- 85
SELECT TIMESTAMP '2026-12-25 00:00' - TIMESTAMP '2026-10-01 00:00';    -- 85 days

-- 5. A DATE rejects days that don't exist. A TEXT column would accept them.
-- Expected to fail: there's no 30 February
-- SELECT DATE '2026-02-30';
-- ERROR:  date/time field value out of range: "2026-02-30"

-- 6. '01/02/2026' is 2 January under DateStyle MDY and 1 February under DMY.
--    What does your server say?
SHOW DateStyle;
SELECT DATE '01/02/2026';
--    Write dates as 'YYYY-MM-DD'. That format means the same under any setting.

