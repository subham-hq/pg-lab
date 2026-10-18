# Fourth Normal Form (4NF)

**Source:** Decomplexify — *Learn Database Normalization (1NF, 2NF, 3NF, 4NF, 5NF)*  
**Example:** `Model_Colours_And_Styles_Available` (birdhouse models) from the lesson screenshots

## 1. What is Fourth Normal Form?

**Fourth Normal Form (4NF)** addresses a problem that can remain even after a table satisfies **BCNF**: the same row can combine **two independent sets of facts** about one thing.

In the video, a birdhouse model has:

- Several **available colours**.
- Several **available styles**.

The available colours and available styles are **independent choices**: choosing a colour does not restrict which style can be chosen, and choosing a style does not restrict which colour can be chosen.

If we put `Model`, `Color`, and `Style` together in one table, we end up storing **every colour–style combination**. This repeats facts unnecessarily.

**Plain-English goal of 4NF:** When one entity has *multiple independent lists of values*, store those lists separately rather than combining every possible pair in one table.

> **Accurate definition:** A relation is in **4NF** if, for every **nontrivial multivalued dependency** `X ↠ Y` that holds in it, `X` is a **superkey**.
>
> Don't worry if this sounds abstract. The birdhouse example below makes each part understandable.

---

## 2. The example from the screenshots

The website in the lesson, `DesignMyBirdhouse.com`, offers the following models:

| Model | Available colours | Available styles |
|---|---|---|
| Tweety | Yellow, Blue | Bungalow, Duplex |
| Metro | Brown, Grey | High-Rise, Modular |
| Prairie | Brown, Beige, Green | Bungalow, Schoolhouse |

For **Tweety**, any available colour can be paired with any available style:

| Model | Color | Style |
|---|---|---|
| Tweety | Yellow | Bungalow |
| Tweety | Yellow | Duplex |
| Tweety | Blue | Bungalow |
| Tweety | Blue | Duplex |

**Why four rows?** Tweety has two colours and two styles, so there are `2 × 2 = 4` combinations.

For **Metro**, there are also `2 × 2 = 4` combinations. **Prairie** has three colours and two styles, so there should be `3 × 2 = 6` combinations **if colours and styles are truly independent**.

The original design is:

### `Model_Colours_And_Styles_Available` — problematic design

| Model | Color | Style |
|---|---|---|
| Tweety | Yellow | Bungalow |
| Tweety | Yellow | Duplex |
| Tweety | Blue | Bungalow |
| Tweety | Blue | Duplex |
| Metro | Brown | High-Rise |
| Metro | Brown | Modular |
| Metro | Grey | High-Rise |
| Metro | Grey | Modular |
| Prairie | Brown | Bungalow |
| Prairie | Brown | Schoolhouse |
| Prairie | Beige | Bungalow |
| Prairie | Beige | Schoolhouse |
| Prairie | Green | Bungalow |

**Detail worth noticing in the screenshot:** It shows the new combination `Prairie | Green | Bungalow`, but not `Prairie | Green | Schoolhouse`. The slide appears to be illustrating a colour being newly added. **If** Prairie's colour choices and style choices are independent, the `Green + Schoolhouse` row would also have to be inserted. The missing row is exactly the kind of maintenance problem this design creates. If, instead, green is *actually allowed only with Bungalow*, the choices are **not independent**, and this decomposition would not be appropriate without additional constraints.

---

## 3. Why can this table still be a problem after 1NF, 2NF, 3NF, and BCNF?

This design is not necessarily violating the earlier normal forms:

- **1NF:** Each cell holds one model, one colour, or one style. No comma-separated lists are stored inside a cell.
- **2NF:** There is no non-key attribute in this three-column example that depends on only part of a candidate key.
- **3NF:** There is no transitive dependency through a non-key attribute causing the problem.
- **BCNF:** Under the stated assumptions, there are no problematic nontrivial **functional dependencies**: `Model` does **not** determine one single `Color` or one single `Style`.

For the original three-column design, a candidate key is:

`(Model, Color, Style)`

No two rows should represent the exact same model–colour–style combination. But **all three columns together** are needed to identify a combination.

**The key insight:** Earlier normal forms mainly address problems involving **functional dependencies**. 4NF also handles a different kind of dependency: **multivalued dependencies**.

---

## 4. Functional dependency vs multivalued dependency

### Functional dependency (FD): `→`

A functional dependency means one value determines **one specific value** of another attribute.

For example, in a different table where each model has one fixed price:

```text
Model → Price
```

Knowing the model determines its price.

### Multivalued dependency (MVD): `↠`

A multivalued dependency means one value determines a **set of values**, and that set can vary independently of other attributes in the relation.

In the birdhouse example:

```text
Model ↠ Color
Model ↠ Style
```

Read these as:

- For a particular model, there is a set of available colours.
- For the same model, there is a set of available styles.
- **Those two sets are independent of each other.**

For Tweety:

```text
Colours = {Yellow, Blue}
Styles  = {Bungalow, Duplex}
```

One chosen colour does not determine which style is allowed; **both styles are available with both colours**.

This does **not** mean:

```text
Model → Color   -- not true: Tweety has more than one colour
Model → Style   -- not true: Tweety has more than one style
```

**Important:** `Model ↠ Color` is not just a fancy way of saying “one model has many colours.” The defining feature here is the **independence** of the colours from the styles stored alongside them.

### How independence works, more precisely

Suppose these rows exist:

| Model | Color | Style |
|---|---|---|
| Tweety | Yellow | Bungalow |
| Tweety | Blue | Duplex |

If colour and style are independent for Tweety, the other combinations must also be valid:

| Model | Color | Style |
|---|---|---|
| Tweety | Yellow | Duplex |
| Tweety | Blue | Bungalow |

This ability to **exchange colours and styles for the same model** without changing which combinations are valid is the idea behind the multivalued dependencies in this example.

---

## 5. Why the original design creates anomalies

### Insertion anomaly: adding a new colour

Suppose Prairie introduces **Green**, and Prairie already supports two styles:

```text
Bungalow
Schoolhouse
```

To represent that green works with **both styles**, the combined table needs **two new rows**:

| Model | Color | Style |
|---|---|---|
| Prairie | Green | Bungalow |
| Prairie | Green | Schoolhouse |

If you add only one row (as shown at that moment in the screenshot), you have not completely recorded the independent availability of green.

**Problem:** Adding one new colour forces you to think about every style, even though the colour is an independent fact.

### Update anomaly: changing a colour name

Suppose `Yellow` is renamed `Golden Yellow` for Tweety.

In the combined table, `Yellow` appears with **both Bungalow and Duplex**. Both rows need updating. If only one is updated, the table can incorrectly appear to offer both `Yellow` and `Golden Yellow` as different colour choices.

**Problem:** One underlying fact is stored multiple times.

### Deletion anomaly: accidentally losing an availability fact

Suppose a developer deletes the **only remaining row** for Prairie in the colour Green, trying to remove an individual combination.

If that was the only row recording Green, the database now also loses the independent fact **“Prairie is available in Green.”**

**Problem:** Deleting one combination can erase a separate fact about available colours or styles.

---

## 6. Convert the example into 4NF

Instead of storing colour and style together, create **two tables**.

### Table A: `Model_Colors_Available`

| Model | Color |
|---|---|
| Tweety | Yellow |
| Tweety | Blue |
| Metro | Brown |
| Metro | Grey |
| Prairie | Brown |
| Prairie | Beige |
| Prairie | Green |

**Primary key:** `(Model, Color)`

Each row records **one available colour for one model**.

### Table B: `Model_Styles_Available`

| Model | Style |
|---|---|
| Tweety | Bungalow |
| Tweety | Duplex |
| Metro | High-Rise |
| Metro | Modular |
| Prairie | Bungalow |
| Prairie | Schoolhouse |

**Primary key:** `(Model, Style)`

Each row records **one available style for one model**.

### Why this solves the problem

To add Green to Prairie, insert **one row** in `Model_Colors_Available`:

```text
Prairie | Green
```

You don't have to add a row for each Prairie style. The style options already exist in the other table.

Likewise, to add a new style for Prairie, insert **one row** in `Model_Styles_Available`. You don't have to repeat every colour.

**We now store two independent facts independently.**

---

## 7. Can we still retrieve every valid colour–style combination?

Yes. The decomposition does not mean we lose the ability to display combinations.

Join the two tables on `Model`:

```sql
SELECT
    colors.model,
    colors.color,
    styles.style
FROM model_colors_available AS colors
JOIN model_styles_available AS styles
    ON colors.model = styles.model
ORDER BY colors.model, colors.color, styles.style;
```

For Tweety, the join produces:

| Model | Color | Style |
|---|---|---|
| Tweety | Blue | Bungalow |
| Tweety | Blue | Duplex |
| Tweety | Yellow | Bungalow |
| Tweety | Yellow | Duplex |

This is intentional: **each available colour pairs with each available style** for that model.

The tables store only the independent facts, and the query derives the combinations **when needed**.

This is called a **lossless decomposition** under the stated independence rule: joining the two tables recreates exactly the valid combinations. If certain combinations are restricted, then this join would invent invalid combinations, and a different data model is required.

---

## 8. Practical PostgreSQL design

The following SQL implements the two tables from the screenshots:

```sql
CREATE TABLE model_colors_available (
    model TEXT NOT NULL,
    color TEXT NOT NULL,
    PRIMARY KEY (model, color)
);

CREATE TABLE model_styles_available (
    model TEXT NOT NULL,
    style TEXT NOT NULL,
    PRIMARY KEY (model, style)
);
```

Notice the composite primary keys:

- `(model, color)` prevents recording the same colour twice for the same model.
- `(model, style)` prevents recording the same style twice for the same model.

The same colour can appear for **different** models, and the same style can appear for **different** models. That is expected.

In a fuller application, you might also have a separate `models` table and foreign keys from both availability tables to `models(model_id)`.

### Adding an independently available colour

```sql
INSERT INTO model_colors_available (model, color)
VALUES ('Prairie', 'Green');
```

That is all you need to record the new colour. If Green is already listed for Prairie, the composite primary key prevents inserting the same fact twice.

---

## 9. How 4NF differs from BCNF

This is the easiest way to remember the distinction:

| BCNF | 4NF |
|---|---|
| Primarily addresses **functional dependencies** (`X → Y`). | Also addresses **multivalued dependencies** (`X ↠ Y`). |
| For every nontrivial FD, the determinant `X` must be a superkey. | For every nontrivial MVD, the determinant `X` must be a superkey. |
| A table may still repeat combinations of **independent multi-valued facts**. | Separates those independent facts to remove needless combinations. |

**Every 4NF relation is also in BCNF.** The reverse is not necessarily true.

In the original birdhouse table:

```text
Candidate key: (Model, Color, Style)

Model ↠ Color
Model ↠ Style
```

`Model` is **not** a superkey of the three-column table: there are multiple rows per model.

Those are **nontrivial** MVDs because neither `Color` nor `Style` is part of `Model`, and neither dependency covers every column by itself.

Therefore, the three-column table **violates 4NF** under the independence assumption, even though it can satisfy BCNF.

After splitting:

```text
Model_Colors_Available(Model, Color)
Model_Styles_Available(Model, Style)
```

The unwanted independent multivalued facts no longer coexist in one table. Each relation represents just one kind of availability fact.

### A nuance about the video's wording

The slide says, roughly, that multivalued dependencies should be “on the key.” The precise rule is **on a superkey**, and it applies to **nontrivial** multivalued dependencies. This distinction matters when you study database normalization more formally.

---

## 10. A second example: employees, skills, and spoken languages

Imagine a developer has:

```text
Skills:    Python, PostgreSQL
Languages: English, Bengali
```

If skills and spoken languages are independent facts, a combined table creates four rows:

| Employee | Skill | Language |
|---|---|---|
| E01 | Python | English |
| E01 | Python | Bengali |
| E01 | PostgreSQL | English |
| E01 | PostgreSQL | Bengali |

Here:

```text
Employee ↠ Skill
Employee ↠ Language
```

If the employee adds **Docker** as a skill, we'd need another pair of language-combination rows. But a skill and a spoken language have no reason to be stored together.

A 4NF-friendly design uses:

**`Employee_Skills`**

| Employee | Skill |
|---|---|
| E01 | Python |
| E01 | PostgreSQL |
| E01 | Docker |

**`Employee_Languages`**

| Employee | Language |
|---|---|
| E01 | English |
| E01 | Bengali |

Now adding a skill requires **one insert**, not one for every spoken language.

---

## 11. An important boundary: when should you *not* split the table this way?

Suppose the business rules actually say:

- Prairie is available in **Green only with Bungalow**.
- Green **cannot** be combined with Schoolhouse.

In this case, colour and style are **not independent**.

If we split into two availability lists and join them, the database would incorrectly generate:

```text
Prairie | Green | Schoolhouse  -- not actually allowed
```

So before applying the 4NF decomposition, confirm the business rule:

**Are colours and styles independent options, or are certain specific colour–style combinations allowed?**

- **Independent:** Two tables (`Model_Colors_Available` and `Model_Styles_Available`) are appropriate.
- **Restricted combinations:** Keep a table of valid model–colour–style combinations, or use an additional constraint/relationship that correctly captures the restrictions.

**Normalization depends on real business rules, not just column names or how sample data happens to look.**

---

## 12. Final mental model

Think of the progression this way:

**3NF / BCNF ask:**

> Does one attribute incorrectly determine another attribute inside this table?

**4NF asks:**

> Are two independent lists of values being combined into every possible pair for the same entity?

In the birdhouse example, the facts are:

```text
Tweety has colours {Yellow, Blue}.
Tweety has styles  {Bungalow, Duplex}.
```

These are **two separate facts**. 4NF tells us to **store them separately** rather than storing four rows that repeat both facts in different combinations.

**One-sentence definition:** **4NF prevents redundant combinations of independent multivalued facts by requiring every nontrivial multivalued dependency to have a superkey as its determinant.**
