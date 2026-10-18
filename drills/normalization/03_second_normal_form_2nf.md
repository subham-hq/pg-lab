# Second Normal Form (2NF)

**Source:** Decomplexify — Database Normalization (2NF)  
**Example:** `Player_Inventory` from the lesson screenshots

## What is Second Normal Form?

A table is in **Second Normal Form (2NF)** when:

1. It is already in **First Normal Form (1NF)**.
2. Every **non-key attribute** depends on the **entire candidate key**, not just part of a composite candidate key.

The simple idea: **Store each fact with the thing that determines it.** If a fact describes a player, it should not have to be repeated on every inventory row belonging to that player.

> In the lesson's example, the primary key has two columns, so we can think of the rule as: *Every non-key column must depend on both parts of the primary key together.*

## 1. Understand the key first

The original table holds one row for each item type owned by each player:

### `Player_Inventory` — in 1NF, but not 2NF

| Player_ID | Item_Type | Item_Quantity | Player_Rating |
|---|---|---:|---|
| jdog21 | amulets | 2 | Intermediate |
| jdog21 | rings | 4 | Intermediate |
| gila19 | copper coins | 18 | Beginner |
| trev73 | shields | 3 | Advanced |
| trev73 | arrows | 5 | Advanced |
| trev73 | copper coins | 30 | Advanced |
| trev73 | rings | 7 | Advanced |

The **composite primary key** is:

`(Player_ID, Item_Type)`

A composite key uses **multiple columns together** to uniquely identify a row.

- `Player_ID` alone is **not unique**: `jdog21` owns both amulets and rings.
- `Item_Type` alone is **not unique**: different players can own rings.
- `(Player_ID, Item_Type)` **is unique**: assuming each player has only one inventory row per item type, the combination identifies one inventory entry.

The columns `Item_Quantity` and `Player_Rating` are **non-key attributes** because neither is part of this primary key.

## 2. What does “depends on” mean?

A **functional dependency** means that knowing the value on the left determines exactly one value on the right.

We write it like this:

`A → B`

Read it as: **“A determines B.”**

For example, if a player's rating is a single property of that player:

`Player_ID → Player_Rating`

Knowing `jdog21` tells us that player's rating. We do **not** need to know which item the player owns.

But to know the number of rings a player owns, we need *both* pieces of information:

`(Player_ID, Item_Type) → Item_Quantity`

Knowing only `Player_ID` isn't enough: the player may own 2 amulets and 4 rings. Knowing only `Item_Type` isn't enough: different players may own different quantities of rings.

### Full dependency versus partial dependency

**Full dependency:** The non-key attribute needs the **whole composite key**.

- `(Player_ID, Item_Type) → Item_Quantity` ✅
- `Item_Quantity` describes **this player's quantity of this particular item**.

**Partial dependency:** The non-key attribute can be determined by **only part of the composite key**.

- `Player_ID → Player_Rating` ❌ (for 2NF in this table)
- `Player_Rating` describes the **player**, regardless of the item.
- `Item_Type` adds no information needed to determine the rating.

This is the exact problem highlighted in the Decomplexify screenshots: **`Player_Rating` depends on only `Player_ID`, even though the table's primary key is `(Player_ID, Item_Type)`.**

The table can satisfy **1NF**—one value per cell and one inventory item per row—while still **violating 2NF** because of this partial dependency.

## 3. Why does a partial dependency cause problems?

Repeating `Player_Rating` on every inventory row creates three possible anomalies.

### Insertion anomaly

The lesson introduces a new player:

| Player_ID | Player_Rating |
|---|---|
| tina42 | Beginner |

But `tina42` **has no inventory items yet**.

In the original table, we cannot represent this player properly without also providing an `Item_Type`: it is part of the composite primary key. We would have to invent an item, delay inserting the player, or redesign the schema.

**Problem:** We cannot save a player's rating independently of their inventory.

### Update anomaly

Suppose `jdog21` improves from **Intermediate** to **Advanced**.

Because the rating appears on multiple inventory rows, we must update all of them:

| Player_ID | Item_Type | Player_Rating |
|---|---|---|
| jdog21 | amulets | Advanced |
| jdog21 | rings | Intermediate |

If we update only the amulets row, the same player now has **two contradictory ratings**. This is the inconsistency shown in the screenshots.

**Problem:** One change must be repeated in several rows, and missing a row makes the data inconsistent.

### Deletion anomaly

Suppose `gila19` owns only **18 copper coins** and decides to remove them all.

If we delete the player's only inventory row, we also delete the **only stored record that `gila19` is a Beginner**.

**Problem:** Deleting an inventory fact accidentally removes a separate player fact.

These anomalies share one cause: **information about a player is stored inside rows describing that player's items**.

## 4. Convert the table into 2NF

The fix is to separate **player facts** from **inventory facts**.

### Table A: `Player`

| Player_ID (PK) | Player_Rating |
|---|---|
| jdog21 | Intermediate |
| gila19 | Beginner |
| trev73 | Advanced |
| tina42 | Beginner |

- **Primary key:** `Player_ID`
- **Dependency:** `Player_ID → Player_Rating`
- Each player appears **once**, even when they own no items.

### Table B: `Player_Inventory`

| Player_ID (PK, FK) | Item_Type (PK) | Item_Quantity |
|---|---|---:|
| jdog21 | amulets | 2 |
| jdog21 | rings | 4 |
| gila19 | copper coins | 18 |
| trev73 | shields | 3 |
| trev73 | arrows | 5 |
| trev73 | copper coins | 30 |
| trev73 | rings | 7 |

- **Composite primary key:** `(Player_ID, Item_Type)`
- **Dependency:** `(Player_ID, Item_Type) → Item_Quantity`
- **Foreign key:** `Player_Inventory.Player_ID` references `Player.Player_ID`.

Now `Player_Rating` is stored only in `Player`. `Player_Inventory` stores only the quantity associated with a specific player–item combination.

### Why the anomalies are fixed

- **Insert `tina42`:** Add a row to `Player` even though they have no inventory.
- **Update `jdog21`'s rating:** Change **one** row in `Player`.
- **Delete `gila19`'s copper coins:** Remove the inventory row while preserving the player's rating in `Player`.

When we need a player's inventory **and** rating, we can retrieve them by joining these two tables on `Player_ID`.

## 5. How the 2NF design looks in PostgreSQL

```sql
CREATE TABLE player (
    player_id TEXT PRIMARY KEY,
    player_rating TEXT NOT NULL
);

CREATE TABLE player_inventory (
    player_id TEXT NOT NULL REFERENCES player(player_id),
    item_type TEXT NOT NULL,
    item_quantity INTEGER NOT NULL CHECK (item_quantity >= 0),
    PRIMARY KEY (player_id, item_type)
);
```

Notice the two different roles of `player_id`:

- In `player`, it is the **primary key** and identifies one player.
- In `player_inventory`, it is part of the **composite primary key** and also a **foreign key** that connects each inventory entry to an existing player.

To view a player's items alongside their rating:

```sql
SELECT
    p.player_id,
    p.player_rating,
    pi.item_type,
    pi.item_quantity
FROM player AS p
JOIN player_inventory AS pi
    ON p.player_id = pi.player_id;
```

The join brings the information together **when we need it**; we do not need to duplicate `Player_Rating` in the stored inventory rows.

## 6. An important nuance about the rule

Decomplexify states: **“Each non-key attribute must depend on the entire primary key.”** This is a useful way to learn 2NF for the displayed example.

The more precise database-theory definition is:

> A relation is in 2NF if it is in 1NF and **no non-prime attribute is partially dependent on any candidate key**.

A **candidate key** is any minimal set of attributes capable of uniquely identifying a row. A **prime attribute** is an attribute belonging to at least one candidate key. The designated primary key is just one chosen candidate key.

In our example, `(Player_ID, Item_Type)` is the relevant composite candidate key, and `Player_Rating` depends on only one part of it. That's why the table violates 2NF.

**A table with only single-column candidate keys cannot have a partial-key dependency**, so once it is in 1NF, it meets the 2NF requirement. That does **not** mean it is automatically a perfect design; it only means 2NF's specific issue is absent.

## Remember the central idea

**1NF** makes inventory entries properly row-based instead of storing repeated groups in one row.

**2NF** asks a new question: **“Does every non-key fact belong to the whole key, or does it actually describe only part of that key?”**

For this example:

- **Player rating** belongs to **the player** → `Player`.
- **Item quantity** belongs to **the player + item combination** → `Player_Inventory`.

That's why we split one table into two.
