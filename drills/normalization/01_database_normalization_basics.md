# Database Normalization — Basics

*Study notes based on Decomplexify's database normalization lesson.*

## What is database normalization?

**Database normalization** is a way of organizing data in relational tables so that information is stored consistently, relationships are clear, and unnecessary duplication is reduced.

The goal is **not** to create as many tables as possible. The goal is to design tables that are easy to understand, maintain, and update correctly.

### Why normalize a database?

Well-organized tables are generally:

- **Easier to understand:** Each table has a clear purpose.
- **Easier to extend:** New data can often be added without changing the table structure.
- **Easier to maintain:** Related data is stored consistently.
- **Less prone to errors:** The same fact does not need to be edited in many places.

Normalization also helps protect against three common data problems called **anomalies**.

## Data anomalies

An *anomaly* is a problem caused by how data is arranged in a table. It can make inserting, updating, or deleting information unreliable.

### 1. Insertion anomaly

**Meaning:** You cannot add one fact without also supplying unrelated information, or without changing the schema.

**Example:** A table stores both customer details and purchase details in each row. A new customer cannot be recorded until they make their first purchase, because the table also requires a `purchase_id`.

**Why it matters:** The database cannot represent a valid customer who has not purchased anything yet.

**Better design:** Store customers in their own table and purchases in another table, linked by `customer_id`.

### 2. Update anomaly

**Meaning:** One fact is repeated in multiple rows, so updating some copies but not others leaves contradictory data.

Suppose this table stores the customer's address with every order:

| order_id | customer_id | address |
|---|---|---|
| 101 | 7 | 10 Lake Road |
| 102 | 7 | 10 Lake Road |
| 103 | 7 | 10 Lake Road |

If the customer moves, the address must be updated in all three rows. Updating only one row creates conflicting addresses for the same customer.

**Better design:** Store the customer's current address once in a `customer` table. Keep orders linked by `customer_id` (and store a separate historical shipping address with each order if the business needs one).

### 3. Deletion anomaly

**Meaning:** Deleting one fact accidentally deletes some other information you still need.

**Example:** If a table stores both player details and inventory items, and the last inventory row for a player is deleted, their player information might disappear too.

**Better design:** Keep the `player` record separately from its inventory records. Removing the last inventory item should not remove the player.

## Normal forms

Normalization is usually taught through progressively stricter design standards called **normal forms**.

Common ones are **First Normal Form (1NF), Second Normal Form (2NF), Third Normal Form (3NF), Boyce–Codd Normal Form (BCNF), Fourth Normal Form (4NF), and Fifth Normal Form (5NF)**.

Each addresses particular data-organization problems. Being in a normal form does not automatically guarantee a perfect database design, nor does 1NF alone eliminate every anomaly.

We'll study the normal forms individually. The next note covers **First Normal Form (1NF)** in detail.
