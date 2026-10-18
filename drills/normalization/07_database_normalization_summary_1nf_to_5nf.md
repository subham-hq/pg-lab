# Database Normalization — Summary (1NF to 5NF + BCNF)

Database normalization is the process of organizing relational tables so that facts are stored in suitable places, unnecessary repetition is reduced, and data can be inserted, updated, or deleted without causing inconsistencies.

**The three classic problems normalization helps prevent:**

- **Insertion anomaly:** You cannot record one fact without inventing or supplying an unrelated fact.
- **Update anomaly:** The same fact appears in several rows, so updating only some rows creates conflicting information.
- **Deletion anomaly:** Removing one record unintentionally removes another fact you wanted to preserve.

Normalization proceeds through increasingly strict **normal forms**. Each form assumes the requirements of the earlier forms have been met.

## The concepts behind the rules

- **Candidate key:** A minimal set of columns that uniquely identifies a row.
- **Composite key:** A key made from more than one column, such as `(Player_ID, Item_Type)`.
- **Superkey:** Any set of columns that uniquely identifies a row; it may contain extra columns.
- **Prime attribute:** A column that belongs to *at least one* candidate key.
- **Non-prime attribute:** A column that belongs to *no* candidate key.
- **Functional dependency (`X → Y`):** Knowing `X` determines exactly one value of `Y` (under the table's business rules).
- **Multivalued dependency (`X ↠ Y`):** For a given `X`, a set of `Y` values varies independently of the other attributes.
- **Join dependency:** A table can be reconstructed exactly by joining specified projections (smaller tables), without adding or losing rows.

## First Normal Form (1NF) — One fact per field, no repeating groups

**Main idea:** Represent data as a proper relational table with well-defined columns and values, rather than packing repeating items into one row.

**Bad design:**

| Player_ID | Inventory |
|---|---|
| trev73 | 3 shields, 5 arrows, 30 copper coins, 7 rings |

**Better design:**

| Player_ID | Item_Type | Item_Quantity |
|---|---|---:|
| trev73 | shields | 3 |
| trev73 | arrows | 5 |
| trev73 | copper coins | 30 |
| trev73 | rings | 7 |

Also avoid columns such as `Item_Type_1`, `Item_Type_2`, `Quantity_1`, `Quantity_2` when they represent a repeating group. Store the item types in rows instead.

**Other good relational design habits from Decomplexify:**

- **Do not rely on row position to represent meaning.** Store an explicit `rank` or `position` column if order matters; query with `ORDER BY` when displaying it.
- **Give each column one clear domain and meaning.** Do not store unrelated text and numeric meanings in the same field.
- **Use an appropriate primary key in actual database design.** Here `(Player_ID, Item_Type)` can identify each inventory entry, assuming each player has one row per item type.

*Precision note:* Declaring a SQL `PRIMARY KEY` constraint, or using a particular SQL data type, is not by itself the formal definition of 1NF. These are valuable design and integrity practices emphasized in the tutorial.

## Second Normal Form (2NF) — Depend on the whole key

**Rule:** A table is in 1NF, and every **non-prime attribute** is fully dependent on every candidate key—not just part of a composite key.

Consider `Player_Inventory` with key `(Player_ID, Item_Type)`:

| Player_ID | Item_Type | Item_Quantity | Player_Rating |
|---|---|---:|---|
| jdog21 | amulets | 2 | Intermediate |
| jdog21 | rings | 4 | Intermediate |

Dependencies:

- `(Player_ID, Item_Type) → Item_Quantity` ✅ Both parts identify the item's quantity.
- `Player_ID → Player_Rating` ❌ The rating depends only on part of the composite key (**partial dependency**).

**Fix: Split into two tables.**

`Player(Player_ID, Player_Rating)`

`Player_Inventory(Player_ID, Item_Type, Item_Quantity)`

Now the rating is stored once per player. A new player can exist without inventory, and changing the rating doesn't require updating multiple inventory rows.

**Memory phrase:** *2NF removes partial dependencies on candidate keys.*

## Third Normal Form (3NF) — No problematic dependency through another non-key attribute

**Main idea:** A non-key fact should not be stored as a repeated consequence of another non-key fact.

In the video's `Player` example, a numeric skill level determines the rating:

- `Player_ID → Player_Skill_Level`
- `Player_Skill_Level → Player_Rating`
- So `Player_ID → Player_Skill_Level → Player_Rating` is a **transitive dependency**.

**Problematic table:**

| Player_ID | Player_Skill_Level | Player_Rating |
|---|---:|---|
| jdog21 | 4 | Intermediate |
| gila19 | 4 | Beginner ❌ |
| trev73 | 8 | Advanced |

The same level `4` has inconsistent ratings because the rating rule is duplicated in player records.

**Fix: Split into two tables.**

`Player(Player_ID, Player_Skill_Level)`

`Player_Skill_Levels(Player_Skill_Level, Player_Rating)`

The mapping `4 → Intermediate` now lives in exactly one place.

**Precise 3NF rule:** For every nontrivial functional dependency `X → A`, either **`X` is a superkey** or **`A` is a prime attribute** (part of some candidate key). The familiar phrase *“the key, the whole key, and nothing but the key”* is a useful shortcut, but not the complete formal rule.

## Boyce–Codd Normal Form (BCNF) — Every determinant must be a superkey

**Rule:** For every nontrivial functional dependency `X → Y`, **`X` must be a superkey**.

BCNF is stricter than 3NF because **it does not allow 3NF's prime-attribute exception**.

**An example that meets 3NF but fails BCNF:**

`Enrollment(Student, Course, Instructor)` with these business rules:

1. A student has exactly one instructor for each course: `(Student, Course) → Instructor`.
2. Each instructor teaches just one course: `Instructor → Course`.

Candidate keys are `(Student, Course)` and `(Student, Instructor)`. Therefore, `Course` is a *prime* attribute, and `Instructor → Course` is allowed by **3NF**. But `Instructor` is **not a superkey**, so this dependency **violates BCNF**.

**BCNF decomposition:**

- `Instructor_Course(Instructor, Course)`
- `Student_Instructor(Student, Instructor)`

**Difference in one line:** 3NF sometimes tolerates a dependency whose right-hand attribute belongs to a candidate key; BCNF requires the left-hand side to be a superkey in every nontrivial functional dependency.

## Fourth Normal Form (4NF) — Separate independent sets of choices

**Main idea:** If one entity has two *independent* multi-valued facts, don't store every combination in one table.

A birdhouse model **Tweety** has colours `Yellow` and `Blue`, and styles `Bungalow` and `Duplex`. If any colour works with any style, a combined table needs four rows:

| Model | Color | Style |
|---|---|---|
| Tweety | Yellow | Bungalow |
| Tweety | Yellow | Duplex |
| Tweety | Blue | Bungalow |
| Tweety | Blue | Duplex |

Here, `Model ↠ Color` and `Model ↠ Style` describe independent multivalued dependencies. Adding a third colour would require another row for **each** style.

**Fix:**

- `Model_Colors_Available(Model, Color)`
- `Model_Styles_Available(Model, Style)`

**Precise 4NF rule:** For every nontrivial multivalued dependency `X ↠ Y`, `X` must be a superkey.

**Important assumption:** The split works only when the available colours and styles are independent. If some colour–style combinations are forbidden, storing the two lists alone would invent invalid combinations.

## Fifth Normal Form (5NF) — Split only when the smaller relations join back exactly

**Main idea:** Sometimes a relationship involving **three or more entities** can be represented without redundant combinations by joining smaller relations. This is about **join dependencies**.

From Decomplexify's ice-cream example, consider a triple:

`Preferred_Ice_Cream(Person, Brand, Flavor)`

Under the specific business rule that a combination is valid **if and only if**:

1. The person likes the brand;
2. The person likes the flavour; and
3. That brand sells the flavour;

we can store three smaller tables:

- `Preferred_Brands_By_Person(Person, Brand)`
- `Preferred_Flavors_By_Person(Person, Flavor)`
- `Available_Flavors_By_Brand(Brand, Flavor)`

Joining **all three** recreates the intended `(Person, Brand, Flavor)` combinations, without separately maintaining each triple.

**Precise 5NF rule:** Every nontrivial join dependency must be implied by the candidate keys.

**Important assumption:** If a person likes a flavour *only from a particular brand*, even though they generally like that flavour and brand, the three-table join could generate a false combination. In that case, this decomposition would **not** be lossless relative to the intended facts. The business rules—not just the presence of matching columns—determine whether 5NF decomposition is valid.

## All the normal forms at a glance

| Form | Main question | What it addresses |
|---|---|---|
| **1NF** | Are values stored cleanly without repeating groups? | Repeating items / improperly structured records |
| **2NF** | Do non-prime attributes depend on the **whole** candidate key? | Partial functional dependencies |
| **3NF** | Are there functional dependencies that improperly pass through other non-key facts? | Common transitive dependencies |
| **BCNF** | Is every nontrivial FD determined by a **superkey**? | FDs still permitted by 3NF's exception |
| **4NF** | Are independent multivalued facts stored separately? | Nontrivial MVDs with non-superkey determinants |
| **5NF** | Can the relation be losslessly decomposed based on a non-key-implied join dependency? | Redundant multiway relationships |

**Progression:** `1NF → 2NF → 3NF → BCNF → 4NF → 5NF`

**Practical takeaway:** Normalization is not about splitting tables as much as possible. It is about matching table structure to **real business dependencies** while preserving information. Every proposed split should have a sound reason and, when intended as a normalization step, reconstruct the original valid facts without losing or inventing rows.
