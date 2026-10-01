-- data/employee-laptop.sql: practice data for notes 10-12
-- One-to-one: each employee has at most one laptop, and each laptop belongs
-- to at most one employee. Loaded with \ir by the notes files; safe to re-run.

-- employee points at laptop, so employee has to be dropped first.
-- 10-foreign-keys.sql shows the error you get the other way round.
DROP TABLE IF EXISTS employee;
DROP TABLE IF EXISTS laptop;

-- GENERATED ALWAYS AS IDENTITY is the modern replacement for BIGSERIAL (13)
CREATE TABLE laptop (
    id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    brand TEXT NOT NULL,
    model TEXT NOT NULL
);

CREATE TABLE employee (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name TEXT NOT NULL,
    last_name  TEXT NOT NULL,
    laptop_id  BIGINT REFERENCES laptop (id),
    UNIQUE (laptop_id)
);

-- The tables are brand new, so ids are handed out 1, 2, 3, ... in insert order
INSERT INTO laptop (brand, model)
VALUES ('Apple',     'MacBook Air 13'),        -- id 1
       ('Lenovo',    'ThinkPad X1 Carbon'),    -- id 2
       ('Dell',      'XPS 13'),                -- id 3
       ('Framework', 'Laptop 13');             -- id 4: not given to anyone

INSERT INTO employee (first_name, last_name, laptop_id)
VALUES ('Asha',  'Rao',      2),               -- id 1
       ('Ben',   'Carter',   1),               -- id 2
       ('Chloe', 'Martin',   NULL),            -- id 3: no laptop
       ('Dev',   'Malhotra', 3),               -- id 4
       ('Elena', 'Rossi',    NULL);            -- id 5: no laptop
