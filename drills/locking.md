# PostgreSQL Locks, Deadlocks & Concurrency

A practical reference for understanding what happens when several requests or workers use the same database data at the same time.

## 1. Why do databases need locks?

Imagine two customers trying to buy the last item in stock at almost the same time. Both requests check the stock and see `1`. If both then subtract one, the application may accept two orders for an item that existed only once.

This is a **race condition**: the result depends on the timing and order of concurrent operations.

Locks let PostgreSQL coordinate transactions when their operations conflict. They help protect data while a transaction checks or changes it.

### PostgreSQL also uses MVCC

PostgreSQL uses **Multi-Version Concurrency Control (MVCC)**. It keeps row versions so a normal reader can often see a consistent snapshot while another transaction changes data.

An ordinary `SELECT` generally does not lock each row against writers. It does take a lightweight table-level `ACCESS SHARE` lock, which is compatible with ordinary reads and writes. It mainly conflicts with `ACCESS EXCLUSIVE`.

Use explicit row locks when your operation needs to read a row and then make a decision based on that value, and competing transactions must wait rather than make the same decision at the same time.

## 2. Table locks and row locks are different

A **table-level lock** applies to a table as a whole. A **row-level lock** applies to selected rows.

A table lock does not automatically mean nobody else can use the table. PostgreSQL has several table lock modes, and many are compatible with one another.

### Table-level lock modes

PostgreSQL has eight table-level lock modes:

| Mode | Simple explanation |
|---|---|
| `ACCESS SHARE` | Taken by ordinary `SELECT`. Compatible with normal reads and writes. |
| `ROW SHARE` | Taken by locking reads such as `SELECT ... FOR UPDATE`. Despite its name, this is a table lock. |
| `ROW EXCLUSIVE` | Taken by `INSERT`, `UPDATE` and `DELETE`. |
| `SHARE UPDATE EXCLUSIVE` | Used by operations including regular `VACUUM` and `ANALYZE`. |
| `SHARE` | Used by operations such as a non-concurrent `CREATE INDEX`. |
| `SHARE ROW EXCLUSIVE` | A stronger lock used by certain maintenance or schema operations. |
| `EXCLUSIVE` | Blocks ordinary writes and most other table-lock modes, but permits `ACCESS SHARE` reads. |
| `ACCESS EXCLUSIVE` | Strongest table lock; conflicts with every other table lock mode, including ordinary `SELECT`. |

You do not need to memorize the full compatibility matrix immediately. The key idea is that PostgreSQL chooses a lock mode for an operation, and other operations can proceed if their lock modes are compatible.

### `VACUUM` versus `VACUUM FULL`

Updates and deletes can leave old row versions (often called **dead tuples**) behind.

- Regular `VACUUM` cleans up dead tuples and makes their space reusable. It generally allows ordinary reads and writes to continue.
- `VACUUM FULL` rewrites and compacts the table to return space to the operating system. It needs `ACCESS EXCLUSIVE`, so it blocks other access to that table while it runs.

This matters when planning maintenance on a production database.

### Row-level locks

Row-level locks protect particular rows, not the whole table. Two transactions can update different customer accounts at the same time.

The main row-lock strengths are:

- `FOR UPDATE` — strongest row lock; used when a transaction intends to update a row.
- `FOR NO KEY UPDATE` — slightly weaker when key columns are not being changed.
- `FOR SHARE` — allows compatible shared row locks but conflicts with updates and deletes.
- `FOR KEY SHARE` — protects key values against changes that would conflict with references to them.

An ordinary `SELECT` does **not** take a shared row lock. MVCC is what lets normal reads and writes coexist in many cases.

## 3. `SELECT ... FOR UPDATE`: protect a read-then-change operation

Suppose your application must read a row, check its current value, decide whether an operation is allowed, and then update it. If two transactions do these steps at once, both might make a decision based on the same old value.

`FOR UPDATE` locks the selected rows. A competing transaction that needs a conflicting row lock or update must wait until the first transaction commits or rolls back.

The lock lasts until the transaction ends. That is why the `SELECT` and `UPDATE` belong in the same transaction.

### Example A: prevent double-booking a seat

```sql
BEGIN;

SELECT *
FROM seats
WHERE seat_id = 42
FOR UPDATE;

-- In application code, check whether the seat is still available.
-- If available:
UPDATE seats
SET booked = TRUE
WHERE seat_id = 42
  AND booked = FALSE;

COMMIT;
```

If another request tries to lock the same seat, it waits. Once the first transaction commits, the second request checks the current state and should see that the seat is no longer available.

The `AND booked = FALSE` condition is an extra safety check. In a real application, check the number of rows updated and report a booking conflict if no row was changed.

### Example B: two customers want the last item

```sql
BEGIN;

SELECT quantity
FROM inventory
WHERE product_id = 7
FOR UPDATE;

-- Application checks that quantity is greater than zero.

UPDATE inventory
SET quantity = quantity - 1
WHERE product_id = 7
  AND quantity > 0;

COMMIT;
```

The row lock makes competing transactions take turns checking and changing this inventory row. The conditional update is useful defense-in-depth: it prevents the quantity from being reduced below zero even if application logic changes later.

### Example C: protect a wallet withdrawal

```sql
BEGIN;

SELECT balance
FROM wallets
WHERE wallet_id = 12
FOR UPDATE;

-- Application checks that the balance is at least 500.

UPDATE wallets
SET balance = balance - 500
WHERE wallet_id = 12
  AND balance >= 500;

COMMIT;
```

Without coordination, two withdrawals could both read the same balance and both decide enough money is available. Locking the wallet row makes the second withdrawal wait and then check the updated balance.

Check whether the `UPDATE` changed a row. Do not treat a request as successful if the balance condition was not met.

### Important practical points

- Lock only the rows you need.
- Keep transactions short; do not hold locks while waiting for a user, calling a slow external API, or doing unrelated work.
- Always commit or roll back. An open transaction can keep locks longer than intended.
- A row lock does not normally stop an ordinary MVCC `SELECT` from reading a visible row version.
- Constraints and conditional updates are valuable additional protection. A lock is not a substitute for database constraints.

## 4. `NOWAIT` and `SKIP LOCKED`

These options change what happens when a selected row is already locked by another transaction.

| Clause | What happens when a conflicting lock exists? |
|---|---|
| `FOR UPDATE` | Waits for the lock to be released. |
| `FOR UPDATE NOWAIT` | Fails immediately instead of waiting. |
| `FOR UPDATE SKIP LOCKED` | Skips locked rows and continues looking for other rows. |

Think of three ways to approach a locked door:

- `FOR UPDATE`: wait outside.
- `NOWAIT`: do not wait; report that it is locked.
- `SKIP LOCKED`: try another door.

### Why `SKIP LOCKED` is useful: a job queue

Imagine several background workers are looking for pending jobs. Worker 1 has locked job 1. Worker 2 should not wait for job 1 if job 2 is available.

A worker can claim one available job like this:

```sql
BEGIN;

WITH next_job AS (
    SELECT id
    FROM jobs
    WHERE status = 'pending'
    ORDER BY id
    FOR UPDATE SKIP LOCKED
    LIMIT 1
)
UPDATE jobs
SET status = 'processing'
WHERE id = (SELECT id FROM next_job)
RETURNING *;

COMMIT;
```

The worker locks one pending row, changes its status, and commits the claim. Other workers skip that locked row and can claim different jobs.

`SKIP LOCKED` does not by itself guarantee exactly-once processing. Real workers still need failure handling, retries, and a way to recover jobs left in `processing` if a worker crashes.

## 5. Deadlocks: when transactions wait for each other

A **deadlock** happens when transactions form a cycle of waiting.

Imagine two bank accounts, A and B:

| Step | Transaction 1 | Transaction 2 |
|---|---|---|
| 1 | Locks account A | |
| 2 | | Locks account B |
| 3 | Requests B, so it waits | |
| 4 | | Requests A, so it waits |

Transaction 1 holds A and waits for B. Transaction 2 holds B and waits for A. Neither can continue.

PostgreSQL detects deadlocks and aborts one transaction so the other can proceed. The application should be prepared to retry a transaction that fails with a deadlock error.

### How to reduce deadlocks

**Use consistent lock ordering.** If a transaction needs accounts A and B, always lock them in the same order (for example, lower account ID first). Do not let one code path lock A then B while another locks B then A.

Also:

- Keep transactions short.
- Lock only what is needed.
- Avoid unnecessary work between `BEGIN` and `COMMIT`.
- Handle deadlock errors and retry the whole transaction when appropriate.

Consistent ordering greatly reduces deadlocks, although it cannot prevent every possible lock conflict.

### How to inspect blocking

If a query seems stuck, PostgreSQL's `pg_stat_activity` and `pg_locks` views help investigate active sessions and locks.

A useful debugging approach is to open a third database session and inspect who is waiting and who is blocking. This is more informative than guessing why an application request is slow.

## 6. Page-level locks

PostgreSQL stores table and index data in fixed-size pages (commonly 8 KB).

It uses short-lived page-level locks internally to coordinate access to pages and index structures. These are different from the row locks you request with `SELECT ... FOR UPDATE`.

For everyday application development, you generally do not manage page-level locks yourself. Understand that they exist, but focus first on transactions and row-level locking.

## 7. Advisory locks

An **advisory lock** is an application-defined lock.

Your application chooses a key that represents some logical operation, and PostgreSQL coordinates sessions that try to acquire the same key.

```sql
SELECT pg_advisory_lock(12345);
```

This obtains a session-level advisory lock. Another session requesting the same lock must wait.

PostgreSQL also provides transaction-level advisory locks, which are released automatically when the transaction ends.

Advisory locks can coordinate work that does not map neatly to one database row—for example, ensuring that only one instance of a particular scheduled task runs at a time.

The catch: PostgreSQL does not know what your advisory-lock key represents. Every part of your application that needs the same protection must follow the same locking convention.

## 8. Where backend engineers use these ideas

| Situation | Useful mechanism |
|---|---|
| Two users book the same seat | Lock the seat row with `FOR UPDATE`; also enforce booking uniqueness where appropriate. |
| Two customers buy the last item | Lock the inventory row or use a safe conditional update; enforce valid quantity constraints. |
| Two withdrawals affect one wallet | Lock the wallet row before checking and changing its balance. |
| Several workers claim jobs | `FOR UPDATE SKIP LOCKED` to claim different pending rows. |
| A request should fail rather than wait | `NOWAIT`. |
| Transactions lock resources in opposite order | Consistent lock ordering; handle and retry deadlock failures. |
| Only one scheduled task should run for a logical key | Advisory lock. |

## 9. The main ideas to remember

1. **Concurrency** means multiple transactions are using the database at the same time.
2. **MVCC** lets ordinary readers and writers coexist in many situations.
3. **Table locks** coordinate operations at table level; **row locks** protect particular rows.
4. **`FOR UPDATE`** is useful when you must read a row, make a decision, and then update it safely.
5. **`NOWAIT`** fails immediately on a lock conflict; **`SKIP LOCKED`** moves past locked rows.
6. **Deadlocks** are cycles of transactions waiting for one another. PostgreSQL detects them and aborts one transaction.
7. **Consistent lock ordering, short transactions, constraints, and retries** are important parts of robust backend design.
8. **Advisory locks** let the application coordinate logical operations that are not tied to a particular row.

The practical question to ask when designing a backend operation is:

> What if two requests try to do this at exactly the same time?

If the answer could be incorrect data, double-booking, overselling, or duplicate work, think about transaction boundaries, constraints, and the appropriate locking strategy.
