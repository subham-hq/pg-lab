# Fifth Normal Form (5NF)

*Database normalization notes — based on Decomplexify's ice-cream example*

## 1. What is Fifth Normal Form?

**Fifth Normal Form (5NF)**, also called **Project–Join Normal Form (PJNF)**, deals with tables that contain relationships among **three or more things**, where the relationship can sometimes be represented more accurately using smaller tables.

The goal is to avoid storing combinations that can already be determined from other, simpler relationships—**provided we can reconstruct the original information without losing rows or inventing incorrect ones**.

**In plain English:** If a big relationship can be split into smaller relationships and reliably put back together with `JOIN`, storing all the repeated combinations in one table may be unnecessary.

5NF builds on the earlier normal forms; a table in 5NF must already satisfy 4NF.

> **Precise definition:** A relation is in 5NF if every **nontrivial join dependency** that holds in the relation is implied by its **candidate keys**. The easier explanation above is a way to understand why such decompositions matter; it is not a rule to split every table with three columns.

---

## 2. The Decomplexify example: People, brands, and ice-cream flavours

The video introduces three kinds of facts:

1. **Which ice-cream brands a person likes.**
2. **Which flavours a person likes.**
3. **Which flavours each brand offers.**

A person can enjoy a brand without liking every possible flavour. Likewise, a brand can offer a flavour that a particular person does not like.

The original screenshot uses a table named `Preferred_Ice_Cream_Products_By_Person`:

| Person | Brand | Flavour |
|---|---|---|
| Jason | Frosty's | Vanilla |
| Jason | Frosty's | Chocolate |
| Jason | Alpine | Vanilla |
| Suzy | Alpine | Rum Raisin |
| Suzy | Ice Queen | Mint Chocolate Chip |
| Suzy | Ice Queen | Strawberry |
| Suzy | Frosty's | Strawberry |

**What does one row mean?**

`(Jason, Frosty's, Vanilla)` means that Jason likes **Vanilla made by Frosty's**. It is a fact involving **three values together**: person, brand, and flavour.

For this original three-column table, the natural candidate key is typically:

`(Person, Brand, Flavour)`

Each unique combination identifies one recorded preference.

### Why might this design be unnecessarily repetitive?

The brand names, flavour names, and people are repeated across many rows. If the business rule says that a person will enjoy **any flavour they like** from **any brand they like**, as long as that brand offers the flavour, then we do not need to store every matching three-way combination separately.

We can store the underlying pairwise facts instead.

**That business rule is essential.** Without it, the decomposition described next might not preserve the meaning of the original data.

---

## 3. Breaking the relationship into three smaller tables

### Table A — `Preferred_Brands_By_Person`

Records which brands each person likes.

| Person | Brand |
|---|---|
| Jason | Frosty's |
| Jason | Alpine |
| Suzy | Alpine |
| Suzy | Ice Queen |
| Suzy | Frosty's |

**Primary key:** `(Person, Brand)`.

This table answers: *Does this person like this brand?*

### Table B — `Preferred_Flavors_By_Person`

Records which flavours each person likes, regardless of brand.

| Person | Flavour |
|---|---|
| Jason | Vanilla |
| Jason | Chocolate |
| Suzy | Rum Raisin |
| Suzy | Mint Chocolate Chip |
| Suzy | Strawberry |

**Primary key:** `(Person, Flavour)`.

This table answers: *Does this person like this flavour?*

### Table C — `Available_Flavors_By_Brand`

Records which flavours each brand sells.

| Brand | Flavour |
|---|---|
| Frosty's | Vanilla |
| Frosty's | Chocolate |
| Frosty's | Strawberry |
| Frosty's | Mint Chocolate Chip |
| Alpine | Vanilla |
| Alpine | Rum Raisin |
| Ice Queen | Vanilla |
| Ice Queen | Strawberry |
| Ice Queen | Mint Chocolate Chip |

**Primary key:** `(Brand, Flavour)`.

This table answers: *Does this brand actually offer this flavour?*

The three tables store **three independent kinds of facts** rather than all their combinations.

---

## 4. How do the three tables reconstruct the original information?

For a `(Person, Brand, Flavour)` combination to be valid under the video's intended rule, **all three conditions must hold**:

1. The person likes the brand.
2. The person likes the flavour.
3. The brand sells the flavour.

Think of it as:

```text
Person likes Brand
        AND
Person likes Flavour
        AND
Brand offers Flavour
        ↓
Person can choose that Brand + Flavour
```

### Example: Jason

Jason likes **Frosty's** and **Alpine**, and likes **Vanilla** and **Chocolate**.

- **Frosty's + Vanilla** → valid: Jason likes both, and Frosty's offers Vanilla.
- **Frosty's + Chocolate** → valid: Jason likes both, and Frosty's offers Chocolate.
- **Alpine + Vanilla** → valid: Jason likes both, and Alpine offers Vanilla.
- **Alpine + Chocolate** → **invalid**: Alpine does not offer Chocolate.

Notice that we reconstructed Jason's three combinations **without storing them directly**.

### Example: Suzy

Suzy likes **Alpine**, **Ice Queen**, and **Frosty's**. Her favourite flavours are **Rum Raisin**, **Mint Chocolate Chip**, and **Strawberry**.

Under the same rule, valid combinations are:

| Person | Brand | Flavour |
|---|---|---|
| Suzy | Alpine | Rum Raisin |
| Suzy | Ice Queen | Mint Chocolate Chip |
| Suzy | Ice Queen | Strawberry |
| Suzy | Frosty's | Mint Chocolate Chip |
| Suzy | Frosty's | Strawberry |

**Pay attention to `Suzy + Frosty's + Mint Chocolate Chip`.** This additional combination follows from the three pairwise facts, but is **not** shown in the video's original three-column example. That difference matters; see Section 7.

---

## 5. What is a join dependency?

A **join dependency (JD)** means a relation can be reconstructed exactly by joining projections (smaller sets of its columns).

For the three-column relation:

`R(Person, Brand, Flavour)`

we are considering these projections:

- `PB(Person, Brand)`
- `PF(Person, Flavour)`
- `BF(Brand, Flavour)`

The proposed relationship is:

```text
R = PB JOIN PF JOIN BF
```

This must be a **lossless reconstruction**: the join must return **exactly** the intended three-way rows, **not fewer and not more**.

When this join dependency follows from actual business rules, it can justify decomposing the three-way table into the smaller tables.

### Why are three tables necessary?

Using only two of the relationships can give incorrect combinations:

- **Person + brand** and **person + flavour** don't prove the brand sells the flavour.
- **Person + brand** and **brand + flavour** don't prove the person likes the flavour.
- **Person + flavour** and **brand + flavour** don't prove the person likes the brand.

The third table supplies the missing condition.

---

## 6. PostgreSQL example

The following schema implements the three pairwise relationships.

```sql
CREATE TABLE preferred_brands_by_person (
    person TEXT NOT NULL,
    brand TEXT NOT NULL,
    PRIMARY KEY (person, brand)
);

CREATE TABLE preferred_flavors_by_person (
    person TEXT NOT NULL,
    flavor TEXT NOT NULL,
    PRIMARY KEY (person, flavor)
);

CREATE TABLE available_flavors_by_brand (
    brand TEXT NOT NULL,
    flavor TEXT NOT NULL,
    PRIMARY KEY (brand, flavor)
);
```

Each table has a **composite primary key** because neither column alone is enough to uniquely identify a relationship.

### Reconstruct matching person–brand–flavour combinations

```sql
SELECT
    pb.person,
    pb.brand,
    pf.flavor
FROM preferred_brands_by_person AS pb
JOIN preferred_flavors_by_person AS pf
    ON pb.person = pf.person
JOIN available_flavors_by_brand AS bf
    ON pb.brand = bf.brand
   AND pf.flavor = bf.flavor
ORDER BY pb.person, pb.brand, pf.flavor;
```

**How the joins work:**

- First `JOIN`: combine each person's preferred brands with their preferred flavours.
- Second `JOIN`: keep only brand–flavour pairs that actually exist in the brand's offerings.

This query returns the supported combinations **under the assumption that those three pairwise facts are sufficient to determine a preference**.

> This is a useful distinction: `JOIN` tells PostgreSQL **how** to combine rows. The business rules determine **whether those resulting combinations are actually true**.

---

## 7. Important correction to the screenshots

The video's illustrations are helpful, but their displayed data is **not perfectly consistent** across screenshots.

- The initial brand list says **Frosty's offers Chocolate**, and the original table includes **Jason + Frosty's + Chocolate**. However, the later `Available_Flavors_By_Brand` table shown in the video omits **Frosty's + Chocolate**.
- The original table adds **Suzy + Frosty's + Strawberry**, and Suzy's speech bubble adds **Frosty's** to her preferred brands. However, the later `Preferred_Brands_By_Person` table omits **Suzy + Frosty's**.
- If those two missing pairs are added to the decomposed tables, the join additionally produces **Suzy + Frosty's + Mint Chocolate Chip** (because Suzy likes the brand and flavour, and Frosty's offers the flavour). This row is not in the original table.

So the exact tables shown in those screenshots **do not reconstruct the original seven rows exactly**. The three-table design is sound **only if the intended rule really is that any liked flavour from any liked brand is an acceptable combination**. Under that rule, Suzy's additional Mint Chocolate Chip combination belongs in the result, giving **eight** total combinations in the consistent worked example.

If Suzy specifically dislikes **Frosty's Mint Chocolate Chip**, despite liking that flavour from other brands, then the original three-way preference contains essential information. In that case, **you cannot safely replace it with only the three pairwise tables**: doing so would invent a preference.

**Lesson:** Never decide a table violates 5NF merely because you can make smaller tables. You must prove the decomposition is valid for the real business rules and reconstructs exactly the intended rows.

---

## 8. What problems can this normalization prevent?

When a three-way table is merely repeating combinations that are implied by simpler facts, it can cause maintenance problems.

**Insertion problem:** A new flavour offered by a brand may require inserting several person–brand–flavour rows, even though only one brand–flavour fact changed.

**Update problem:** Changing which flavours a brand offers can require many changes in the combined table. Missing one creates inconsistent records.

**Deletion problem:** Removing someone's last matching three-way preference could accidentally remove the only stored evidence that a brand offers a particular flavour.

The decomposed design stores each fact in its appropriate table:

- Brand preference → `preferred_brands_by_person`
- Flavour preference → `preferred_flavors_by_person`
- Product availability → `available_flavors_by_brand`

This makes each kind of information easier to maintain independently.

---

## 9. 4NF vs 5NF — what changed?

| Fourth Normal Form (4NF) | Fifth Normal Form (5NF) |
|---|---|
| Focuses on **independent multivalued facts** about one key. | Focuses on **join dependencies** involving combinations of related facts. |
| Example: A birdhouse model has independent available colours and styles. | Example: A person likes brands and flavours, while brands offer particular flavours. |
| Typical decomposition: `(Model, Colour, Style)` → `(Model, Colour)` and `(Model, Style)`. | Possible decomposition: `(Person, Brand, Flavour)` → `(Person, Brand)`, `(Person, Flavour)`, and `(Brand, Flavour)`. |
| Guards against duplication from independent multivalued relationships. | Guards against duplication from valid, more complex decompositions that can be joined back together. |

**The simple distinction:**

- **4NF:** “Two independent lists are being multiplied together.”
- **5NF:** “This three-way relationship may be derivable from several smaller relationships—*but only if their join reconstructs the facts exactly*.”

The formal difference is that 5NF covers certain nontrivial join dependencies that are not handled by 4NF's multivalued-dependency rule.

---

## 10. When should you actually use 5NF?

5NF is useful when the domain has complex relationships among several entities and you can express them as **smaller, independently maintained facts**.

Potential areas include product compatibility, supplier–part–project permissions, publishing rights, and recommendation or preference systems.

It is **not** a reason to split every table into as many tables as possible. If a three-way fact is genuinely specific to the entire combination, it may need to stay together.

For backend development, the most important practical skill is to identify the actual business rule first, then decide which relationships can safely be represented independently.

### Core idea to remember

> **5NF is about lossless decomposition driven by real join dependencies—not simply about making tables smaller.**

A decomposition is helpful only when the smaller tables can be joined to recover **all and only** the valid original facts.
