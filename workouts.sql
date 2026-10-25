-- GYM workouts. Run once in your Supabase SQL editor (same project as setup.sql). Safe to run again.
begin;

-- A named workout, like "Chest day 1": the exercises you do, in order.
create table if not exists public.workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  name text not null check (char_length(name) between 1 and 60),
  exercise_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists workouts_by_user on public.workouts (user_id, name);
alter table public.workouts enable row level security;

drop policy if exists w_read on public.workouts;
drop policy if exists w_write on public.workouts;
drop policy if exists w_edit on public.workouts;
drop policy if exists w_remove on public.workouts;
create policy w_read   on public.workouts for select using (user_id = auth.uid());
create policy w_write  on public.workouts for insert with check (user_id = auth.uid());
create policy w_edit   on public.workouts for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy w_remove on public.workouts for delete using (user_id = auth.uid());

grant select, insert, update, delete on public.workouts to authenticated;
commit;
