# First Normal Form (1NF)

*Study notes based on Decomplexify's 1NF lesson and the supplied Player_Inventory screenshots.*

## What is 1NF?

**First Normal Form (1NF)** is the starting point for organizing data as a relational table. In practical database design, it means keeping attributes well-defined, storing values in a consistent way, and avoiding lists or repeating sets of columns that really represent multiple records.

A useful rule of thumb is:

> **One cell = one value of the intended attribute. One inventory item type = one inventory row.**

In the lesson, Decomplexify highlights four design rules:

1. Do not rely on **row order** to convey information.
2. Do not mix **data types or meanings** in a single column.
3. Give records a reliable **unique key**.
4. Do not store **repeating groups** within a single row.

These are useful teaching guidelines. Strictly speaking, having an explicitly declared SQL `PRIMARY KEY` is a **recommended constraint**, not the formal definition of 1NF. The examples below focus on the practical database-design lessons.

## Rule 1: Row order must not carry meaning

A table does **not** promise that rows are stored or returned in a particular order.

### Bad design: “The first row is first place”

| player_id | score |
|---|---:|
| `jdog21` | 900 |
| `trev73` | 700 |
| `gila19` | 500 |

If an application assumes the top row is the winner, it relies on display position instead of actual data. A database query may return these rows in another order.

### Better design

If ranking is determined by score, calculate the ranking order when you query:

```sql
SELECT player_id, score
FROM player_scores
ORDER BY score DESC, player_id;
```

If a position is an **independent fact** you must preserve—such as a manually assigned tournament finishing place—store that position in an explicit column instead of relying on row placement.

**Remember:** An `ORDER BY` sorts a query's **output**; it does not give a table a permanent row order.

## Rule 2: A column should have one consistent type and meaning

Each column should represent one clearly defined attribute.

### Bad design

| player_id | item_quantity |
|---|---|
| `jdog21` | `2` |
| `gila19` | `many` |
| `trev73` | `7 rings` |

The `item_quantity` column sometimes holds a number, sometimes a vague word, and sometimes a quantity mixed with an item name. Calculating totals becomes unreliable.

### Better design

| player_id | item_type | item_quantity |
|---|---|---:|
| `jdog21` | amulets | 2 |
| `gila19` | copper coins | 18 |
| `trev73` | rings | 7 |

Now `item_quantity` can be an `INTEGER`, while `item_type` can be `TEXT`.

**PostgreSQL detail:** A SQL column normally already has a declared type. Putting `'7 rings'` in a `TEXT` column isn't literally storing two SQL types; the problem is that **two different meanings** have been packed into one field. Structured types such as arrays and JSON have legitimate uses, but are generally not a good replacement for separate inventory records when items need independent querying and updating.

## Rule 3: Identify each record using a suitable key

A **primary key** uniquely identifies a row. Other columns are allowed to repeat.

Consider this inventory:

| player_id | item_type | item_quantity |
|---|---|---:|
| `jdog21` | amulets | 2 |
| `jdog21` | rings | 4 |
| `trev73` | rings | 7 |

`player_id` alone **cannot** be the primary key: `jdog21` legitimately appears twice because that player owns two kinds of items.

### Composite key

If each player can have only one row per item type, this pair uniquely identifies a record:

```text
(player_id, item_type)
```

- (`jdog21`, `amulets`) identifies one row.
- (`jdog21`, `rings`) identifies another.
- (`trev73`, `rings`) identifies another.

The individual columns can repeat; **the combination cannot**.

A PostgreSQL table could enforce this design:

```sql
CREATE TABLE player_inventory (
    player_id     TEXT NOT NULL,
    item_type     TEXT NOT NULL,
    item_quantity INTEGER NOT NULL CHECK (item_quantity >= 0),
    PRIMARY KEY (player_id, item_type)
);
```

You could instead use an `inventory_id` primary key with `UNIQUE (player_id, item_type)`. If multiple independent stacks of the same item type are allowed, the data model would need a different key.

**Important nuance:** Defining an appropriate key is crucial for reliable SQL tables, but a declared `PRIMARY KEY` constraint is not *by itself* what defines 1NF.

## Rule 4: Do not store repeating groups in a single row

This is the main idea illustrated by Decomplexify's **Player_Inventory** screenshots.

### Bad version A: A list in one cell

| Player_ID | Inventory |
|---|---|
| `trev73` | 3 shields, 5 arrows, 30 copper coins, 7 rings |

The single `Inventory` cell actually contains **four different item-and-quantity facts**. Updating just the arrow count or finding everybody with rings requires interpreting text.

### Bad version B: Numbered, repeating columns

The first screenshot uses a column layout like this:

| Player_ID | Quantity_1 | Item_Type_1 | Quantity_2 | Item_Type_2 | Quantity_3 | Item_Type_3 | Quantity_4 | Item_Type_4 |
|---|---:|---|---:|---|---:|---|---:|---|
| `jdog21` | 2 | amulets | 4 | rings | — | — | — | — |
| `gila19` | 18 | copper coins | — | — | — | — | — | — |
| `trev73` | 3 | shields | 5 | arrows | 30 | copper coins | 7 | rings |

This still stores a repeating *set of attributes* on one row. It causes several problems:

- **Limited capacity:** A fifth item type needs `Quantity_5` and `Item_Type_5` columns.
- **Wasted space:** Players with fewer items leave many cells empty.
- **Awkward queries:** Finding all rings requires checking `Item_Type_1`, `Item_Type_2`, etc.
- **Harder maintenance:** The same concept (“item type”) is spread across many numbered columns.

Even though each individual cell seems to contain one value, the **repeating group of columns** makes this design unsuitable.

### Correct version: One item type per row

The second screenshot shows the corrected `Player_Inventory` table:

| Player_ID | Item_Type | Item_Quantity |
|---|---|---:|
| `jdog21` | amulets | 2 |
| `jdog21` | rings | 4 |
| `gila19` | copper coins | 18 |
| `trev73` | shields | 3 |
| `trev73` | arrows | 5 |
| `trev73` | copper coins | 30 |
| `trev73` | rings | 7 |

Each row has a clear meaning. For example:

> `trev73` has **5 arrows**.

Why this version is better:

- To add another item type, **insert a row**, not new columns.
- To change arrow quantity, **update the row for (`trev73`, `arrows`)**.
- To find players with rings, filter `Item_Type = 'rings'`.
- Repeated `Player_ID` values are **expected**: one player can own multiple kinds of items.

For example:

```sql
SELECT item_type, item_quantity
FROM player_inventory
WHERE player_id = 'trev73'
ORDER BY item_type;
```

If a player must exist even when they own no items, maintain a separate `players` table. The absence of inventory rows should not erase the player.

## Important distinctions

**A repeated player ID is not a repeating group.** The corrected table repeats `player_id` across *different inventory records*. The bad design repeats *item slots* (`Item_Type_1`, `Item_Type_2`, etc.) inside one record.

**One cell, one value is a useful shortcut, not a complete definition.** Whether a value is sufficiently atomic depends on what it means in the application. For instance, a person's display name can be treated as one value even though it contains spaces.

**1NF does not eliminate every data anomaly.** It establishes a clean tabular foundation; later normal forms deal with further dependency and redundancy issues.

**The central idea:** Store each independently meaningful inventory entry as its own row, with clear attributes and an appropriate key, rather than packaging many entries into one cell or one set of numbered columns.
