# pg-lab

A hands-on PostgreSQL lab: notes that run, drills that measure, and a final checkpoint taken cold.

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-7AA2F7?style=flat-square&labelColor=1A1B27&logo=postgresql&logoColor=white)
![Status](https://img.shields.io/badge/status-in%20progress-E0AF68?style=flat-square&labelColor=1A1B27)

## Why this exists

> ✍️ **Subham to write:** 2–3 sentences in your own words. Why PostgreSQL, why now, and what you want to be able to do by the end.

## How this lab works

- **Every file runs.** Each notes file rebuilds its data from scratch and runs top to bottom without errors. That's checked before every commit.
- **Typed, not pasted.** Queries are typed by hand in `psql`. Nothing is copied from a video.
- **Evidence over summaries.** Drills record real `EXPLAIN ANALYZE` plans, timings and two-session transcripts: numbers, not claims.
- **One gate at the end.** The lab is done when the checkpoint is passed cold, with no notes and no videos.

## Progress

✅ done · 🚧 in progress · ⬜ not started

| # | Topic | Source | Output | Status |
|:-:|---|---|---|:-:|
| 1 | Setup, SELECT, WHERE, ORDER BY, LIMIT, IN | freeCodeCamp · part 1 | `notes/01-basics.sql` | 🚧 |
| 2 | GROUP BY, aggregates, NULLs, dates and intervals | freeCodeCamp · part 2 | `notes/02-aggregates.sql` | ⬜ |
| 3 | Keys, constraints, UPDATE / DELETE, upserts | freeCodeCamp · part 3 | `notes/03-constraints.sql` | ⬜ |
| 4 | Foreign keys, JOINs, sequences, UUIDs + Pagila drill | freeCodeCamp · part 4 | `drills/pagila-tier1.sql` | ⬜ |
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

## Proof-of-skill drills

| Drill | What it proves | Headline result |
|---|---|---|
| #1 Index performance | Read a slow plan, add the right index, measure the win | _pending_ |
| #2 Isolation levels | Reproduce each read anomaly in two live sessions, and the level that prevents it | _pending_ |
| #3 Normalization | Turn a messy spec into a 3NF/BCNF schema whose constraints reject bad data | _pending_ |

## Checkpoint

Done when all three pass with no notes, no videos, and a timer running:

1. Design a normalized schema from a spec never seen before.
2. Read a slow query's `EXPLAIN ANALYZE`, add the right index, and prove the speed-up.
3. Explain each isolation level and the anomaly it prevents, out loud.

## Repository layout

```
pg-lab/
├── data/      generated practice data (Mockaroo)
├── notes/     one file per lesson, runnable top to bottom
├── drills/    exercises with measured results
└── README.md
```

## Run it yourself

Requires PostgreSQL 18. On macOS, [Postgres.app](https://postgresapp.com) is the simplest install.

```bash
createdb lab
psql lab -v ON_ERROR_STOP=1 -f notes/01-basics.sql > /dev/null && echo "runs clean"
```

From topic 4 on, the drills use the [Pagila](https://github.com/devrimgunduz/pagila) sample database, loaded into its own database:

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
- Comments explain surprises, not syntax

## Resources

- freeCodeCamp: *Learn PostgreSQL Tutorial – Full Course for Beginners*
- Hussein Nasser: [Database Engineering](https://www.youtube.com/@hnasr) playlist
- Andy Pavlo: [CMU 15-445/645 Intro to Database Systems](https://15445.courses.cs.cmu.edu)
- Markus Winand: [Use The Index, Luke](https://use-the-index-luke.com)
- [PostgreSQL documentation](https://www.postgresql.org/docs/current/)
- Decomplexify: *Learn Database Normalization – 1NF, 2NF, 3NF, 4NF, 5NF*

## What I've learned

> ✍️ **Subham to write**, updated as you go. The gotcha lines at the bottom of each notes file are good raw material.