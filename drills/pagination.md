# Pagination, Indexes, B-Trees & B+Trees

A practical note on why databases use indexes, how B-tree structures make lookups efficient, and why pagination strategy matters.

## 1. The problem: finding one row in a large table

Imagine a PostgreSQL table with one million rows. If the database has no useful index for a query, it may need to perform a **sequential scan**: read rows (and the pages containing them) and check which ones match.

That can mean examining a huge amount of data just to find one row.

The central idea behind database performance is often:

> Reduce the search space. Avoid examining rows that cannot possibly be part of the answer.

There are different ways to do that:

- **Partitioning** divides a table into smaller, manageable pieces according to a partitioning rule.
- **Indexes** create a separate lookup structure that helps the database find relevant rows or pages without scanning the whole table.

An index usually stores indexed key values plus information that helps the database reach the corresponding table row (or, in some database designs, the row data itself).

## 2. From a binary tree to a B-tree

A basic **binary search tree** keeps smaller keys on the left and larger keys on the right. To search, start at the root, compare the target with the current key, and follow the appropriate branch.

The problem is that an ordinary binary search tree is not guaranteed to stay balanced. If keys arrive in an unfortunate order—for example, 1, 2, 3, 4, 5—the tree can become almost a linked list. Searching it may then take many steps.

A **B-tree** solves this by keeping the tree balanced as keys are inserted and removed. A node can contain multiple sorted keys and have more than two children. Those keys divide the values into ranges, telling the search which child to follow.

### The trade-off: balancing costs work

When a node becomes full, the tree may split it and promote a separator key to its parent. This can cause more changes higher up the tree.

So a B-tree is not “free speed”:

- Reads benefit from a shallow, balanced structure.
- Inserts and deletes sometimes pay the cost of splits, merges, and other balancing work.

This is a useful engineering trade-off: spend some work maintaining the index so future lookups can be faster.

*Terminology note:* “Order” and “degree” are defined differently in different explanations. In a simple example where a node can have at most 3 children, it can hold at most 2 separator keys. Real database node capacity is based on page size and the size of the indexed values and pointers—not a tiny fixed degree like 3.

## 3. B-tree vs B+Tree

The key difference in the common textbook comparison is where the row references or records are stored.

### B-tree

- Keys and associated record references/data can appear in both internal nodes and leaves.
- A search may find its record reference before reaching a leaf.
- Since internal nodes carry more information per key, they may fit fewer keys in a page.

### B+Tree

- Internal nodes mainly contain separator keys and child pointers. They guide the search.
- The actual record references (or row entries) are stored at the leaf level.
- Leaf pages are linked in key order, making it easy to continue from one matching key to the next.

This design gives B+Trees two important advantages:

1. **Higher fan-out:** internal pages can hold more separator keys because they do not carry the full row references/data for every key. More children per internal page generally means a shallower tree.
2. **Efficient range scans:** find the first matching leaf entry, then follow the linked leaves rather than repeatedly searching from the root.

For example, to find all keys from 100 through 500, the database can seek to 100 and scan forward through the ordered leaf entries until it passes 500.

The extra leaf links and repeated separator keys take some space, but can be a worthwhile trade-off for lookups and range scans.

### How this relates to PostgreSQL

PostgreSQL stores tables and indexes in fixed-size pages (commonly 8 KB by default, though the build can differ). Its standard `btree` index access method is a balanced, multi-level structure with internal pages and leaf pages; leaf entries identify table tuples. It is often explained using B+Tree concepts, especially the separation between navigation pages and leaf entries.

Do not assume every database implements an identical textbook B+Tree. The video’s B-tree/B+Tree comparison is a useful conceptual model; implementation details vary by database.

## 4. What pagination does

An application rarely wants to return every matching row at once. A product list, activity feed, or admin table might show 20 rows and let the user load more.

**Pagination** divides a result set into smaller batches. Two common approaches are OFFSET and keyset (cursor) pagination.

### OFFSET pagination

```sql
SELECT id, created_at
FROM products
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 0;
```

For a later page:

```sql
SELECT id, created_at
FROM products
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 99980;
```

`LIMIT 20` returns at most 20 rows. `OFFSET 99980` asks the database to move past the first 99,980 rows in the ordered result before returning the next 20.

This is convenient and supports jumping directly to a page number. But deep pages can be expensive: the database still has to walk past the skipped entries. An index can help with ordering and filtering, but it does not make a large OFFSET free.

### Keyset pagination (the seek method)

Instead of saying “skip 99,980 rows,” keyset pagination says “continue after the last row I received.”

Suppose the previous page ended at:

- `created_at = '2026-11-14 10:30:00'`
- `id = 103`

The next page can use that pair as a **cursor**:

```sql
SELECT id, created_at
FROM products
WHERE (created_at, id) < ($1, $2)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

For descending order, the `<` comparison asks for rows after that cursor in the result order. The exact cursor values come from the final row of the previous page.

The two columns matter:

- `created_at` gives the primary sort order.
- `id` is a unique **tie-breaker**. Multiple rows can have the same timestamp; adding a unique key makes the order deterministic and avoids ambiguous page boundaries.

A matching index is important:

```sql
CREATE INDEX products_created_id_idx
ON products (created_at DESC, id DESC);
```

With a suitable index, PostgreSQL can seek to the cursor position and read the next entries instead of walking through every earlier page. Keyset pagination is especially useful for feeds and large result sets.

## 5. OFFSET vs keyset: which should you use?

| Consideration | OFFSET | Keyset |
|---|---|---|
| Jump to page 500 | Easy | Not naturally supported |
| Deep pagination | Can become expensive | Usually efficient with a matching index |
| Implementation | Simple | Needs cursor handling |
| Changing data between requests | Rows can shift, causing duplicates or omissions | More stable when using a deterministic sort, though concurrent changes can still affect results |
| Good fit | Small tables, page-number navigation, reports | Feeds, timelines, APIs, large ordered result sets |

Keyset is not a universal replacement for OFFSET. It trades arbitrary page-number navigation for efficient continuation from a known position.

## 6. Try it in PostgreSQL

Use a table with roughly one million rows and compare a shallow page with a deep page. Make sure both approaches use the same deterministic ordering.

Run each query with:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, created_at
FROM products
ORDER BY created_at DESC, id DESC
LIMIT 20 OFFSET 99980;
```

Then compare it with a keyset query using a cursor around the same position:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, created_at
FROM products
WHERE (created_at, id) < ($1, $2)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

Look at:

- **Execution Time:** how long the query took.
- **Actual Rows:** how many rows each plan node processed or returned.
- **Buffers:** how many database pages were read from cache or storage.
- **Scan type and index conditions:** whether the intended index was used.

Do not judge only by one timing. Run the tests more than once, keep the data and index setup consistent, and compare the execution plans as well as the timings.

## The main ideas to remember

1. A full scan can be expensive because it examines a large amount of data.
2. An index reduces the search space; a B-tree keeps that lookup structure balanced.
3. B+Tree-style leaf organization is especially useful for ordered range scans.
4. OFFSET is simple, but deep offsets make the database walk past many rows.
5. Keyset pagination continues from a cursor. Use a deterministic sort with a unique tie-breaker and an index that matches the ordering.
6. Choose based on the product requirement: direct page jumps or efficient “load the next batch.”

The goal is not to memorize tree terminology or SQL syntax. It is to understand what work the database must do—and how the data structure and query design can avoid unnecessary work.
