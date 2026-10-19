create table users (
  id          serial primary key,
  handle      text not null unique,
  created_at  timestamptz not null default now()
);

create table issues (
  id          serial primary key,
  user_id     int not null references users(id),   -- creator
  status      text not null CHECK (status IN ('open', 'closed')), -- open, closed
  priority    int  not null CHECK (priority BETWEEN 1 AND 5), -- 1..5
  title       text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table comments (
  id          serial primary key,
  issue_id    int not null references issues(id),
  user_id     int references users(id),            -- commenter
  body        text not null,
  archived    boolean not null default false,
  created_at  timestamptz not null default now()
);
