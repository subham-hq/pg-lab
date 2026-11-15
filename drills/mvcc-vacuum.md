# PostgreSQL MVCC, Version Churn, and VACUUM

> **Purpose:** Understand why PostgreSQL keeps old row versions, how that creates version churn/bloat, why indexes can make it worse, and how VACUUM and PostgreSQL 14's bottom-up B-tree deletion help.
>
> **Source:** Your video transcript (Backend Engineering Show, “Postgres Version Churn and its Implication to Performance”, focused on PostgreSQL 14), clarified with the official PostgreSQL documentation.
>
> **Mental model to remember:** PostgreSQL keeps multiple physical versions of a logical row so concurrent transactions can see a consistent snapshot. That is great for concurrency, but obsolete versions must eventually be cleaned up. Until then, they can consume space and make index and heap reads do extra work.

---

## 1. Start with the problem MVCC solves

Imagine two database sessions:

- **Session A** starts a transaction and reads an account balance.
- **Session B** updates that balance and commits.
- Session A continues working.

Should Session A suddenly see a different version halfway through its transaction or statement? The answer depends on its isolation level and snapshot rules. PostgreSQL uses **MVCC (Multi-Version Concurrency Control)** to give each statement or transaction a consistent view of data.

Instead of making readers wait for writers in every case, PostgreSQL can keep an older row version around for a transaction whose snapshot is still allowed to see it.

The benefit:

- Readers and writers generally do not block each other just because one is reading a row while another updates it.
- A query can see a consistent snapshot rather than a mixture of old and new values.
- Concurrent work can proceed with less read/write lock contention.

The trade-off:

- An `UPDATE` does not simply overwrite the old row in place.
- PostgreSQL creates a **new physical tuple version**.
- The old version must remain until no transaction can still need it.
- Later, VACUUM can reclaim versions that are no longer visible to any relevant transaction.

This is the central idea behind the whole video. [PostgreSQL: MVCC introduction](https://www.postgresql.org/docs/14/mvcc-intro.html)

## 2. Logical row vs physical tuple

These two words are related, but they are not interchangeable.

| Term | Meaning |
|---|---|
| **Row** | The logical record your application thinks about, such as customer `id = 7`. |
| **Tuple** | A physical stored version of that row inside PostgreSQL's heap. |

Suppose your application has this logical row:

```text
id = 7, name = "Subham", city = "Kolkata"
```

After an update, PostgreSQL may have more than one physical tuple associated with logical row `id = 7`:

```text
Logical row id=7
    ├── tuple version A: city = "Kolkata"  (older)
    └── tuple version B: city = "Chandigarh" (newer)
```

Your application should not receive both versions as two separate logical customers. MVCC visibility rules decide which version a particular query is allowed to see.

**Remember:** one logical row can have several physical tuple versions over time.

## 3. How PostgreSQL decides which version you can see

PostgreSQL stores transaction metadata with tuple versions. Two important system columns are:

- `xmin`: the transaction ID associated with the transaction that inserted this tuple version.
- `xmax`: the transaction ID associated with a transaction that deleted or superseded this version; it can be unset/zero when there is no such transaction recorded.

A simplified way to think about it:

1. A transaction gets a snapshot when it runs a statement (or, at stronger isolation levels, uses the transaction's established snapshot).
2. The snapshot records which transactions were already completed and which were still in progress.
3. PostgreSQL checks tuple metadata against that snapshot.
4. A tuple created by a transaction that was not committed and visible to the snapshot is not visible to that snapshot.
5. An older tuple may remain visible to an older snapshot even after a newer version has been committed.

Do **not** memorize visibility as a simplistic rule such as “my transaction ID is between xmin and xmax.” Real visibility checks account for transaction commit/abort state and the snapshot's in-progress transaction set. Transaction IDs alone are not enough to explain every case.

### A two-session example

Assume a row starts with `balance = 100`.

```text
Session A                         Session B
---------                         ---------
BEGIN;
SELECT balance;  -- sees 100

                                  BEGIN;
                                  UPDATE accounts
                                  SET balance = 150
                                  WHERE id = 7;
                                  COMMIT;

SELECT balance;  -- depends on
                  -- isolation level
```

At PostgreSQL's default **READ COMMITTED** isolation level, each statement gets a fresh snapshot. So Session A's second `SELECT` can see `150`.

At **REPEATABLE READ**, Session A keeps the transaction snapshot, so it continues to see the version with `100` (subject to the full isolation semantics).

The old tuple is not pointless garbage immediately after Session B commits: Session A might still need it.

See [Transaction Isolation](https://www.postgresql.org/docs/14/transaction-iso.html).

## 4. Why updates create version churn

Imagine repeatedly changing the same logical row:

```sql
UPDATE accounts SET balance = 110 WHERE id = 7;
UPDATE accounts SET balance = 120 WHERE id = 7;
UPDATE accounts SET balance = 130 WHERE id = 7;
```

Conceptually, PostgreSQL may create a chain of physical versions:

```text
id=7, balance=100  ->  balance=110  ->  balance=120  ->  balance=130
       old                 old              old             newest
```

The old versions cannot be removed while an active snapshot might still need them.

When many updates happen, especially on hot rows or in update-heavy workloads, the database can accumulate many obsolete tuple versions. This is commonly called **version churn**. When those versions consume unnecessary heap or index space, people often describe the result as **bloat**.

A useful distinction:

- **Version churn** describes the repeated creation of new physical versions.
- **Dead tuples** are old versions that are no longer visible to any transaction.
- **Bloat** is excess space or extra structures resulting from obsolete versions and their index entries.

An old tuple is not dead merely because a newer version exists. It becomes removable only when PostgreSQL can prove that no active transaction can still need it.

## 5. Why indexes can multiply the work

A PostgreSQL index (for example, a B-tree) is a separate data structure. An index entry contains the indexed key and a pointer (a tuple identifier, or TID) to a physical tuple in the table heap.

Suppose a table has these indexes:

```sql
CREATE INDEX ON accounts (email);
CREATE INDEX ON accounts (status);
CREATE INDEX ON accounts (region);
```

Now update only `status`:

```sql
UPDATE accounts
SET status = 'active'
WHERE id = 7;
```

The new tuple has a new physical location/TID. For a non-HOT update, PostgreSQL generally needs successor index entries pointing to the new tuple version in **each index**, including indexes whose indexed key did not logically change (`email` and `region`).

Why? A new query using the `email` index must be able to find the current row version, not be stranded with only a pointer to an older tuple. Old index entries may also need to remain temporarily for snapshots that can still see the old tuple version.

This is one of the video's most important points:

> Updating one column can cause index maintenance in indexes on other columns too.

The official PostgreSQL documentation explicitly describes this version-churn behavior for B-tree indexes. [B-tree implementation: bottom-up index deletion](https://www.postgresql.org/docs/14/btree-implementation.html)

### Why this matters for reads

An index scan roughly does this:

1. Traverse B-tree pages to find matching index entries.
2. Follow the TID pointers into the heap.
3. Check whether the pointed-to tuple version is visible to the current snapshot.
4. Return visible rows and ignore versions that are not visible.

If an index page contains many obsolete entries for repeated versions of the same logical row, a scan may need to inspect more entries and perform more visibility checks to return the rows it actually needs.

More pages and more pointer-following can mean more I/O, CPU work, cache pressure, and latency. The concern is not just “the database uses more disk.” It is that a read may do extra work to find a small amount of useful data.

**Important nuance:** this is not a claim that every slow query is caused by bloat. A poor query plan, missing or unsuitable index, too many indexes, inefficient application queries, or lock contention may matter much more. Measure before tuning.

## 6. HOT updates: PostgreSQL's important optimization

**HOT** means **Heap-Only Tuple**. It reduces update overhead when both of these conditions are met:

1. The update does **not** change any column referenced by the table's indexes (including relevant expression and partial indexes).
2. There is enough free space on the same heap page to store the new tuple version.

When HOT is possible:

- PostgreSQL can create the new heap tuple version without adding a new entry to every index.
- Existing index entries can lead PostgreSQL through the HOT chain to the visible tuple version.
- Some old HOT versions can be pruned during normal page activity, rather than waiting for a regular VACUUM.

### Example

If `email` is indexed but `last_seen_at` is not:

```sql
UPDATE users
SET last_seen_at = now()
WHERE id = 7;
```

This update may be HOT if there is enough free space on the same heap page.

But this update changes an indexed column:

```sql
UPDATE users
SET email = 'new@example.com'
WHERE id = 7;
```

That cannot be HOT under the ordinary B-tree-index case because the index key itself changed.

HOT is not guaranteed just because you update a non-indexed column. The same-page free-space condition must also be satisfied.

### Fillfactor

`fillfactor` controls how full PostgreSQL initially tries to make heap pages when writing rows. A lower table fillfactor leaves more free space on pages, which can make same-page HOT updates more likely.

Example:

```sql
-- Example only; choose a value based on workload and measurement.
ALTER TABLE users SET (fillfactor = 80);
```

This does not instantly reorganize existing pages. It affects future table writes/rewrite behavior, and it trades some initial storage density for room that may help updates.

Check HOT activity with:

```sql
SELECT
    relname,
    n_tup_upd,
    n_tup_hot_upd,
    round(
        100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0),
        2
    ) AS hot_update_percent
FROM pg_stat_user_tables
ORDER BY n_tup_upd DESC;
```

[Official HOT documentation](https://www.postgresql.org/docs/14/storage-hot.html)

## 7. VACUUM: cleaning up dead tuple versions

Once no active transaction can see an old tuple version, that version is **dead** and its space can be reclaimed for reuse.

`VACUUM` performs this cleanup. In broad terms, it:

- identifies tuple versions that are no longer needed;
- makes their space reusable by future inserts or updates;
- cleans up obsolete index entries as appropriate;
- updates visibility-map information;
- helps prevent transaction ID wraparound by freezing sufficiently old tuples.

### Standard VACUUM does not usually shrink the table file

This is a very important distinction:

```sql
VACUUM accounts;
```

Ordinary `VACUUM` generally makes space reusable **inside the table**. It usually does not return that space to the operating system or make the table file smaller.

For example:

```text
Before:
[ live row ][ dead row ][ dead row ][ live row ]

After ordinary VACUUM:
[ live row ][ reusable space ][ reusable space ][ live row ]
```

PostgreSQL can reuse those empty slots for future tuple versions.

`VACUUM FULL` is different:

```sql
VACUUM FULL accounts;
```

It rewrites the table into a compact new file and can return disk space to the operating system. But it is much more disruptive: it requires an `ACCESS EXCLUSIVE` lock on the table, preventing normal access while it runs. It is not a routine substitute for ordinary VACUUM.

[Official VACUUM command documentation](https://www.postgresql.org/docs/14/sql-vacuum.html)

### Autovacuum

PostgreSQL normally runs maintenance automatically through **autovacuum**. The autovacuum launcher starts workers that inspect tables and run VACUUM and/or ANALYZE when needed.

- `VACUUM` reclaims reusable space and performs maintenance.
- `ANALYZE` collects statistics used by the query planner.
- `autovacuum` automates these jobs based on activity and thresholds.
- It also performs anti-wraparound work; this is a correctness/safety requirement, not merely a performance optimization.

A long-running transaction or old snapshot can prevent cleanup of tuple versions that might still be visible to it. This is one reason to avoid leaving transactions open unnecessarily.

Check table-level activity:

```sql
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

These statistics are estimates/monitoring counters, not a byte-perfect measurement of bloat.

[Routine Vacuuming and Autovacuum](https://www.postgresql.org/docs/14/routine-vacuuming.html)

## 8. PostgreSQL 14: bottom-up B-tree index deletion

The video focuses on a PostgreSQL 14 improvement called **bottom-up index deletion**.

First, the problem:

- A non-HOT update may add successor entries to every index.
- For an index whose indexed value did not logically change, repeated updates can leave many versions of index entries associated with the same logical row.
- Those entries can accumulate on B-tree leaf pages and contribute to page splits and extra index-scan work.

PostgreSQL 14 added a targeted way for B-tree indexes to delete obsolete version-churn entries incrementally.

When an insertion is approaching a B-tree leaf-page split, PostgreSQL can recognize a likely version-churn situation and attempt a **bottom-up deletion pass** on that leaf page. It targets obsolete index tuples that are no longer needed, potentially avoiding the page split.

Why “bottom-up”?

Think of the cleanup as being triggered locally by pressure on a B-tree leaf page, rather than waiting only for a table-wide VACUUM pass. The operation is aimed at the specific index page where version churn is building up.

### What it does not mean

Bottom-up deletion is **not** a replacement for VACUUM.

- It is targeted B-tree index cleanup, not general heap cleanup.
- It does not guarantee that all dead tuples everywhere are removed.
- VACUUM is still needed for comprehensive table/index cleanup and transaction ID freezing.
- It is most useful for version churn in indexes that are not logically changed by the update.
- It does not eliminate the cost of a non-HOT update to an indexed column.

The video describes this as PostgreSQL 14 reducing the need for some cleanup work to be done later by VACUUM. The precise description is: bottom-up deletion incrementally removes eligible version-churn index tuples during B-tree operations, often to avoid an anticipated page split. It does not generally run as a background cleanup pass on every read.

[PostgreSQL 14 B-tree implementation documentation](https://www.postgresql.org/docs/14/btree-implementation.html) · [PostgreSQL 14 release notes](https://www.postgresql.org/docs/14/release-14.html)

## 9. A complete example: follow one update through the system

Suppose this table has three indexes:

```sql
CREATE TABLE users (
    id          bigint PRIMARY KEY,
    email       text NOT NULL,
    status      text NOT NULL,
    last_seen   timestamptz
);

CREATE INDEX users_email_idx ON users (email);
CREATE INDEX users_status_idx ON users (status);
CREATE INDEX users_last_seen_idx ON users (last_seen);
```

Now run:

```sql
UPDATE users
SET status = 'active'
WHERE id = 42;
```

Conceptually, the lifecycle is:

1. PostgreSQL finds the old tuple for `id = 42`.
2. It creates a new tuple version containing `status = 'active'`.
3. The old tuple is marked as superseded by the updating transaction.
4. If the update is not HOT, PostgreSQL creates successor entries for the new tuple version in the indexes. This includes indexes whose key values did not change.
5. Older snapshots may still need the old tuple version and its index entry.
6. After those snapshots can no longer need it, the old tuple becomes dead.
7. VACUUM can reclaim the old heap version and clean up index entries.
8. For eligible B-tree version churn, PostgreSQL 14's bottom-up deletion may remove obsolete index tuples earlier when a leaf-page split is anticipated.

Could this update be HOT? Not in this exact schema if `status` is indexed, because the update changes an indexed column. If you instead updated an unindexed column and there were enough free bytes on the same heap page, HOT could be possible.

---

## 10. Try it locally in psql

Use a disposable table. These commands are safe for a local learning database, but do not run tuning or manual vacuum experiments on a production table without understanding the impact.

### A. Create a small test table

```sql
DROP TABLE IF EXISTS mvcc_demo;

CREATE TABLE mvcc_demo (
    id      integer PRIMARY KEY,
    email   text NOT NULL,
    status  text NOT NULL,
    note    text
);

CREATE INDEX mvcc_demo_status_idx ON mvcc_demo (status);
CREATE INDEX mvcc_demo_email_idx  ON mvcc_demo (email);

INSERT INTO mvcc_demo
VALUES (1, 'one@example.com', 'new', 'first version');
```

### B. Inspect the tuple metadata

```sql
SELECT
    id,
    email,
    status,
    xmin,
    xmax,
    ctid
FROM mvcc_demo;
```

What to notice:

- `xmin` and `xmax` are system columns that expose transaction metadata.
- `ctid` is the physical location (block, offset) of the tuple version in the table.
- `ctid` can change after an update. It is not a stable application identifier.
- Do not treat `xmin`/`xmax` as a complete replacement for PostgreSQL's visibility rules.

### C. Update the row several times

```sql
UPDATE mvcc_demo SET status = 'processing' WHERE id = 1;
UPDATE mvcc_demo SET status = 'packed'     WHERE id = 1;
UPDATE mvcc_demo SET status = 'shipped'    WHERE id = 1;

SELECT id, status, xmin, xmax, ctid
FROM mvcc_demo;
```

A normal SELECT shows the version visible to that statement, not every historical tuple. The old versions may still physically exist until pruning/VACUUM makes them reusable.

### D. See the effect of VACUUM

```sql
VACUUM (VERBOSE) mvcc_demo;
```

`VERBOSE` prints useful cleanup information. Run the metadata query again, but remember that physical tuple locations and exact cleanup timing can vary.

### E. Inspect update and vacuum statistics

```sql
SELECT
    relname,
    n_tup_upd,
    n_tup_hot_upd,
    n_dead_tup,
    last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'mvcc_demo';
```

Statistics may update asynchronously and can be reset. A tiny demo table may also be cleaned or pruned quickly, so it is not guaranteed to show a dramatic pile of dead tuples.

### F. Compare HOT-friendly and non-HOT-friendly updates

The `status` column is indexed, so changing it prevents HOT. The `note` column is not indexed, so changing only `note` may allow HOT if the new version fits on the same heap page.

```sql
UPDATE mvcc_demo
SET note = 'a different note'
WHERE id = 1;
```

Then inspect `n_tup_hot_upd` again. One update is not a statistically meaningful benchmark; repeat controlled tests on a larger disposable table if you want to compare rates.

### G. Inspect long-running transactions

A transaction holding an old snapshot can delay cleanup. You can inspect sessions with:

```sql
SELECT
    pid,
    usename,
    state,
    xact_start,
    now() - xact_start AS transaction_age,
    query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start;
```

Look for transactions that have been open much longer than expected. Do not terminate sessions blindly; first understand what the application is doing.

---

## 11. Common misconceptions to avoid

| Misconception | Better mental model |
|---|---|
| “An UPDATE overwrites the old row in place.” | PostgreSQL normally creates a new tuple version. |
| “One logical row means one physical tuple.” | One logical row can have multiple physical versions. |
| “An old version is immediately garbage after UPDATE.” | It may still be visible to an older snapshot. |
| “Only the index on the changed column needs maintenance.” | A non-HOT update can require successor entries in every index. |
| “HOT means the row is never versioned.” | HOT still creates a new heap tuple version; it avoids new index entries under its conditions. |
| “VACUUM makes the database file smaller.” | Ordinary VACUUM usually makes space reusable inside the relation; VACUUM FULL rewrites it. |
| “Autovacuum is just optional tidying.” | It is important for space reuse, planner statistics (via ANALYZE), and transaction ID wraparound protection. |
| “PostgreSQL 14 bottom-up deletion replaces VACUUM.” | It is targeted B-tree index cleanup; VACUUM remains essential. |
| “Every slow query is caused by bloat.” | Query plans, missing indexes, excess indexes, locks, I/O, and application behavior all matter. |

## 12. Practical engineering lessons

When designing a write-heavy PostgreSQL workload:

1. **Avoid unnecessary repeated updates.** If an application can compute a final state and write it once instead of issuing many tiny updates, that may reduce churn.
2. **Be deliberate with indexes.** Every index adds write and maintenance cost. Index only for real query patterns.
3. **Keep indexed columns stable when possible.** Updates to indexed columns cannot use ordinary HOT optimization.
4. **Leave room for HOT where it helps.** A lower fillfactor may help update-heavy tables, but validate with measurements.
5. **Keep transactions short.** Long-lived snapshots can hold back cleanup.
6. **Monitor autovacuum.** Check dead-tuple estimates, vacuum timestamps, update counts, HOT-update rates, and logs.
7. **Measure the actual bottleneck.** Use `EXPLAIN (ANALYZE, BUFFERS)` on representative queries and inspect I/O and buffer behavior before blaming bloat.
8. **Do not reach for `VACUUM FULL` casually.** It takes a strong lock and rewrites the table.

Useful query:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM users
WHERE email = 'one@example.com';
```

`ANALYZE` executes the query, so use care with statements that modify data. For a SELECT like this, it is a practical way to compare actual execution time and buffer activity.

---

## 13. The whole topic in one picture

```text
UPDATE a logical row
        |
        v
PostgreSQL creates a new heap tuple version
        |
        +------------------------------+
        |                              |
        v                              v
   Can HOT apply?                 HOT cannot apply
        |                              |
        v                              v
No new index entries             Successor entries in indexes
needed for the new version       point to the new tuple version
        |                              |
        +---------------+--------------+
                        |
                        v
       Old version must remain while a snapshot
             could still need to see it
                        |
                        v
        No relevant snapshot can see old version
                        |
                        v
                 Old tuple is dead
                        |
             +----------+-----------+
             |                      |
             v                      v
       VACUUM reclaims       B-tree bottom-up deletion
       heap/index space      can remove eligible index
       for reuse             version-churn entries
             |                      |
             +----------+-----------+
                        |
                        v
           Less obsolete data to inspect
            and space available for reuse
```

## 14. Six-month recall: what should stick?

If you come back to this note after six months, remember these six statements:

1. **MVCC is why PostgreSQL can give concurrent transactions consistent snapshots.**
2. **PostgreSQL keeps old tuple versions instead of immediately overwriting them.**
3. **Repeated updates create version churn; obsolete versions can become dead tuples and contribute to bloat.**
4. **Non-HOT updates can create new entries in every index, even when an index's key value did not change.**
5. **HOT reduces index work when indexed columns are unchanged and the new tuple fits on the same heap page.**
6. **VACUUM reclaims dead tuple space for reuse; PostgreSQL 14 bottom-up B-tree deletion additionally targets eligible index version churn before a page split.**

### Quick self-test

Try answering these without looking above:

1. Why can't PostgreSQL immediately delete an old tuple after an UPDATE commits?
2. What is the difference between a logical row and a physical tuple?
3. Why can changing one column create work in indexes on other columns?
4. What two conditions are required for a HOT update?
5. Does ordinary VACUUM normally shrink the table file on disk?
6. What specific problem does PostgreSQL 14 bottom-up index deletion target?

If you can explain those in your own words, you understand the main argument of the video.

---

## References

The video transcript is the primary teaching narrative. The links below are official PostgreSQL documentation used to clarify exact behavior and terminology.

- [MVCC Introduction — PostgreSQL 14](https://www.postgresql.org/docs/14/mvcc-intro.html)
- [Transaction Isolation — PostgreSQL 14](https://www.postgresql.org/docs/14/transaction-iso.html)
- [Heap-Only Tuples (HOT) — PostgreSQL 14](https://www.postgresql.org/docs/14/storage-hot.html)
- [B-tree Implementation and Bottom-up Index Deletion — PostgreSQL 14](https://www.postgresql.org/docs/14/btree-implementation.html)
- [VACUUM command — PostgreSQL 14](https://www.postgresql.org/docs/14/sql-vacuum.html)
- [Routine Vacuuming and Autovacuum — PostgreSQL 14](https://www.postgresql.org/docs/14/routine-vacuuming.html)
- [PostgreSQL 14 Release Notes](https://www.postgresql.org/docs/14/release-14.html)
- [System Information Functions and Snapshot Details — PostgreSQL 14](https://www.postgresql.org/docs/14/functions-info.html)
