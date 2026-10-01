# pg-lab

A hands-on PostgreSQL lab: notes that run, drills that measure, and a final checkpoint taken cold.

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-7AA2F7?style=flat-square&labelColor=1A1B27&logo=postgresql&logoColor=white)
![Status](https://img.shields.io/badge/status-in%20progress-E0AF68?style=flat-square&labelColor=1A1B27)

## About

pg-lab is a structured path through PostgreSQL, from the first `SELECT` to how the engine stores, indexes and isolates data. It has three layers:

1. **Course notes** (`notes/01`–`13`): the freeCodeCamp beginner course, rewritten as runnable SQL, plus the edge cases and production habits the course leaves out.
2. **Depth topics** (5–16): CTEs, window functions, normalization, isolation levels, storage, indexing, locking, MVCC, WAL, partitioning and CMU 15-445 internals.
3. **Proof**: three measured drills and a checkpoint taken cold.

## How this lab works

- **Every file runs.** Each notes file reloads its own data and runs top to bottom without an error. That's checked before every commit.
- **Expected errors stay in the file.** Statements that fail on purpose are kept as comments, next to the exact message psql printed.
- **Beyond the video.** Every notes file ends with what the course skips: edge cases, performance notes and production habits, each shown with a query.
- **Evidence over summaries.** Drills record real `EXPLAIN ANALYZE` plans, timings and two-session transcripts: numbers, not claims.
- **One gate at the end.** The lab is done when the checkpoint is passed cold, with no notes and no videos.

## Progress

✅ done · 🚧 in progress · ⬜ not started

| # | Topic | Source | Output | Status |
|:-:|---|---|---|:-:|
| 1 | Setup, SELECT, WHERE, ORDER BY, LIMIT, IN | freeCodeCamp · part 1 | [`notes/01`](notes/01-basics.sql) | ✅ |
| 2 | Filtering, aggregates, expressions, NULLs, dates and intervals | freeCodeCamp · part 2 | [`notes/02`–`06`](#course-notes) | ✅ |
| 3 | Keys and constraints, UPDATE / DELETE, upserts | freeCodeCamp · part 3 | [`notes/07`–`09`](#course-notes) | ✅ |
| 4 | Foreign keys, JOINs, CSV export, sequences, UUIDs + Pagila drill | freeCodeCamp · part 4 | [`notes/10`–`13`](#course-notes), `drills/pagila-tier1.sql` | 🚧 |
| 5 | Subqueries and CTEs | PostgreSQL docs | `drills/ctes.sql` | ⬜ |
| 6 | Window functions | PostgreSQL docs | `drills/windows.sql` | ⬜ |
| 7 | Normalization, 1NF → BCNF | Decomplexify | `drills/normalization/` | ⬜ |
| 8 | ACID and isolation levels | Hussein Nasser | `drills/isolation.md` | ⬜ |
| 9 | How Postgres stores data | Hussein Nasser | `notes/internals.md` | ⬜ |
| 10 | Indexing and EXPLAIN | Hussein Nasser · Use The Index, Luke | `drills/indexing.md` | ⬜ |
| 11 | OFFSET vs keyset pagination | Hussein Nasser | `drills/pagination.md` | ⬜ |
| 12 | Locks, deadlocks, `SKIP LOCKED` | Hussein Nasser | `drills/locking.md` | ⬜ |
| 13 | MVCC and VACUUM | Hussein Nasser · PostgreSQL docs | `notes/mvcc.md` | ⬜ |
| 14 | WAL, replication, connection pooling | Hussein Nasser | `notes/wal-pooling.md` | ⬜ |
| 15 | Partitioning and JSONB | Hussein Nasser · PostgreSQL docs | `drills/partitioning-jsonb.md` | ⬜ |
| 16 | B+Trees and MVCC from the inside | CMU 15-445 | `notes/cmu-btree.md`, `notes/cmu-mvcc.md` | ⬜ |
| ✓ | Checkpoint, taken cold | — | `CHECKPOINT.md` | ⬜ |

## Course notes

Each file reloads the data it needs first, so the files run in any order.

| File | Covers | Status |
|---|---|:-:|
| [`01-basics.sql`](notes/01-basics.sql) | Setup, SELECT, WHERE, ORDER BY, LIMIT, IN | ✅ |
| [`02-filtering.sql`](notes/02-filtering.sql) | BETWEEN, LIKE / ILIKE, half-open ranges, escaping wildcards | ✅ |
| [`03-aggregation.sql`](notes/03-aggregation.sql) | GROUP BY, HAVING, COUNT / MIN / MAX / AVG / SUM, FILTER | ✅ |
| [`04-expressions.sql`](notes/04-expressions.sql) | Arithmetic, ROUND, aliases, integer division, NUMERIC vs float | ✅ |
| [`05-nulls.sql`](notes/05-nulls.sql) | COALESCE, NULLIF, three-valued logic, IS DISTINCT FROM | ✅ |
| [`06-dates-and-times.sql`](notes/06-dates-and-times.sql) | NOW, intervals, EXTRACT, AGE, time zones | ✅ |
| [`07-constraints.sql`](notes/07-constraints.sql) | Primary keys, UNIQUE, CHECK, NOT VALID | ✅ |
| [`08-update-delete.sql`](notes/08-update-delete.sql) | UPDATE, DELETE, RETURNING, safe transactions, TRUNCATE | ✅ |
| [`09-upsert.sql`](notes/09-upsert.sql) | ON CONFLICT DO NOTHING / DO UPDATE, upserting on a natural key | ✅ |
| [`10-foreign-keys.sql`](notes/10-foreign-keys.sql) | Foreign keys, ON DELETE actions, relationship shapes | ✅ |
| [`11-joins.sql`](notes/11-joins.sql) | INNER, LEFT, FULL and CROSS joins, anti-joins | ✅ |
| [`12-export-csv.sql`](notes/12-export-csv.sql) | `\copy` to and from CSV, `\copy` vs `COPY` | ✅ |
| `13-id-generation.sql` | Sequences, identity columns, UUIDs | 🚧 |

## Gotchas covered

The traps worth remembering, and where each one is shown:

- `BETWEEN` includes both ends. With timestamps, a half-open range (`>= start AND < end`) is safer. ([02](notes/02-filtering.sql))
- `LIKE` with no wildcard is plain equality, and `LIKE` is case-sensitive while `ILIKE` isn't. ([02](notes/02-filtering.sql))
- `NOT LIKE` leaves out NULL rows, and `NOT IN` with a NULL in its list returns nothing at all. ([02](notes/02-filtering.sql), [05](notes/05-nulls.sql))
- `HAVING COUNT(*) > 5` means six or more. ([03](notes/03-aggregation.sql))
- `SUM`, `AVG`, `MIN` and `MAX` over zero rows return NULL, not 0. ([03](notes/03-aggregation.sql))
- Integer division truncates (`5 / 2` is `2`), and money belongs in `NUMERIC`, never a float. ([04](notes/04-expressions.sql))
- `ROUND(2.5)` gives 3 for `NUMERIC` but 2 for `DOUBLE PRECISION`. ([04](notes/04-expressions.sql))
- `= NULL` matches nothing; use `IS NULL`, or `IS DISTINCT FROM` for a NULL-safe comparison. ([05](notes/05-nulls.sql))
- `NOW()` stays fixed for the whole transaction. Real moments go in `timestamptz`, and dates are written `YYYY-MM-DD`. ([06](notes/06-dates-and-times.sql))
- `CHECK` lets NULL through, and `UNIQUE` allows any number of NULLs. ([07](notes/07-constraints.sql))
- On a big table, add a constraint `NOT VALID` first, then `VALIDATE` it. ([07](notes/07-constraints.sql))
- A destructive statement gets tried inside `BEGIN … ROLLBACK` first. Even `TRUNCATE` can be rolled back. ([08](notes/08-update-delete.sql))
- `ON CONFLICT` needs a unique constraint on its target, and unlike SELECT-then-INSERT it can't race. ([09](notes/09-upsert.sql))
- Postgres doesn't index foreign-key columns for you. ([10](notes/10-foreign-keys.sql))
- A `WHERE` condition on the right-hand table turns a `LEFT JOIN` into an inner join. ([11](notes/11-joins.sql))
- `\copy` writes the file on your machine; `COPY` writes it on the database server. ([12](notes/12-export-csv.sql))

## Proof-of-skill drills

| Drill | What it proves | Status |
|---|---|:-:|
| #1 Index performance | Read a slow plan, add the right index, measure the win | ⬜ |
| #2 Isolation levels | Reproduce each read anomaly in two live sessions, and the level that prevents it | ⬜ |
| #3 Normalization | Turn a messy spec into a 3NF/BCNF schema whose constraints reject bad data | ⬜ |

## Checkpoint

Done when all three pass with no notes, no videos, and a timer running:

1. Design a normalized schema from a spec never seen before.
2. Read a slow query's `EXPLAIN ANALYZE`, add the right index, and prove the speed-up.
3. Explain each isolation level and the anomaly it prevents, out loud.

## Repository layout

```
pg-lab/
├── data/                       practice data, loaded by the notes
│   ├── person.sql              1,000 people (Mockaroo-style)
│   ├── car.sql                 1,000 cars (Mockaroo-style)
│   └── employee-laptop.sql     5 employees and 4 laptops, one-to-one
├── notes/                      one file per lesson, runnable top to bottom
├── drills/                     exercises with measured results (from topic 4 on)
└── README.md
```

## Run it yourself

Requires PostgreSQL 18. On macOS, [Postgres.app](https://postgresapp.com) is the simplest install.

Run every notes file and see which pass:

```bash
createdb lab
for f in notes/*.sql; do psql lab -v ON_ERROR_STOP=1 -f "$f" > /dev/null && echo "ok    $f" || echo "FAIL  $f"; done
```

Each file loads its own data with `\ir`, so any single file also runs on its own:

```bash
psql lab -f notes/11-joins.sql
```

From topic 4's drill on, the drills use the [Pagila](https://github.com/devrimgunduz/pagila) sample database, loaded into its own database:

```bash
createdb pagila
psql pagila -f pagila-schema.sql
psql pagila -f pagila-data.sql
```

## Conventions

- SQL keywords in UPPERCASE, names in lower_snake_case
- One clause per line
- Every script is re-runnable: `DROP … IF EXISTS` before `CREATE`
- `LIMIT` and `OFFSET` always come with an `ORDER BY`
- Statements that fail on purpose are commented out, with psql's exact error underneath
- Comments explain surprises, not syntax

## Resources

- freeCodeCamp (Amigoscode): *Learn PostgreSQL Tutorial – Full Course for Beginners*
- Hussein Nasser: [Database Engineering](https://www.youtube.com/@hnasr) playlist
- Andy Pavlo: [CMU 15-445/645 Intro to Database Systems](https://15445.courses.cs.cmu.edu)
- Markus Winand: [Use The Index, Luke](https://use-the-index-luke.com)
- [PostgreSQL documentation](https://www.postgresql.org/docs/current/)
- PostgreSQL wiki: [Don't Do This](https://wiki.postgresql.org/wiki/Don't_Do_This)
- Decomplexify: *Learn Database Normalization – 1NF, 2NF, 3NF, 4NF, 5NF*
