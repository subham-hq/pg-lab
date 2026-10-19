-- 1) See all comments by user
select *
from comments
where user_id = 1;


-- 2) Count all comments by user
select count(*)
from comments
where user_id = 1;

-- 3) See all comments for an issue by ID
select *
from comments
where issue_id = 1;

-- 4) Count comments for an issue by ID from a user by ID

select count(*)
from comments
where issue_id = 1
  and user_id = 2;

-- 5) See all comments for an issue by ID from a user by ID, sorted by date, in the last month

select *
from comments
where issue_id = 1
  and user_id  = 2
  and created_at >= now() - interval '1 month'
order by created_at desc;


-- indexes
create index ix_comments_user_id
on comments (user_id);

create index ix_comments_issue_id
on comments (issue_id);

create index ix_comments_issue_id_user_id_created_at
on comments (issue_id, user_id, created_at desc);
