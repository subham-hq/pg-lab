# Third Normal Form (3NF) and Boyce–Codd Normal Form (BCNF)

> **Source context:** Decomplexify's database-normalization lesson, using the `Player`, `Player_Inventory`, and `Player_Skill_Levels` examples shown in the screenshots. This note covers **3NF and BCNF together** because the key difference between them is easier to understand side by side.

## 1. Where 3NF fits

Database normalization helps us organize data so that a fact is stored in the right place instead of being repeated unnecessarily. This reduces inconsistent information and insertion, update, and deletion anomalies.

We have already seen:

- **1NF:** Avoid repeating groups and make each row/column represent a clear value and fact.
- **2NF:** Build on 1NF and eliminate **partial dependencies** of non-prime attributes on part of a candidate key (especially important with composite keys).
- **3NF:** Build on 2NF and deal with dependencies where a non-key attribute determines another non-key attribute—often called **transitive dependencies**.
- **BCNF:** Apply a stricter rule to *all* functional dependencies: the attributes determining another attribute must form a **superkey**.

The central question now is: **Which fact depends on which identifier?**

## 2. Understand functional dependencies first

A **functional dependency** is written as:

```text
X → Y
```

It means: **If two rows agree on X, they must also agree on Y.** In other words, knowing X determines exactly one Y value *under the business rules*.

For the game example:

```text
Player_ID → Player_Skill_Level
Player_Skill_Level → Player_Rating
```

- A particular player has one current skill level.
- A particular skill level corresponds to one rating.

For this example, the game's rating rules are:

| Player skill level | Player rating |
|---|---|
| 1, 2, 3 | Beginner |
| 4, 5, 6 | Intermediate |
| 7, 8, 9 | Advanced |

**Important:** A functional dependency is about the *rules of the data*, not simply a pattern that happens to appear in a few example rows. Also, `Skill_Level → Rating` does **not** mean `Rating → Skill_Level`: several skill levels share the same rating.

## 3. Third Normal Form (3NF)

### Simple definition

**A table is in 3NF when it is in 2NF and its non-key facts do not depend on other non-key facts instead of being determined directly by a key.**

A useful teaching phrase from the video is:

> Every non-key attribute should depend on **the key, the whole key, and nothing but the key**.

This describes the main design goal. Later in this note, we'll clarify the precise technical definition, which is slightly more nuanced.

### A transitive dependency

Imagine three attributes:

```text
A → B
B → C
```

It follows that:

```text
A → C
```

So **C depends on A through B**. This is a *transitive dependency*.

In our example:

```text
Player_ID → Player_Skill_Level → Player_Rating
```

`Player_Rating` is determined by `Player_Skill_Level`, which is itself determined by `Player_ID`.

The problem is **not** that the player ID fails to determine the rating; it does. The problem is that the rating is a fact about **skill levels**, but we're storing it repeatedly on **player rows**.

### Before 3NF: The Player table from the screenshots

**`Player`** — primary key: `Player_ID`

| Player_ID | Player_Rating | Player_Skill_Level |
|---|---|---:|
| jdog21 | Intermediate | 4 |
| gila19 | Beginner | 4 |
| trev73 | Advanced | 8 |
| tina42 | Beginner | 1 |

Notice the issue: `jdog21` and `gila19` both have skill level `4`, but the ratings disagree. Level 4 should be **Intermediate** according to the game's rules. The screenshot deliberately highlights `gila19` as an inconsistency.

This table can satisfy **2NF** because its primary key is a single column (`Player_ID`), so there is no *part* of a composite key on which a non-key attribute could depend. But it has the transitive dependency shown above, so **it is not in 3NF**.

### Why this design causes anomalies

**Update anomaly:** If the rating assigned to a skill level changes, many player rows may need updating. Missing even one row creates conflicting ratings for the same skill level. The screenshot's level-4 disagreement illustrates this risk.

**Insertion anomaly:** Suppose we want to define a new skill level and its rating *before any player has that level*. In a player-only table, there's no natural place to store that skill-level rule without inventing a player row.

**Deletion anomaly:** If the last player at skill level 8 is deleted, we may also lose the only stored evidence that level 8 corresponds to `Advanced`.

The underlying problem is **one table is storing two different kinds of facts**: player-to-skill-level assignments and skill-level-to-rating rules.

### Fix: Separate the two kinds of facts

The screenshots split the table into two tables.

**`Player`** — primary key: `Player_ID`; `Player_Skill_Level` is a foreign key.

| Player_ID | Player_Skill_Level |
|---|---:|
| jdog21 | 4 |
| gila19 | 4 |
| trev73 | 8 |
| tina42 | 1 |

**`Player_Skill_Levels`** — primary key: `Player_Skill_Level`.

| Player_Skill_Level | Player_Rating |
|---:|---|
| 1 | Beginner |
| 2 | Beginner |
| 3 | Beginner |
| 4 | Intermediate |
| 5 | Intermediate |
| 6 | Intermediate |
| 7 | Advanced |
| 8 | Advanced |
| 9 | Advanced |

Now each table has one clear responsibility:

```text
Player:
Player_ID → Player_Skill_Level

Player_Skill_Levels:
Player_Skill_Level → Player_Rating
```

The rating for skill level 4 is stored **once**, in `Player_Skill_Levels`. Both `jdog21` and `gila19` refer to that same rule, so they can't disagree about level 4's rating when it's retrieved through the relationship.

The previously normalized **`Player_Inventory`** table stays separate; we don't need to put inventory items back into `Player`.

### PostgreSQL example of the corrected design

```sql
CREATE TABLE player_skill_levels (
    player_skill_level INTEGER PRIMARY KEY,
    player_rating TEXT NOT NULL
);

CREATE TABLE player (
    player_id TEXT PRIMARY KEY,
    player_skill_level INTEGER NOT NULL
        REFERENCES player_skill_levels(player_skill_level)
);
```

To display a player's rating, use a `JOIN`:

```sql
SELECT
    p.player_id,
    p.player_skill_level,
    sl.player_rating
FROM player AS p
JOIN player_skill_levels AS sl
    ON p.player_skill_level = sl.player_skill_level;
```

**The `JOIN` doesn't mean the data is missing.** It means each fact is stored in the table that owns it, and related facts can be combined when needed.

## 4. The precise meaning of 3NF

The intuitive “remove transitive dependencies” rule is excellent for spotting the **Player** problem, but it isn't the complete formal definition.

A few terms help:

| Term | Meaning |
|---|---|
| **Superkey** | One or more columns whose values uniquely identify a row; may include extra columns. |
| **Candidate key** | A *minimal* superkey—remove any column and it stops uniquely identifying rows. |
| **Primary key** | The candidate key chosen as the table's main identifier. |
| **Prime attribute** | An attribute that belongs to **at least one** candidate key. |
| **Non-prime attribute** | An attribute that belongs to **no** candidate key. |

**Formal 3NF rule:** For every *nontrivial* functional dependency `X → A`, at least one of these must hold:

1. **`X` is a superkey**, or
2. **`A` is a prime attribute** (part of some candidate key).

“Nontrivial” means `A` isn't already part of `X`.

The **second possibility** is crucial: **3NF allows certain dependencies where the left-hand side is not a superkey, provided the right-hand side is prime.** BCNF removes this exception.

## 5. Boyce–Codd Normal Form (BCNF)

### Simple definition

**For every nontrivial functional dependency `X → Y`, `X` must be a superkey.**

Put plainly:

> If one set of columns determines another column, that set must be capable of uniquely identifying the row.

This is more demanding than 3NF. A table can satisfy 3NF **and still violate BCNF**.

This explains the final screenshot: Decomplexify crosses out **“non-key”** in the familiar phrase. The point is that BCNF scrutinizes determinants of **all** attributes, not only dependencies involving non-key attributes. The formal superkey rule above is the precise version.

### Do the corrected Player tables meet BCNF?

Yes, under the stated game rules:

- In `Player`, `Player_ID → Player_Skill_Level`; `Player_ID` is a key.
- In `Player_Skill_Levels`, `Player_Skill_Level → Player_Rating`; `Player_Skill_Level` is a key.

So the **3NF fix in the screenshots also happens to satisfy BCNF**. That example alone cannot show how the two normal forms differ. We need a table with **more than one candidate key**.

## 6. The difference: A table in 3NF but NOT in BCNF

Consider a university table named **`Student_Course_Instructor`**.

| Student_ID | Course | Instructor |
|---|---|---|
| Ava | Databases | Dr Rao |
| Ben | Databases | Dr Rao |
| Ava | Networks | Dr Lin |
| Cara | Databases | Dr Kim |

Assume these **business rules**:

- Each **instructor teaches exactly one course**. (Different instructors may teach the same course.)
- For any given student and course, **only one instructor is assigned**.

These rules imply:

```text
(Student_ID, Course) → Instructor
Instructor → Course
```

They also imply:

```text
(Student_ID, Instructor) → Course
```

### Step A: Identify the candidate keys

Under these rules, there are **two candidate keys**:

```text
(Student_ID, Course)
(Student_ID, Instructor)
```

Why?

- Knowing the **student + course** identifies the student's instructor.
- Knowing the **student + instructor** identifies the course, because each instructor teaches just one course.
- `Student_ID` alone, `Course` alone, and `Instructor` alone cannot uniquely identify enrollment rows.

**All three attributes are prime:** each appears in at least one candidate key.

### Step B: Does this table satisfy 3NF?

**Yes.** Look at the interesting dependency:

```text
Instructor → Course
```

`Instructor` is **not a superkey**, because Dr Rao appears in multiple student rows. But `Course` **is a prime attribute** because it belongs to the candidate key `(Student_ID, Course)`.

That satisfies the *prime-attribute exception* in the formal 3NF rule. The other stated dependencies have candidate keys on the left-hand side.

### Step C: Does it satisfy BCNF?

**No.** BCNF doesn't have the prime-attribute exception.

```text
Instructor → Course
```

The left-hand side, `Instructor`, is **not a superkey**: it can't identify which student enrollment row we're talking about.

That single dependency violates BCNF, even though the table is in 3NF.

### Why might that matter?

Dr Rao's assignment to `Databases` is repeated for Ava and Ben. If Dr Rao changes to another course, updating only one of those rows creates inconsistent course assignments for the same instructor. This is an **update anomaly** that BCNF tries to eliminate.

### BCNF decomposition

Separate *instructor-to-course assignments* from *student-to-instructor assignments*.

**`Instructor_Course`** — primary key: `Instructor`

| Instructor | Course |
|---|---|
| Dr Rao | Databases |
| Dr Lin | Networks |
| Dr Kim | Databases |

**`Student_Instructor`** — candidate/primary key: `(Student_ID, Instructor)`

| Student_ID | Instructor |
|---|---|
| Ava | Dr Rao |
| Ben | Dr Rao |
| Ava | Dr Lin |
| Cara | Dr Kim |

Now the relevant dependencies are:

```text
Instructor_Course:
Instructor → Course

Student_Instructor:
(Student_ID, Instructor) identifies an assignment row
```

Both tables satisfy BCNF under these assumptions. To see students with their courses, join on `Instructor`.

```sql
SELECT
    si.student_id,
    ic.course,
    si.instructor
FROM student_instructor AS si
JOIN instructor_course AS ic
    ON si.instructor = ic.instructor;
```

**Important practical trade-off:** This split is **lossless** for the assumed dependencies, but it may not preserve every original constraint in a form that can be checked within one table. In particular, enforcing “a student has at most one instructor per course” may require an additional rule, validation, or redesign after decomposition. BCNF is not automatically the simplest operational schema in every case.

## 7. 3NF vs BCNF — Side by side

| Question | 3NF | BCNF |
|---|---|---|
| Must already be in 2NF? | Yes | Yes (BCNF also implies 3NF). |
| What is the main idea? | Avoid problematic dependencies among non-key facts; formal rule allows a prime-attribute exception. | Every nontrivial dependency must have a **superkey determinant**. |
| Can `X → A` be allowed when `X` is **not** a superkey? | **Yes**, if `A` is a prime attribute. | **No**. |
| Is it stricter? | Less strict | More strict |
| Player example after splitting `Player` from `Player_Skill_Levels` | Satisfies 3NF | Also satisfies BCNF |
| Student/Course/Instructor example above | Satisfies 3NF | Violates BCNF because `Instructor → Course` |
| Design trade-off | Often easier to preserve all constraints within the tables | Stronger redundancy control, but decomposition can make some constraints harder to enforce |

### The simplest way to distinguish them

```text
3NF:
For X → A, either X is a superkey OR A is prime.

BCNF:
For X → A, X MUST be a superkey.
```

**That “OR A is prime” exception is the difference.**

## 8. Connect the two Decomplexify examples

The player example teaches **why we split a table**:

```text
BEFORE:
Player_ID → Skill_Level → Rating

AFTER:
Player(Player_ID, Skill_Level)
Player_Skill_Levels(Skill_Level, Rating)
```

That removes a dependency through a non-key attribute and fixes the rating inconsistency shown in the screenshots.

The university example teaches **why BCNF is stricter than 3NF**:

```text
Student/Course/Instructor has two candidate keys.
Instructor → Course is allowed by 3NF (Course is prime),
but rejected by BCNF (Instructor is not a superkey).
```

The first illustrates a **transitive-dependency problem**; the second illustrates the **exact formal distinction** between 3NF and BCNF.

---

*These notes use Decomplexify's player and skill-level scenario as the starting point, with an additional university example to clarify the 3NF–BCNF distinction. All sample data is instructional.*
