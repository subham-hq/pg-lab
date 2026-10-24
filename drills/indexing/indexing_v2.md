# PostgreSQL Indexing — Indexing I & II

> **Readable reference notes · PostgreSQL 18 · Sessions 6–7**  
> Based on *PostgreSQL — Watch · Read · Test* (pages 2–3), the original `indexing.md`, and the `schema.sql`, `seed.sql`, `queries.sql`, and `demo.sql` practice files. These notes cover both sessions in one place, following the progression **why indexes exist → how PostgreSQL uses them → how to choose more advanced indexes → how to prove the benefit**.

## 1. Why do databases need an index?

Imagine a `comments` table containing **1,000,000 comments**. You ask for all comments on one issue:

```sql
SELECT *
FROM comments
WHERE issue_id = 1;
```

Without a suitable index, PostgreSQL may read through the table and check rows individually. This is a **sequential scan (`Seq Scan`)**. It can be expensive when a million rows exist but only a hundred match.

An **index** is a separate data structure that keeps selected values organized so the database can find matching rows without scanning most of the table. Think of the index at the back of a textbook: it tells you *where* to look instead of making you read every page.

```sql
CREATE INDEX ix_comments_issue_id
ON comments (issue_id);
```

This does **not** rearrange the actual `comments` table, and it does **not** guarantee every query will use the index. It simply gives the PostgreSQL planner another way to access the data.

**The guiding question:** *Does the index save more work than it costs to consult?*

## 2. B-tree: the default PostgreSQL index

A **B-tree** is a balanced, **multiway** search tree—not a binary tree. A binary-tree node has at most two children; a B-tree node can guide searches toward many different ranges of values.

```text
                 [30 | 60]
                 /   |   \
             < 30  30–59  >= 60
```

To find 45, the search moves to the middle range instead of examining every value. Real PostgreSQL B-tree pages contain many entries and the tree remains relatively shallow. Its leaf entries point to table rows using tuple locations. The structure is designed to avoid unnecessary storage-page reads.

By default, PostgreSQL uses a B-tree when you write `CREATE INDEX` without specifying a type:

```sql
CREATE INDEX ix_comments_created_at
ON comments (created_at);
-- Equivalent index-method choice: USING btree
```

B-trees are generally helpful for:

| Query pattern | Example |
|---|---|
| Equality | `WHERE issue_id = 20` |
| Range | `WHERE created_at >= '2026-01-01'` |
| Ordered retrieval | `ORDER BY created_at DESC LIMIT 50` |
| Prefix of a useful multicolumn index | `WHERE issue_id = 20 AND user_id = 5` |

They are **not automatically best for every kind of search**. For example, a regular B-tree is not a general substitute for specialized full-text or JSONB indexing.

### Table data versus index data

- **Heap (table):** where PostgreSQL stores the actual rows.
- **Index:** stores searchable keys and references to those rows.
- **Index Scan:** finds matches through the index, then fetches required table columns from the heap.

PostgreSQL indexes are separate from the heap. They do **not** make the table physically sorted in B-tree order. This is different from the clustered-primary-key organization used by some other database engines.

## 3. Key columns versus non-key columns

An index is **not limited to primary-key columns**. You can index an ordinary column if your queries benefit from it:

```sql
-- Primary key: PostgreSQL creates a unique index automatically.
CREATE TABLE example_users (
    id bigint PRIMARY KEY,
    email text NOT NULL UNIQUE,
    display_name text NOT NULL
);

-- display_name is not a key, but it can still be indexed.
CREATE INDEX ix_example_users_display_name
ON example_users (display_name);
```

Important differences:

| Concept | Purpose |
|---|---|
| `PRIMARY KEY` | Uniquely identifies rows and cannot be NULL; PostgreSQL creates an enforcing unique index |
| `UNIQUE` | Prevents duplicate key values; PostgreSQL creates an enforcing unique index (multiple NULLs allowed by default) |
| Ordinary `CREATE INDEX` | Speeds up suitable queries but **does not** guarantee uniqueness |
| Foreign key (`REFERENCES`) | Enforces a relationship; PostgreSQL **does not automatically index the referencing column** |

**Don't add a second index identical to an existing primary-key or unique-constraint index.** It adds maintenance cost without adding a useful new access path.

## 4. Your practice database

The supplied files model a small issue tracker:

| Table | Approximate seeded rows | Relevant columns |
|---|---:|---|
| `users` | 100 | `id`, `handle`, `created_at` |
| `issues` | 10,000 | `id`, `user_id`, `status`, `priority`, `created_at` |
| `comments` | 1,000,000 | `id`, `issue_id`, `user_id`, `body`, `archived`, `created_at` |

`seed.sql` generates these records using `generate_series()` and random values. It **already contains table creation** and then **truncates existing practice data**, so only run it on a disposable practice database. `schema.sql` is an alternative standalone schema, not a second required setup step. The two files differ slightly on the nullability of `comments.user_id`.

After bulk loading:

```sql
ANALYZE users;
ANALYZE issues;
ANALYZE comments;
```

`ANALYZE` updates planner statistics. It helps PostgreSQL estimate how many rows a filter will return and choose an appropriate plan.

**Don't run all of `queries.sql` before measuring:** its final statements create indexes, which would spoil your **before-index** baseline. Likewise, `demo.sql` contains `DROP INDEX` commands—use `DROP INDEX IF EXISTS ...` if resetting the lab from scratch.

## 5. `EXPLAIN`: how to see what PostgreSQL is doing

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM comments
WHERE issue_id = 1;
```

- `EXPLAIN`: shows the chosen execution plan.
- `ANALYZE` inside `EXPLAIN`: **runs the SQL** and reports observed performance.
- `BUFFERS`: shows buffer activity, including pages found in PostgreSQL's shared buffer cache (`hit`) and pages read into it (`read`). In PostgreSQL 18, buffer information is included by default with `EXPLAIN ANALYZE`; spelling it out is still clear and portable to older versions.

Read the plan in this order:

1. **Scan type:** Did it choose `Seq Scan`, `Index Scan`, `Bitmap Heap Scan`, or `Index Only Scan`?
2. **Estimated vs actual rows:** Was the planner's guess close to reality?
3. **Execution Time:** Did the query actually become faster?
4. **Buffers:** Did the improved query perform less page work? Was some data already cached?

| Plan detail | Interpretation |
|---|---|
| `cost=...` | Estimated planner cost units, **not milliseconds** |
| `rows=...` | Estimated number of rows |
| `actual ... rows=...` | Rows observed during execution (per loop where applicable) |
| `loops=...` | How often that node was executed |
| `Rows Removed by Filter` | Rows checked and rejected |
| `Execution Time: ... ms` | Observed duration |
| `Heap Fetches: ...` | Heap visits made during an index-only scan for visibility checks |

`ANALYZE comments;` and `EXPLAIN ANALYZE SELECT ...;` are **different**: the first gathers statistics, while the second runs a query and reports its plan.

> **Safety:** `EXPLAIN (ANALYZE)` really executes `INSERT`, `UPDATE`, and `DELETE` too. Use a disposable database or wrap a test in `BEGIN; ... ROLLBACK;`.

## 6. The four major scan types

| Scan type | What PostgreSQL does | Typical reason |
|---|---|---|
| **Seq Scan** | Reads the table pages and tests rows | Small table, or query matches a large fraction of rows |
| **Index Scan** | Uses index keys and fetches matching heap tuples | Selective lookup requiring additional table columns |
| **Bitmap Index Scan → Bitmap Heap Scan** | Collects matching tuple locations, visits heap pages in a useful order | More matches, or combining multiple index conditions |
| **Index Only Scan** | Reads values held by the index; can avoid heap visits when visibility information permits | Requested columns are covered and visibility map supports it |

**A sequential scan is not an error.** If 80% of the table matches, walking an index plus visiting thousands of heap locations may be slower than scanning the table once.

### Small practical comparison

```sql
-- Before: run this on the seeded table without ix_comments_issue_id.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM comments WHERE issue_id = 1;

CREATE INDEX ix_comments_issue_id
ON comments (issue_id);

-- After: execute exactly the same query.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM comments WHERE issue_id = 1;
```

In this seed, comments are spread over 10,000 issues: **roughly 100 comments per issue on average**. An index should often be attractive for this selective lookup. By comparison, about **10,000 comments per user** are expected because there are only 100 users; retrieving `SELECT *` for one user can require many heap fetches.

Your earlier `demo.sql` contains example timing comments (such as ~18 ms → ~0.1 ms). Those are **observations recorded in the demo**, not guaranteed results on your machine. Check `actual rows` and buffer usage as well as milliseconds.

## 7. Composite (multicolumn) indexes: when one column is not enough

Suppose your query is:

```sql
SELECT *
FROM comments
WHERE issue_id = 42
  AND user_id = 7
  AND created_at >= now() - interval '30 days'
ORDER BY created_at DESC;
```

You have two equality filters, one timestamp range, and ordered output. A useful index is:

```sql
CREATE INDEX ix_comments_issue_user_created
ON comments (issue_id, user_id, created_at DESC);
```

Think of its organization as: **issue → user within issue → date within that user/issue pair**.

- `issue_id = 42`: narrow to a specific issue.
- `user_id = 7`: narrow further within that issue.
- `created_at >= ...`: scan the remaining date range.
- `ORDER BY created_at DESC`: the index may also supply the requested order and avoid an explicit sort.

**Good first heuristic:** Put commonly used **equality** conditions before the **range** condition. But index design depends on your actual query patterns; equality columns aren't universally interchangeable for other queries.

| Index definition | `WHERE issue_id = 42` | `WHERE user_id = 7` | Both equality filters |
|---|---|---|---|
| `(issue_id, user_id)` | Usually useful | Less ideal | Usually useful |
| `(user_id, issue_id)` | Less ideal | Usually useful | Usually useful |

### PostgreSQL 18: B-tree skip scan

Older explanations often say that an index on `(issue_id, user_id)` is simply useless when filtering on `user_id` alone. That's **too absolute** in PostgreSQL 18: the planner may apply **skip scan**, making repeated probes for distinct values of the missing leading column. It is most promising when that leading column has **few distinct values**. It is not a promise that every suffix-only query will be efficient.

The rule worth retaining: **leading columns still matter, but measure the plan on your PostgreSQL version.**

### Direction of the index

A B-tree can be scanned backward. For a query with fixed `issue_id` and `user_id`, an index ending in `created_at ASC` can still often serve `ORDER BY created_at DESC` through a backward scan. An explicit `DESC` makes intended access patterns readable and becomes especially relevant with mixed ordering directions across multiple unconstrained columns.

## 8. Combining two separate indexes (bitmap AND / OR)

Suppose you already created:

```sql
CREATE INDEX ix_comments_issue_id ON comments (issue_id);
CREATE INDEX ix_comments_user_id  ON comments (user_id);
```

For:

```sql
SELECT * FROM comments
WHERE issue_id = 42 AND user_id = 7;
```

PostgreSQL may choose one index and filter by the other condition, **or** form a bitmap from each index and combine them with `BitmapAnd`. With an `OR` predicate it can sometimes use `BitmapOr`.

```text
Index on issue_id ──┐
                    ├── BitmapAnd ──> Bitmap Heap Scan
Index on user_id ───┘
```

A **composite index** can often be faster for a heavily used, predictable conjunction, but separate indexes are more flexible for unrelated filters. Bitmap heap scans visit table pages rather than preserving index sort order, so the database may require a separate `Sort` for `ORDER BY`.

**Takeaway:** Two indexes aren't automatically equivalent to a well-chosen `(issue_id, user_id)` index. `EXPLAIN` tells you which strategy is actually used.

## 9. Partial indexes: index only the rows you care about

Imagine 99% of comments are **not archived** and about 1% **are archived**, as in your seed. If your service frequently asks for recent archived comments, indexing all million records may waste space.

```sql
CREATE INDEX ix_comments_archived_created
ON comments (created_at DESC)
WHERE archived = true;
```

Only rows satisfying `archived = true` get entries in this index.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, created_at
FROM comments
WHERE archived = true
  AND created_at >= now() - interval '30 days'
ORDER BY created_at DESC
LIMIT 50;
```

The query explicitly includes the condition from the index predicate. PostgreSQL can recognize that the query only needs indexed rows.

**Benefits:** smaller index, less maintenance for rows outside the predicate, potentially faster targeted searches.

**Limitation:** a partial index is useful only when PostgreSQL can establish that the query's conditions imply its predicate. It is not a universal index on `created_at`. Parameterized predicates can complicate matching—for example, a generic prepared query with `WHERE archived = $1` may not prove that `$1` is always `true`.

Use partial indexes for **stable, common filters** with reasonably selective subsets—not just any arbitrary expression.

## 10. Covering indexes (`INCLUDE`) and index-only scans

Suppose your query returns only `user_id` and `created_at` for one issue:

```sql
SELECT user_id, created_at
FROM comments
WHERE issue_id = 42;
```

An index on `issue_id` locates matching rows, but ordinarily PostgreSQL still needs the table to fetch `user_id` and `created_at`.

A **covering index** can store those extra return columns as payload:

```sql
CREATE INDEX ix_comments_issue_cover
ON comments (issue_id)
INCLUDE (user_id, created_at);
```

Here:

- `issue_id` is the **search key**.
- `user_id` and `created_at` are **included payload**, not additional search keys.
- Because all query columns are held in the index, an **Index Only Scan becomes possible**.

But `Index Only Scan` does **not** guarantee zero heap visits. PostgreSQL also has to verify whether rows are visible to the query's snapshot. It uses a **visibility map** to avoid most heap checks when pages are marked **all-visible**.

After bulk loading, a lab experiment may show nonzero `Heap Fetches` even when it selects an index-only scan:

```sql
VACUUM (ANALYZE) comments;

EXPLAIN (ANALYZE, BUFFERS)
SELECT user_id, created_at
FROM comments
WHERE issue_id = 42;
```

After `VACUUM`, more pages may be marked all-visible and `Heap Fetches` may decrease. Run `VACUUM` outside an explicit transaction block.

**Two cautions:**

1. `SELECT *` can't use this index as a complete covering structure because it needs columns like `body` that are not included.
2. Adding wide payload columns bloats the index and can increase write costs. `INCLUDE` is for *useful* coverage, not copying the entire table.

### Composite key versus `INCLUDE`

```sql
-- Both columns affect index search/order:
CREATE INDEX ix_issue_user ON comments (issue_id, user_id);

-- Only issue_id is a search key; user_id is payload:
CREATE INDEX ix_issue_include_user ON comments (issue_id) INCLUDE (user_id);
```

An included column does not help narrow an index search by that column in the same way as a key column.

## 11. Expression indexes: index the value your query actually computes

Consider a case-insensitive lookup:

```sql
SELECT * FROM users
WHERE lower(handle) = 'user_1_abcdef';
```

An ordinary index on `handle` is not necessarily useful for `lower(handle)`. The query searches by the **computed lowercase result**, not the raw stored value.

```sql
CREATE INDEX ix_users_handle_lower
ON users ((lower(handle)));
```

Now PostgreSQL may use the index when the query uses the matching expression. It stores computed index values, so inserts and certain updates pay the cost of computing and maintaining them.

**Why a `Seq Scan` might still appear:** Your `users` table has only 100 rows. Scanning it can be cheaper than consulting an index. That does not mean your expression index syntax is wrong.

For a production use case, a **unique expression index** can also enforce case-insensitive uniqueness:

```sql
CREATE UNIQUE INDEX ix_users_handle_ci_unique
ON users ((lower(handle)));
```

Only create such a unique index if your data and application truly require this rule; existing handles must already satisfy it.

## 12. Indexes improve reads but make writes more expensive

Every additional index needs storage and maintenance. Inserting a comment may mean writing to the heap **and** adding entries to several index structures. Updating an indexed value may also require index work; deleting rows creates eventual cleanup work.

### Small 0-versus-5-index experiment

Use a disposable PostgreSQL lab and compare inserts into two otherwise identical tables:

```sql
CREATE TABLE write_no_indexes (
    id bigint,
    user_id int,
    issue_id int,
    created_at timestamptz,
    archived boolean,
    body text
);

CREATE TABLE write_five_indexes (LIKE write_no_indexes);

CREATE INDEX wi_1 ON write_five_indexes (user_id);
CREATE INDEX wi_2 ON write_five_indexes (issue_id);
CREATE INDEX wi_3 ON write_five_indexes (created_at);
CREATE INDEX wi_4 ON write_five_indexes (archived);
CREATE INDEX wi_5 ON write_five_indexes (issue_id, user_id);
```

In `psql`, turn on timing and run these two inserts separately:

```sql
\timing on

INSERT INTO write_no_indexes
SELECT gs, gs % 100, gs % 10000,
       now() - (gs % 365) * interval '1 day',
       (gs % 100 = 0), repeat('x', 40)
FROM generate_series(1, 100000) AS gs;

INSERT INTO write_five_indexes
SELECT gs, gs % 100, gs % 10000,
       now() - (gs % 365) * interval '1 day',
       (gs % 100 = 0), repeat('x', 40)
FROM generate_series(1, 100000) AS gs;
```

Record *your* runtimes. Avoid concluding that index maintenance always adds some fixed number of milliseconds: timings depend on caching, disk, machine, and data distribution. For a stronger test, repeat with fresh tables or switch test order.

Check size:

```sql
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE relname = 'write_five_indexes'
ORDER BY pg_relation_size(indexrelid) DESC;
```

For the real `comments` table, you can use the same catalog query with `WHERE relname = 'comments'`.

**Engineering lesson:** An index is a trade: faster specific reads in exchange for more disk usage and write-maintenance work.

## 13. `CREATE INDEX CONCURRENTLY`: production writes matter

```sql
-- Standard build:
CREATE INDEX ix_comments_created_at
ON comments (created_at);
```

On a live, large table, an ordinary index build **blocks concurrent inserts, updates, and deletes** on that table until the build completes (ordinary reads can continue).

```sql
-- Production-friendly alternative:
CREATE INDEX CONCURRENTLY ix_comments_created_at
ON comments (created_at);
```

The concurrent build is designed to let normal writes continue. The trade-off is **more work and often longer build time**: PostgreSQL makes multiple passes and waits for relevant transactions. It still imposes CPU and I/O load. It cannot be run inside an explicit transaction block.

```sql
-- This is NOT allowed:
BEGIN;
CREATE INDEX CONCURRENTLY ix_demo ON comments (created_at);
COMMIT;
```

A failed concurrent build can leave an **invalid index** that needs investigation and cleanup, so do not blindly retry on production. Use `pg_stat_progress_create_index` to observe active builds. A migration tool must support operations outside its usual wrapping transaction.

**Why it exists:** We don't want adding an index to stop all application writes for a long period. It is about **availability during schema maintenance**, not making index queries intrinsically faster.

## 14. A reliable before/after experiment

The roadmap asks you to be able to explain *query → index → before/after timing → why*. Here's a good way to structure one experiment:

```sql
-- 1. Establish baseline; use only a disposable database.
DROP INDEX IF EXISTS ix_comments_issue_id;
ANALYZE comments;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM comments WHERE issue_id = 42;

-- 2. Add the index.
CREATE INDEX ix_comments_issue_id ON comments (issue_id);

-- 3. Run the EXACT same SQL again.
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM comments WHERE issue_id = 42;
```

A results table worth keeping in your notes:

| Query | Index used | Before (ms) | After (ms) | Why it changed |
|---|---|---:|---:|---|
| `WHERE issue_id = 42` | `ix_comments_issue_id` | *Measure* | *Measure* | Index limits work to one issue |
| `WHERE issue_id = 42 AND user_id = 7` | `(issue_id, user_id)` | *Measure* | *Measure* | Both equality filters help narrow lookup |
| `WHERE archived = true ORDER BY created_at DESC` | Partial index | *Measure* | *Measure* | Only archived rows indexed |
| `SELECT user_id, created_at WHERE issue_id = 42` | `INCLUDE` index | *Measure* | *Measure* | Possible index-only scan; visibility matters |
| `WHERE lower(handle) = ...` | Expression index | *Measure* | *Measure* | Computed search expression is indexed |

No timing values are filled in because those depend on **your system**. The purpose is to explain the actual plan, not to copy someone else's speedup.

### Why a comparison can mislead you

- **Warm cache:** The second query may be faster even without an index because data is cached.
- **Different results:** If the query matches 0 rows, impressive timing may not represent a busy real-world query.
- **Missing statistics:** Run `ANALYZE` after bulk loading before blaming the planner.
- **Index already exists:** `PRIMARY KEY` and `UNIQUE` create indexes automatically; previously executed demo statements may have created others.
- **Query changes:** Changing the filter or projection invalidates a simple before/after comparison.
- **Broad filters:** A `Seq Scan` may remain the fastest plan, even with a valid index.

For your seeded dataset, note that `issue_id = 1 AND user_id = 2` is expected to match **about one row across an entire year** on average (1,000,000 ÷ 10,000 ÷ 100), possibly **zero** over just the last month. Consider this when interpreting the tiny timings in `demo.sql`.

## 15. How these ideas connect

The two roadmap sessions aren't separate subjects; they build on each other:

```text
Question: Which rows do we need?
          ↓
B-tree/index creates a potential shortcut
          ↓
Planner compares shortcuts with sequential scan
          ↓
EXPLAIN shows the actual strategy
          ↓
Single column not enough?
   ├── Several filters in fixed order → composite index
   ├── Only a subset matters         → partial index
   ├── Query needs a few extra fields → INCLUDE / covering index
   ├── Filter calculates a value     → expression index
   └── Separate existing indexes     → bitmap AND / OR may help
          ↓
Validate rows, buffers and timings
          ↓
Balance read benefits against write and storage cost
```

**The principle to remember:** **Design indexes around real query patterns, then verify with `EXPLAIN (ANALYZE, BUFFERS)`**. Indexing is not about placing an index on every column; it is about choosing access paths that reduce real work for your workload.

---

## Reference links

**From the Session 6–7 roadmap and PostgreSQL documentation:**

- [Use The Index, Luke — Anatomy of an SQL Index](https://use-the-index-luke.com/sql/anatomy)
- [Use The Index, Luke — The Where Clause](https://use-the-index-luke.com/sql/where-clause)
- [PostgreSQL 18 — Using EXPLAIN](https://www.postgresql.org/docs/18/using-explain.html)
- [PostgreSQL 18 — Multicolumn Indexes](https://www.postgresql.org/docs/18/indexes-multicolumn.html)
- [PostgreSQL 18 — Combining Multiple Indexes](https://www.postgresql.org/docs/18/indexes-bitmap-scans.html)
- [PostgreSQL 18 — Partial Indexes](https://www.postgresql.org/docs/18/indexes-partial.html)
- [PostgreSQL 18 — Index-Only Scans and Covering Indexes](https://www.postgresql.org/docs/18/indexes-index-only-scans.html)
- [PostgreSQL 18 — Indexes on Expressions](https://www.postgresql.org/docs/18/indexes-expressional.html)
- [PostgreSQL 18 — Unique Indexes](https://www.postgresql.org/docs/18/indexes-unique.html)
- [PostgreSQL 18 — CREATE INDEX, including CONCURRENTLY](https://www.postgresql.org/docs/18/sql-createindex.html)
- [Hussein Nasser — Database Indexing Explained (with PostgreSQL)](https://youtu.be/teMXE6hzva0)

**Local project files:** `schema.sql`, `seed.sql`, `queries.sql`, `demo.sql`, and the earlier `indexing.md`.

*Scope: Indexing I and Indexing II only. Pagination, locks/deadlocks, MVCC/VACUUM internals, and JSONB indexing are separate later sessions in the roadmap.*
