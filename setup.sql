-- GYM. Run once in your Supabase project (SQL Editor). Safe to share a project with other apps.
begin;

-- The movements you train, each with its own progression rule.
create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  name text not null,
  muscle text not null default 'Other',
  unit text not null default 'lbs' check (unit in ('lbs','kg')),
  target_sets int not null default 3 check (target_sets between 1 and 20),
  target_reps int not null default 8 check (target_reps between 1 and 100),
  increment numeric not null default 5 check (increment >= 0),
  archived boolean not null default false,
  created_at timestamptz not null default now()
);

-- One row per set you actually did.
create table public.sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  exercise_id uuid not null references public.exercises(id) on delete cascade,
  performed_on date not null,
  set_no int not null default 1 check (set_no between 1 and 50),
  weight numeric not null default 0 check (weight >= 0),
  reps int not null check (reps between 0 and 1000),
  note text not null default '',
  created_at timestamptz not null default now()
);

create index sets_by_exercise on public.sets (user_id, exercise_id, performed_on desc);
create index sets_by_day on public.sets (user_id, performed_on desc);
create index exercises_by_user on public.exercises (user_id, archived);

alter table public.exercises enable row level security;
alter table public.sets enable row level security;

create policy ex_read   on public.exercises for select using (user_id = auth.uid());
create policy ex_write  on public.exercises for insert with check (user_id = auth.uid());
create policy ex_edit   on public.exercises for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy ex_remove on public.exercises for delete using (user_id = auth.uid());

create policy set_read   on public.sets for select using (user_id = auth.uid());
create policy set_write  on public.sets for insert with check (user_id = auth.uid());
create policy set_edit   on public.sets for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy set_remove on public.sets for delete using (user_id = auth.uid());

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.exercises to authenticated;
grant select, insert, update, delete on public.sets to authenticated;

-- Cardio sessions.

create table if not exists public.cardio (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  performed_on date not null,
  kind text not null default 'treadmill',
  minutes numeric not null check (minutes > 0 and minutes <= 1440),
  speed numeric check (speed >= 0),
  speed_unit text not null default 'mph',
  calories numeric check (calories >= 0),
  note text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists cardio_by_day on public.cardio (user_id, performed_on desc);
alter table public.cardio enable row level security;

drop policy if exists c_read on public.cardio;
drop policy if exists c_write on public.cardio;
drop policy if exists c_edit on public.cardio;
drop policy if exists c_remove on public.cardio;
create policy c_read   on public.cardio for select using (user_id = auth.uid());
create policy c_write  on public.cardio for insert with check (user_id = auth.uid());
create policy c_edit   on public.cardio for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy c_remove on public.cardio for delete using (user_id = auth.uid());

grant select, insert, update, delete on public.cardio to authenticated;

-- Workouts: a named list of exercises, in order, like "Chest day 1".
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
