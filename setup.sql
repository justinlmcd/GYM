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

commit;
