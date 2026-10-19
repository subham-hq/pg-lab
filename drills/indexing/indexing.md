# Database Indexing in PostgreSQL — Practical Notes

> Based on the video **Database Indexing Explained (with PostgreSQL)** and the accompanying `schema.sql`, `seed.sql`, `queries.sql`, and `demo.sql` files. The goal is to remember *what an index does, why it can make a query faster, and how to prove it with PostgreSQL*.

## 1. Why do databases need indexes?

Imagine a `comments` table containing **1,000,000 rows**. You want to retrieve the comments written by one user:

```sql
SELECT *
FROM comments
WHERE user_id = 1;
```

**Without a suitable index**, PostgreSQL may perform a **Sequential Scan (`Seq Scan`)**: it reads the table's pages and checks rows against `user_id = 1`. This can mean examining a huge amount of data just to find a relatively small set of matching comments.

**With an index on `user_id`**, PostgreSQL has another option: locate matching values in a separate, ordered structure and use their references to find the corresponding table rows. It can avoid examining most unrelated rows.

An index is much like the index at the back of a textbook: instead of reading every page to find one topic, you look up the topic and jump to the relevant pages.

**Important:** An index makes certain *access paths* available; it does not force PostgreSQL to use them. The planner chooses whichever plan it estimates will be cheaper.

## 2. What is a B-tree index?

A **B-tree** is a **balanced, multiway search tree**. Unlike a binary tree, where each node has at most two children, a B-tree node can store multiple keys and guide you toward many child pages.

A tiny illustration (not the exact on-disk PostgreSQL layout):

```text
                    [30 | 60]
                   /    |    \
           values <30  30–59  values >=60
```

To find `50`, PostgreSQL can follow the middle range instead of checking every key. Real index pages contain many more entries, keeping the tree shallow even for large tables.

PostgreSQL creates a **B-tree index by default**:

```sql
CREATE INDEX ix_comments_user_id
ON comments (user_id);
```

A B-tree is especially useful for **equality conditions** (`=`), **ranges** (`<`, `>`, `BETWEEN`), and sometimes satisfying **`ORDER BY`** without an extra sort.

The key distinction is:

- **Table (heap):** stores the actual rows; it is not automatically sorted by the indexed column.
- **Index:** stores searchable keys and references to table rows (tuple IDs), making targeted lookups possible.

This is why a B-tree helps in a database: its broad branching structure reduces the number of storage pages the engine must visit.

## 3. The practice database used in the video files

Your scripts use a simple issue-tracking example:

| Table | Role | Seeded rows |
|---|---|---:|
| `users` | People who create issues or write comments | 100 |
| `issues` | Issues created by users | 10,000 |
| `comments` | Comments attached to issues and users | 1,000,000 |

The relevant `comments` columns are:

```text
id | issue_id | user_id | body | archived | created_at
```

That large `comments` table makes the effect of indexing easier to see.

### Running the supplied scripts safely

Use a **separate practice database**, not your Pagila database: `seed.sql` contains a `TRUNCATE ... RESTART IDENTITY` statement and replaces existing rows in these three practice tables.

On a fresh practice database, `seed.sql` **already creates the tables**, so you do not need to run `schema.sql` first. It then inserts the test data with `generate_series()` and random values.

```sql
-- After executing seed.sql, refresh planner statistics:
ANALYZE users;
ANALYZE issues;
ANALYZE comments;
```

`ANALYZE` helps PostgreSQL estimate how many rows a condition might return, which influences its choice of scan.

**Two file-specific details:**

- `schema.sql` allows `comments.user_id` to be `NULL`, but the table definition inside `seed.sql` declares it `NOT NULL`. Because `seed.sql` uses `CREATE TABLE IF NOT EXISTS`, it will **not change** a table you already created from `schema.sql`. This difference does not change the central indexing lesson.
- `queries.sql` contains `CREATE INDEX` statements **at the bottom**. For a fair before/after experiment, run the test queries first, then create the indexes one at a time. Do not execute the entire file at the beginning.

## 4. Measuring queries with EXPLAIN

Before creating an index, ask PostgreSQL how it executes a query:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM comments
WHERE user_id = 1;
```

Here's what the command means:

- **`EXPLAIN`** shows the plan PostgreSQL chose.
- **`ANALYZE` inside `EXPLAIN`** actually executes the query and records what happened.
- **`BUFFERS`** reports page activity, such as pages read from disk or found in cache.

Watch for these parts of the output:

| Plan detail | What it tells you |
|---|---|
| `Seq Scan` | PostgreSQL checks the table directly. |
| `Index Scan` | PostgreSQL finds entries through an index and visits matching table rows. |
| `Bitmap Index Scan` + `Bitmap Heap Scan` | PostgreSQL collects matching row locations, then visits their table pages in an efficient batch. |
| `Index Only Scan` | PostgreSQL may be able to answer the query mostly from the index, with visibility checks as needed. |
| `cost=...` | The planner's **relative estimated cost**, not milliseconds. |
| `rows=...` / `actual ... rows=...` | Estimated versus observed row counts. |
| `Execution Time` | Time actually spent running the query. |
| `Buffers: shared hit=... read=...` | Pages found in cache versus pages that had to be read. |

**Don't confuse the two commands:** `ANALYZE comments;` updates statistics. `EXPLAIN ANALYZE SELECT ...` executes the `SELECT` and reports the plan and timing.

## 5. Practical experiment #1: Find comments by user

### Before the index

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM comments
WHERE user_id = 1;
```

Without a suitable index, this may show `Seq Scan`.

### Create the index

```sql
CREATE INDEX ix_comments_user_id
ON comments (user_id);
```

### Run the *same* query again

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM comments
WHERE user_id = 1;
```

Now PostgreSQL might use an `Index Scan` or a `Bitmap Heap Scan`. The exact plan depends on how many rows match, table size, and estimated I/O cost.

In this dataset, comments are spread across **100 users**, so an average user has roughly **10,000 comments**. That's about **1% of the table**: an index can help, but the database may still need to fetch many rows because of `SELECT *`.

The `demo.sql` comments note an illustrative improvement of about **20 ms → 5 ms** for a user lookup. Treat that as an observation from the demo, **not a speed PostgreSQL guarantees**.

## 6. Practical experiment #2: COUNT(*) and index-only scans

Your files also test:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM comments
WHERE user_id = 1;
```

With `ix_comments_user_id`, PostgreSQL already has the indexed values needed to identify rows matching `user_id = 1`.

A **count** can be cheaper than `SELECT *` because PostgreSQL does not need to return each comment's `body`, `created_at`, and other columns. In favorable conditions, it can use an **`Index Only Scan`**, reducing visits to the main table.

But “index only” does **not** mean “never touches the table”: PostgreSQL may still need heap visibility checks. Look for `Heap Fetches` in the plan.

The demo records roughly **19 ms → 0.7 ms** for one count query. Again, run it locally and compare your own plans and buffers rather than memorizing the number.

**Key idea:** The kind of data you request matters. `COUNT(*)` and `SELECT *` can have different execution plans even with the same `WHERE` condition.

## 7. Practical experiment #3: Find comments for one issue

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM comments
WHERE issue_id = 1;
```

Create the relevant index:

```sql
CREATE INDEX ix_comments_issue_id
ON comments (issue_id);
```

Then rerun the query and compare its scan and execution time.

Comments are spread across **10,000 issues**, so an issue has about **100 comments on average**. This is more selective than filtering by one of 100 users. The index can be especially effective when only a small number of rows match.

The demo comments include an approximate **18 ms → 0.1 ms** improvement for the issue lookup. Your timings may differ.

**Why this is useful:** The fewer rows a filter returns, the more attractive a targeted index lookup often becomes.

## 8. Practical experiment #4: Two filters and a composite index

Your fourth query adds another condition:

```sql
SELECT COUNT(*)
FROM comments
WHERE issue_id = 1
  AND user_id = 2;
```

PostgreSQL has several possibilities. It might use the `issue_id` index, use the `user_id` index, combine bitmap results from both indexes, or choose another plan. The planner estimates the cheapest route.

If you commonly filter by these columns **together**, a **composite (multicolumn) index** can be useful:

```sql
CREATE INDEX ix_comments_issue_user
ON comments (issue_id, user_id);
```

Think of its ordering as:

1. Organize entries first by `issue_id`.
2. Within each issue, organize them by `user_id`.

This lets PostgreSQL narrow the search efficiently for `issue_id = 1 AND user_id = 2`.

**Column order matters.** An index on `(issue_id, user_id)` is usually most effective when the query constrains `issue_id` (possibly also `user_id`). It is not interchangeable with `(user_id, issue_id)` for every workload. Modern PostgreSQL can sometimes use later columns without the leading column, but that is not the usual ideal access pattern.

## 9. Practical experiment #5: Filters + date range + sorting

This is the most interesting query in your files:

```sql
SELECT *
FROM comments
WHERE issue_id = 1
  AND user_id = 2
  AND created_at >= NOW() - INTERVAL '1 month'
ORDER BY created_at DESC;
```

You're asking PostgreSQL to:

1. Find one specific issue.
2. Keep comments written by one specific user.
3. Keep comments from the last month.
4. Show the newest ones first.

A matching index is:

```sql
CREATE INDEX ix_comments_issue_id_user_id_created_at
ON comments (issue_id, user_id, created_at DESC);
```

Why this order?

- `issue_id` → equality filter (`=`)
- `user_id` → another equality filter (`=`)
- `created_at` → date range (`>=`) and descending order

With the first two columns fixed, PostgreSQL can scan the relevant timestamp range in index order. That **may avoid** scanning unrelated rows and doing a separate sort.

Your `queries.sql` version uses `created_at DESC`; `demo.sql` creates the same three-column index with the default ascending order. Both can be useful: PostgreSQL can scan a B-tree **backward**, so descending output is not automatically a reason to rebuild an otherwise suitable ascending index.

### A caution about these exact values

The seed spreads one million comments randomly across 10,000 issues and 100 users. So the combination `(issue_id = 1, user_id = 2)` has **roughly one matching comment on average across the whole year**, often none in the last month.

That means a very small runtime, such as the **21 ms → 0.6 ms → 0.02 ms** progression written in `demo.sql`, may partly reflect a query returning **zero or one row**, plus caching and other differences. Always check `actual rows`, and use representative queries when benchmarking.

## 10. Why PostgreSQL sometimes ignores an index

Having an index doesn't make every query faster:

- **Small tables:** Reading the whole table may cost less than following an index.
- **Filters matching most rows:** Many index hits plus many heap reads can cost more than one table scan.
- **Unhelpful column order:** A composite index may not line up well with the query's leading conditions.
- **Outdated statistics:** The planner may estimate the number of matching rows badly until `ANALYZE` runs.
- **`SELECT *`:** The index may find row locations quickly, but fetching all the other column values still takes work.

**A `Seq Scan` is not always a mistake.** It can be the correct choice for a broad query.

## 11. Measuring fairly (rather than trusting one timing)

Use the **same SQL** before and after indexing, and inspect both the plan and the work it did:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM comments
WHERE issue_id = 1;
```

Compare:

- The chosen scan (`Seq Scan`, `Index Scan`, `Bitmap Heap Scan`, etc.).
- Estimated rows versus actual rows.
- `Execution Time`.
- Buffer activity (`hit`, `read`), which helps explain differences between warm and cold runs.

Run a test more than once when making performance claims: repeated queries can be faster because more pages are cached.

**Remember:** `EXPLAIN ANALYZE` really runs the query. For `UPDATE`, `DELETE`, or `INSERT`, it can change data unless you manage the transaction and roll it back.

## 12. Indexes cost storage and write performance

Indexes are extra structures that PostgreSQL maintains. They can speed up reads, but they take disk space, and inserts/updates/deletes may require extra work.

Your `demo.sql` includes a query to inspect index sizes:

```sql
SELECT
    schemaname,
    relname AS table_name,
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
ORDER BY pg_relation_size(indexrelid) DESC;
```

A few practical rules:

- Index columns that appear in **frequent, important query filters or ordering**, not every column by default.
- Compare actual plans and timings before deciding whether an index is worthwhile.
- A `PRIMARY KEY` or `UNIQUE` constraint automatically gets a supporting unique index in PostgreSQL. A `FOREIGN KEY` on the *referencing* column does **not** automatically create its own index.
- Extra indexes can become redundant. Keep the ones that help your real workload.

## 13. File notes and common gotchas

- `demo.sql` begins with `DROP INDEX ...` statements. On a fresh database, those fail if the named index doesn't exist. Use `DROP INDEX IF EXISTS index_name;` when resetting a demo.
- If you already ran the index statements in `queries.sql`, you're **not** comparing indexed versus unindexed queries anymore. Check existing indexes first or reset your disposable lab.
- `schema.sql` and `seed.sql` overlap in table creation. On a fresh lab database, **`seed.sql` alone is sufficient** for creating and populating the tables.
- An index named `ix_comments_issue_id_user_id_created_at` is just a name; PostgreSQL decides the indexed columns from the `ON comments (...)` clause.

To see your indexes in `psql`:

```sql
\d comments
```

Or use the catalog:

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'comments';
```

## The idea to remember

**Indexing is about giving PostgreSQL a cheaper way to find data.** A B-tree keeps searchable keys organized; `EXPLAIN (ANALYZE, BUFFERS)` shows whether PostgreSQL used that structure and whether it actually helped. Good index design begins with the **queries you run most often**, not with adding an index to every column.

---

**Source material:** Hussein Nasser, *Database Indexing Explained (with PostgreSQL)* — <https://youtu.be/teMXE6hzva0>; your `schema.sql`, `seed.sql`, `queries.sql`, and `demo.sql`. Timings shown above are annotations in `demo.sql`, not measurements taken for these notes.

**PostgreSQL references:** [Using EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html) · [B-tree Indexes](https://www.postgresql.org/docs/current/btree.html) · [Multicolumn Indexes](https://www.postgresql.org/docs/current/indexes-multicolumn.html)
