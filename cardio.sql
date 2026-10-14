-- GYM cardio. Run once in your Supabase SQL editor (same project as setup.sql).
begin;

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
commit;
