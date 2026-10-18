# ACID Transactions, Isolation Levels & Consistency

> **Study source:** Hussein Nasser, *Relational Database ACID Transactions (Explained by Example)* (approximately 43 minutes). Organized in the **same teaching order as the video**: transactions → atomicity → isolation and its anomalies → isolation levels → consistency → durability. This is a condensed explanation, not a word-for-word transcript. It also incorporates the handwritten annotations in the screenshots and clarifies where the video's generalizations differ from **PostgreSQL**.

## 1. What exactly is a database transaction? (≈ 1:57)

A **transaction** is **one logical unit of work** made up of one or more SQL statements. The statements might be separate commands, but the business operation is treated as a single piece of work.

Think of moving **$100 from account 1 to account 2**. That is one transfer, even though the database may need several statements to complete it:

1. Check that account 1 has enough money.
2. Subtract $100 from account 1.
3. Add $100 to account 2.
4. Confirm the entire transfer.

Before the transfer:

| Account | Balance |
|---|---:|
| 1 | $1,000 |
| 2 | $500 |
| **Total** | **$1,500** |

After a **successful** transfer:

| Account | Balance |
|---|---:|
| 1 | $900 |
| 2 | $600 |
| **Total** | **$1,500** |

The balances changed, but **no money appeared or disappeared**.

### BEGIN, COMMIT and ROLLBACK

```sql
BEGIN;

UPDATE accounts
SET balance = balance - 100
WHERE account_id = 1 AND balance >= 100;

UPDATE accounts
SET balance = balance + 100
WHERE account_id = 2;

COMMIT;
```

- `BEGIN` starts a transaction.
- `COMMIT` ends it successfully: the transaction's database changes become committed.
- `ROLLBACK` aborts the transaction: its uncommitted database changes are undone.

**Important for real banking code:** The two `UPDATE` statements above illustrate transaction boundaries, but are **not sufficient by themselves** for a safe transfer. The application must verify that the debit and credit each affected exactly one intended row; if not, it must roll back. A condition such as `balance >= 100` also prevents a negative balance only when the debit actually matches a row. Real systems need appropriate constraints, error handling, and possibly additional business rules.

A transaction can contain **one** statement, not necessarily several. PostgreSQL also normally executes a standalone statement in its own implicit transaction when you don't explicitly use `BEGIN`.

---

## 2. A — Atomicity: all or nothing (≈ 4:30)

The video's intuition: imagine the transaction as **one indivisible unit**. Either the whole operation succeeds, or none of its database changes take effect.

### Why it matters: a crash between two updates

Suppose we are moving $100 as above:

```text
1. BEGIN transfer
2. Debit account 1: $1,000 → $900
3. Database/server crashes
4. Credit account 2: never happens
```

Without atomicity, the database could be left with:

| Account | Incorrect balance |
|---|---:|
| 1 | $900 |
| 2 | $500 |
| **Total** | **$1,400** |

**$100 has vanished from the system.** That's the failure Hussein is illustrating.

With an **atomic** database transaction, if it crashes **before commit**, recovery does **not** leave that half-completed transfer committed. Its changes are rolled back during recovery. The balances remain $1,000 and $500. If the full transaction commits successfully, the intended result is $900 and $600.

> **Remember:** Atomicity answers: **“Can half of my operation become permanently committed?”** It must not.

A subtlety: an SQL error within a PostgreSQL transaction generally puts the transaction into an aborted state until `ROLLBACK` (or recovery to a previously established `SAVEPOINT`). Do not assume a failed statement silently lets later statements proceed normally.

---

## 3. I — Isolation: what can concurrent transactions see? (≈ 7:10)

Hussein explains **isolation before consistency**, even though the familiar acronym is **ACID**. That ordering is deliberate: concurrency problems help explain why results can become inconsistent.

Imagine **TX1** is running a report while **TX2** changes sales data.

The central question is:

> **While my transaction is still running, which changes made by other transactions am I allowed to observe?**

Different answers give different **isolation levels**. With insufficient isolation for a given task, you can get strange results called *read phenomena* or, more broadly, *concurrency anomalies*.

### The sample SALES table

The video reuses these two products:

| Product | Quantity sold | Price | Quantity × Price |
|---|---:|---:|---:|
| Product 1 | 10 | $5 | $50 |
| Product 2 | 20 | $4 | $80 |
| **Total** | | | **$130** |

The report might first fetch individual totals:

```sql
SELECT pid, qnt * price AS subtotal
FROM sales;
```

Then it might fetch the total:

```sql
SELECT SUM(qnt * price) AS total_sales
FROM sales;
```

These are separate statements. Another transaction might run **between** them.

### 3.1 Dirty read — reading something that might never be committed (≈ 9:45–14:40)

**Your screenshot annotation, refined:** “Another transaction changed a value but **hasn't committed** it. My transaction reads that uncommitted change and bases its result on it.”

Follow the timeline:

```text
TX1                                     TX2
BEGIN                                   BEGIN
Read subtotals: $50 and $80
                                        Increase Product 1 quantity: 10 → 15
                                        (NOT COMMITTED)
Read total: $155  ← dirty read
COMMIT                                  ROLLBACK
```

TX1's first report says **$50 + $80 = $130**, but its next query produces **$155**, because it counted a change that TX2 eventually discarded. **That $155 result should never have represented committed sales.**

**Definition:** A dirty read is reading another transaction's **uncommitted write**.

**PostgreSQL distinction:** This timeline is a *hypothetical example of a database that permits dirty reads*. **PostgreSQL does not allow dirty reads at any supported isolation level**: even when you request `READ UNCOMMITTED`, it behaves as `READ COMMITTED`.

### 3.2 Non-repeatable read — a value changes between reads (≈ 14:40–17:03)

**Your screenshot annotation, refined:** “I read a value, another transaction **commits** a modification, and when I read that same value again within my transaction, I get a different result.”

```text
TX1                                     TX2
BEGIN                                   BEGIN
Read Product 1: quantity 10
                                        Update Product 1: quantity 10 → 15
                                        COMMIT
Read Product 1 again: quantity 15
```

Both reads can be of **committed** data. Nothing was dirty, but TX1 no longer sees a stable value.

The video illustrates the same idea with its sales report: the first details total **$130**, TX2 commits an update, and the later aggregate returns **$155**. Strictly speaking, the textbook definition is **re-reading the same data item** and finding it changed; the video's two different report queries are an easy-to-remember demonstration of the resulting inconsistency.

**Definition:** A non-repeatable read is when a row previously read within one transaction has a different value when re-read because another transaction committed an update.

### 3.3 Phantom read — a new matching row appears (≈ 17:03–18:50)

**Your screenshot annotation, refined:** “Another transaction inserts a row, commits it, and my later query **picks up an extra matching row** that wasn't there when I first checked.”

```text
TX1                                     TX2
BEGIN                                   BEGIN
Read sales rows: Product 1, Product 2
                                        INSERT Product 3 (10 × $1)
                                        COMMIT
Re-run the sales query:
Now Product 1, Product 2, Product 3
```

The total changed from **$130 to $140**, but not because Product 1 or 2 changed. **A new row appeared in the result set.** That's why it's called a *phantom*.

- **Non-repeatable read:** an **existing row's value** changes.
- **Phantom read:** the **set of rows matching a condition** changes (often because a row is inserted or deleted).

**Definition:** A phantom read happens when repeating a query with the same search condition returns a changed set of matching rows due to another committed transaction.

Phantoms are often discussed using range/predicate queries, such as `WHERE amount > 100`, because another transaction can insert a brand-new qualifying row.

### 3.4 Lost update — one writer accidentally discards another writer's work (≈ 11:07; discussed with anomalies)

**Your screenshot annotation, refined:** “Two transactions independently calculate changes from an older value; a later write **overwrites** another update, so one intended change is lost.”

Suppose a stock quantity starts at `10`:

```text
TX1                                     TX2
Read quantity = 10                      Read quantity = 10
Compute 10 + 5 = 15                     Compute 10 + 7 = 17
Write quantity = 15                     Write quantity = 17
```

If both writes succeed in this pattern, the final quantity might be **17**, even though both increments should have produced **22**. TX1's increment was lost.

**Crucial PostgreSQL nuance:** PostgreSQL does not simply permit another session to overwrite a row's **uncommitted** version. Concurrent writers of the same row coordinate with locks. But applications can still cause logical lost updates under `READ COMMITTED` if they **read a value, calculate a new absolute value in application code, then write back that stale calculation**. Using a single atomic statement such as `UPDATE stock SET quantity = quantity + 5 ...` helps avoid that particular lost-update pattern. Other strategies include row locking (`SELECT ... FOR UPDATE`), optimistic concurrency control, or stronger isolation with retries.

> **Mental distinction:** Dirty / non-repeatable / phantom are mainly about **what a reader observes**. Lost update is a **write conflict**: an intended modification disappears.

---

## 4. Isolation levels: the database's “visibility knob” (≈ 18:50–27:43)

Hussein's framing: **You don't automatically want the highest possible isolation for every workload.** Stronger guarantees can require extra coordination, conflict handling, or retries. Choose based on what the application must guarantee.

### 4.1 READ UNCOMMITTED — theoretical weakest level

In the SQL standard's model, a transaction may see **uncommitted changes** made by others. This can allow dirty reads and the other anomalies.

**In PostgreSQL:** Requesting `READ UNCOMMITTED` gets **`READ COMMITTED` behavior**. You cannot reproduce the video's dirty-read demonstration in PostgreSQL using this isolation level.

### 4.2 READ COMMITTED — a fresh committed view for each statement

This is **PostgreSQL's default**.

Each statement sees a snapshot of rows committed **when that statement starts** (plus earlier changes made by its own transaction). A later statement in the same transaction can see newer commits made by other sessions.

```text
TX1: SELECT quantity → 10
TX2: UPDATE quantity → 15; COMMIT
TX1: SELECT quantity → 15
```

This level **prevents dirty reads**, but allows non-repeatable reads and phantoms across statements.

**Think:** “Each new query may see a newer committed world.”

### 4.3 REPEATABLE READ — keep one stable snapshot

In **PostgreSQL**, the transaction keeps a snapshot anchored to its **first non-transaction-control statement**, not simply the moment `BEGIN` was typed. It also sees its own writes.

```text
TX1 (REPEATABLE READ): SELECT quantity → 10
TX2: UPDATE quantity → 15; COMMIT
TX1: SELECT quantity → 10    (same snapshot)
```

The video compares this to reading an **older version** of the database even as other sessions commit new versions. That's the intuition behind **MVCC — Multi-Version Concurrency Control**.

**Think:** “My queries keep seeing the same snapshot of other transactions' data.”

**Important correction for PostgreSQL:** Its `REPEATABLE READ` also **prevents phantom reads** through its snapshot behavior. The video's general comparison table says phantoms *may* occur at this level, which reflects the SQL standard's minimum guarantee and some other implementations—not PostgreSQL's actual behavior.

`REPEATABLE READ` is **not equivalent to full serializability**; anomalies such as **write skew** can still occur when concurrent transactions make decisions using the same snapshot and update different rows.

### 4.4 SERIALIZABLE — the result must make sense as some serial order

The strongest level means that **all successfully committed concurrent transactions must have an outcome equivalent to some order in which they ran one at a time**.

This **does not** mean PostgreSQL literally allows only one transaction to run at a time or takes a global exclusive lock.

PostgreSQL uses **Serializable Snapshot Isolation (SSI)**: transactions can overlap, but the database monitors dangerous dependencies and can **abort one with a serialization failure** rather than allow an impossible combination of commits. Applications must be ready to retry the **whole transaction**, often on SQLSTATE `40001`.

**Think:** “Concurrency is allowed, but an invalid combination of concurrent outcomes isn't.”

### 4.5 Comparison — PostgreSQL behavior, not a generic diagram

| PostgreSQL level | Dirty read | Non-repeatable read | Phantom read | Serialization anomaly |
|---|---|---|---|---|
| `READ UNCOMMITTED` (maps to Read Committed) | No | Possible | Possible | Possible |
| `READ COMMITTED` | No | Possible | Possible | Possible |
| `REPEATABLE READ` | No | No | **No** | **Possible** |
| `SERIALIZABLE` | No | No | No | No among committed transactions; conflicting ones may be retried |

**Lost updates need a separate explanation** rather than a simple yes/no cell: their possibility depends on whether the application performs stale read–modify–write operations, uses atomic updates, locks rows, or handles retries. The video's table is a useful mnemonic, but not a complete PostgreSQL concurrency specification.

### 4.6 Why MVCC is useful

Instead of making ordinary readers wait for every writer, PostgreSQL can keep multiple row versions and let queries see the appropriate snapshot. This helps **readers and writers operate concurrently**.

MVCC and locks are not opposites: PostgreSQL also uses locks for row updates, explicit row locks, and other operations. **Snapshot selection** determines what a query can see; **locking/conflict detection** helps coordinate writers and protect stronger guarantees.

A useful PostgreSQL syntax reminder:

```sql
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT * FROM sales;

COMMIT;
```

Or change `REPEATABLE READ` to `READ COMMITTED` / `SERIALIZABLE` to study their different behavior. For meaningful experiments, open **two separate database sessions** and interleave their statements.

---

## 5. C — Consistency: what does “consistent” actually mean? (≈ 27:43–34:04)

Hussein puts consistency **after atomicity and isolation** to show how the earlier properties help avoid broken results. He discusses **two useful meanings of consistency**:

1. **Consistency of stored data** — do the values obey the application's rules?
2. **Consistency/freshness of reads** — will a reader see the most recently committed change, especially across database replicas?

These are related questions, but **they are not identical**. In formal **ACID**, *Consistency* primarily means preserving the database's **integrity constraints and required invariants** across a successful transaction.

### 5.1 Consistency in stored data — application invariants (≈ 28:19)

A database invariant is something that must remain true, such as:

- A transfer between two accounts does not change their combined total (assuming no fees or outside flows).
- A `picture_likes.picture_id` references an existing picture.
- An inventory quantity is not allowed to go below zero, if that is your business rule.

Database constraints (`PRIMARY KEY`, `FOREIGN KEY`, `UNIQUE`, `CHECK`, `NOT NULL`) can enforce many such rules. Other, cross-row or cross-table invariants require correct transaction logic and appropriate concurrency control.

#### The photo-likes example from the video

**`Pictures`**:

| id | likes (stored counter) |
|---|---:|
| 1 | 2 |
| 2 | 1 |

**`Picture_Likes`**:

| user | picture_id |
|---|---:|
| Jon | 1 |
| Edmond | 1 |
| Jon | 2 |

Picture 1 has **two** like records; its stored `likes` count is **2**. Picture 2 has **one** like record and a counter of **1**.

If the counter says **4** for picture 1 while only **2** rows exist in `Picture_Likes`, the two representations **disagree**.

Why store a counter at all? **Performance**: displaying a popular post's like count can be cheaper than repeatedly counting all matching rows. But a stored counter creates a new responsibility: keeping the derived value aligned with the actual records, perhaps transactionally or eventually.

**Your screenshot annotation, refined:** “We define rules that values must satisfy—like account totals remaining valid—and we want the database to preserve those rules.”

**Connection to A and I:** Atomicity prevents **half of a logical change** being committed. Isolation helps concurrent transactions avoid producing invalid combinations of changes. **Neither automatically invents business rules**: the schema and application still have to define/enforce them.

### 5.2 Consistency in reads — does the next reader see my write? (≈ 34:04)

The video asks a different question:

> “I updated value **X** and committed. If another transaction reads X, will it immediately see my latest update?”

On a single PostgreSQL **primary** database, a new ordinary `READ COMMITTED` statement starting after the commit sees that committed update (subject to its query and normal visibility rules).

But now imagine **replication**:

```text
Primary database                      Read replica
       X = 10                              X = 10
       |
       | TX1 updates X = 20; COMMIT
       v
       X = 20                        (still X = 10)
       |                                  ^
       +------ replication delay --------+
                                          |
                                  eventually X = 20
```

A client who **writes to the primary but immediately reads from an asynchronously updated replica** might temporarily see the older value `10`.

**This is read staleness due to replication lag**, not a dirty read. The old value was previously committed and valid; it is simply **out of date**.

### 5.3 Eventual consistency — converge later (≈ 35:24–40:50)

**Eventual consistency** means that, **if new updates stop and synchronization can proceed**, the replicas will eventually converge to a common value. It does **not** promise that every immediate read returns the newest write.

The video connects this idea to social-network like counts and large-scale follower/leader (primary/replica) systems:

- A slight delay in a public **like count** may be tolerable.
- A stale **bank balance before authorizing a withdrawal** may not be tolerable.

**Engineering decision:** How much freshness does your particular operation require? You can often choose strategies such as routing important reads to the primary, waiting for replication, or using stronger consistency options where supported.

**Important correction to the video's broad SQL-vs-NoSQL framing:** **SQL does not automatically mean immediately consistent everywhere, and NoSQL does not automatically mean eventually consistent.** Replication modes, read/write settings, topology, and individual database guarantees determine the behavior. Some NoSQL systems support transactions, indexes and strong consistency; relational systems also scale out and can serve stale reads from asynchronous replicas.

**Keep the two meanings separate:**

| Question | Concept |
|---|---|
| “After this transaction commits, do required business rules still hold?” | **ACID consistency / invariants** |
| “During TX1, can TX2's changes affect my reads?” | **Isolation** |
| “After a commit on the primary, has another replica caught up?” | **Replication freshness / consistency model** |

---

## 6. D — Durability: committed means it survives a crash (≈ 40:50–42:20)

**Durability** means that once the database successfully acknowledges a durable **commit**, its effects must survive the kinds of failures the database promises to withstand, such as a process or machine crash.

```text
BEGIN
UPDATE balance ...
COMMIT → success acknowledged
Server crashes / power goes out
Server restarts → committed change is still there
```

The easy memory aid:

- **Atomicity** protects us **before** the transaction successfully commits: no half-committed operation.
- **Durability** protects the committed result **after** a successful durable commit: the result isn't forgotten after a restart.

### What PostgreSQL uses

PostgreSQL uses **Write-Ahead Logging (WAL)** to make crash recovery possible. Under normal durable settings, the database ensures the necessary log records are flushed to durable storage before reporting that the transaction has committed successfully.

**Real-world qualification:** PostgreSQL allows performance settings such as `synchronous_commit = off` that can acknowledge a commit **before** its WAL has been durably flushed; a crash can then lose the most recent acknowledged transactions. Durable guarantees depend on the configured settings and reliable storage.

The video's Redis comparison is useful for thinking about **memory vs durable storage**, but too categorical: Redis supports configurable persistence options, and its durability depends on the chosen configuration. “In-memory” does not by itself mean “never persistent.”

---

## 7. Bring the whole video together

Return to the **$100 transfer** and ask four different questions:

| Property | What it protects | Question to ask |
|---|---|---|
| **A — Atomicity** | The transfer as one indivisible unit | “What if the server fails after the debit but before the credit?” |
| **C — Consistency** | Required integrity rules | “After a valid transfer, are balances and required constraints still valid?” |
| **I — Isolation** | Concurrent transactions' interactions | “What if two transfers or a transfer and a balance check happen simultaneously?” |
| **D — Durability** | A successfully committed result | “What if the server restarts immediately after confirming the transfer?” |

And return to the **sales report** for the isolation phenomena:

| Phenomenon | The recognizable sign | Sales example |
|---|---|---|
| Dirty read | Read something **not committed** | Report includes Product 1 quantity 15 even though TX2 rolls back to 10 |
| Non-repeatable read | **Same row**, different value on a later read | Product 1 changes from quantity 10 to 15 after another commit |
| Phantom read | **Different set of matching rows** | Product 3 is inserted and appears in a subsequent report |
| Lost update | One **write's effect disappears** | Two stale read–modify–write operations overwrite each other |

**The design principle Hussein keeps returning to:** Pick guarantees by the **cost of being wrong**, not by assuming maximum isolation or eventual consistency is universally best. Financial records, public counters, inventory, and analytics can have very different requirements.

---

## Notes on accuracy and source wording

The transcript is an **automatic caption transcript** with occasional recognition errors (for example, “Bosphorus” for **Postgres**, “no sequel” for **NoSQL**, and “atomicity” misheard as other phrases). The notes normalize the terminology but retain the **examples and learning sequence**.

A few instructor explanations are **teaching simplifications**, which should not become permanent misconceptions:

- **Serializable** means an **equivalent serial outcome**, not “PostgreSQL puts everything behind one global lock.” PostgreSQL uses SSI and may abort conflicting transactions.
- **PostgreSQL Repeatable Read** prevents phantoms, even though the SQL standard allows an implementation to permit them at this level.
- **Read Uncommitted** does not actually enable dirty reads in PostgreSQL.
- **ACID Consistency**, stable snapshots, and up-to-date replicated reads are three distinct ideas.
- **SQL/NoSQL** and **RAM/disk** are not simple binary switches for consistency and durability.
- **Lost updates** are more subtle than another transaction writing over an uncommitted row; application read–modify–write patterns matter.

### References used to verify PostgreSQL-specific behavior

- [PostgreSQL: Transaction Isolation](https://www.postgresql.org/docs/current/transaction-iso.html) — actual isolation semantics, snapshots, phantom reads and serializable retries.
- [PostgreSQL: MVCC Introduction](https://www.postgresql.org/docs/current/mvcc-intro.html) — multiple row versions, snapshots and concurrent reads/writes.
- [PostgreSQL: Asynchronous Commit](https://www.postgresql.org/docs/current/wal-async-commit.html) — the durability implications of synchronous versus asynchronous commit.

*Based on the supplied video captions and timestamped screenshots, including the user's annotations; reorganized for long-term study and supplemented with explicitly labeled PostgreSQL corrections.*
