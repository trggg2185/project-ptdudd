create extension if not exists pgcrypto;

create or replace function public.current_owner_uid()
returns text
language sql
stable
set search_path = ''
as $$
  select auth.jwt()->>'sub';
$$;

revoke all on function public.current_owner_uid() from public;
grant execute on function public.current_owner_uid() to authenticated;

create table if not exists public.profiles (
  owner_uid text primary key,
  display_name text,
  age_group text,
  timezone text not null default 'Asia/Ho_Chi_Minh',
  occupation text,
  living_conditions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1
);

create table if not exists public.availability_blocks (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  title text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  travel_minutes integer not null default 0 check (travel_minutes >= 0),
  recurrence_rule text,
  exception_dates date[] not null default '{}'::date[],
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  check (end_at > start_at)
);

create table if not exists public.goals (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  type text not null,
  target_value numeric,
  unit text,
  status text not null default 'active'
    check (status in ('active', 'paused', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1
);

create table if not exists public.habits (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  name text not null,
  description text,
  recurrence_rule text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  unique (owner_uid, id)
);

create table if not exists public.habit_logs (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  habit_id uuid not null,
  local_date date not null,
  result text not null check (result in ('completed', 'skipped')),
  skipped_reason text,
  logged_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  unique (owner_uid, habit_id, local_date),
  foreign key (owner_uid, habit_id)
    references public.habits(owner_uid, id) on delete cascade
);

create table if not exists public.exercise_catalog (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  description text,
  duration_minutes integer check (duration_minutes > 0),
  equipment jsonb not null default '[]'::jsonb,
  experience_level text not null default 'beginner'
    check (experience_level in ('beginner', 'intermediate', 'advanced')),
  source_name text,
  source_url text,
  source_version text,
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.meal_catalog (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name text not null,
  description text,
  ingredients jsonb not null default '[]'::jsonb,
  allergens jsonb not null default '[]'::jsonb,
  estimated_cost numeric(12, 2),
  preparation_minutes integer check (preparation_minutes > 0),
  source_name text,
  source_url text,
  source_version text,
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  week_start date not null,
  status text not null default 'draft'
    check (status in ('draft', 'approved', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  unique (owner_uid, id)
);

create unique index if not exists plans_one_approved_per_week
  on public.plans(owner_uid, week_start)
  where status = 'approved';

create table if not exists public.plan_items (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  plan_id uuid not null,
  item_type text not null check (item_type in ('exercise', 'meal', 'sleep', 'habit')),
  exercise_id uuid references public.exercise_catalog(id),
  meal_id uuid references public.meal_catalog(id),
  habit_id uuid,
  start_at timestamptz not null,
  end_at timestamptz,
  status text not null default 'draft'
    check (status in ('draft', 'approved', 'completed', 'skipped')),
  skipped_reason text,
  recommendation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  foreign key (owner_uid, plan_id)
    references public.plans(owner_uid, id) on delete cascade,
  foreign key (owner_uid, habit_id)
    references public.habits(owner_uid, id) on delete cascade
);

create table if not exists public.activity_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  exercise_id uuid references public.exercise_catalog(id),
  activity_name text not null,
  started_at timestamptz,
  ended_at timestamptz,
  duration_seconds integer check (duration_seconds >= 0),
  estimated_distance_meters numeric(12, 2) check (estimated_distance_meters >= 0),
  feeling text,
  route_saved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  unique (owner_uid, id)
);

create table if not exists public.route_points (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  session_id uuid not null,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_meters double precision,
  recorded_at timestamptz not null,
  created_at timestamptz not null default now(),
  foreign key (owner_uid, session_id)
    references public.activity_sessions(owner_uid, id) on delete cascade
);

create table if not exists public.meal_logs (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  meal_id uuid references public.meal_catalog(id),
  meal_name text not null,
  image_path text,
  consumed_at timestamptz not null,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1
);

create table if not exists public.sleep_logs (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  slept_at timestamptz not null,
  woke_at timestamptz not null,
  feeling text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1,
  check (woke_at > slept_at)
);

create table if not exists public.reminder_preferences (
  owner_uid text primary key references public.profiles(owner_uid) on delete cascade,
  quiet_hours_start time,
  quiet_hours_end time,
  reminders_enabled boolean not null default true,
  timezone text not null default 'Asia/Ho_Chi_Minh',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  version integer not null default 1
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  token text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_uid, token)
);

create table if not exists public.consents (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  consent_type text not null,
  granted boolean not null,
  granted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_uid, consent_type)
);

create table if not exists public.sync_changes (
  id uuid primary key default gen_random_uuid(),
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  operation text not null check (operation in ('upsert', 'delete')),
  payload jsonb not null default '{}'::jsonb,
  base_version integer,
  applied boolean not null default false,
  conflict boolean not null default false,
  created_at timestamptz not null default now(),
  applied_at timestamptz
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'availability_blocks', 'goals', 'habits', 'habit_logs',
    'exercise_catalog', 'meal_catalog', 'plans', 'plan_items',
    'activity_sessions', 'meal_logs', 'sleep_logs',
    'reminder_preferences', 'device_tokens', 'consents'
  ]
  loop
    execute format(
      'drop trigger if exists set_updated_at on public.%I',
      table_name
    );
    execute format(
      'create trigger set_updated_at before update on public.%I
       for each row execute function public.set_updated_at()',
      table_name
    );
  end loop;
end;
$$;

alter table public.profiles enable row level security;
alter table public.availability_blocks enable row level security;
alter table public.goals enable row level security;
alter table public.habits enable row level security;
alter table public.habit_logs enable row level security;
alter table public.plans enable row level security;
alter table public.plan_items enable row level security;
alter table public.activity_sessions enable row level security;
alter table public.route_points enable row level security;
alter table public.meal_logs enable row level security;
alter table public.sleep_logs enable row level security;
alter table public.reminder_preferences enable row level security;
alter table public.device_tokens enable row level security;
alter table public.consents enable row level security;
alter table public.sync_changes enable row level security;

do $$
declare
  table_name text;
  policy_prefix text;
begin
  foreach table_name in array array[
    'profiles', 'availability_blocks', 'goals', 'habits', 'habit_logs',
    'plans', 'plan_items', 'activity_sessions', 'route_points',
    'meal_logs', 'sleep_logs', 'reminder_preferences', 'device_tokens',
    'consents', 'sync_changes'
  ]
  loop
    policy_prefix := table_name;

    execute format(
      'drop policy if exists %I on public.%I',
      policy_prefix || '_select_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for select to authenticated
       using (owner_uid = public.current_owner_uid())',
      policy_prefix || '_select_own',
      table_name
    );

    execute format(
      'drop policy if exists %I on public.%I',
      policy_prefix || '_insert_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated
       with check (owner_uid = public.current_owner_uid())',
      policy_prefix || '_insert_own',
      table_name
    );

    execute format(
      'drop policy if exists %I on public.%I',
      policy_prefix || '_update_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for update to authenticated
       using (owner_uid = public.current_owner_uid())
       with check (owner_uid = public.current_owner_uid())',
      policy_prefix || '_update_own',
      table_name
    );

    execute format(
      'drop policy if exists %I on public.%I',
      policy_prefix || '_delete_own',
      table_name
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated
       using (owner_uid = public.current_owner_uid())',
      policy_prefix || '_delete_own',
      table_name
    );
  end loop;
end;
$$;

alter table public.exercise_catalog enable row level security;
alter table public.meal_catalog enable row level security;

drop policy if exists exercise_catalog_read on public.exercise_catalog;
create policy exercise_catalog_read on public.exercise_catalog
  for select to authenticated
  using (approved = true);

drop policy if exists meal_catalog_read on public.meal_catalog;
create policy meal_catalog_read on public.meal_catalog
  for select to authenticated
  using (approved = true);

grant select, insert, update, delete on
  public.profiles,
  public.availability_blocks,
  public.goals,
  public.habits,
  public.habit_logs,
  public.plans,
  public.plan_items,
  public.activity_sessions,
  public.route_points,
  public.meal_logs,
  public.sleep_logs,
  public.reminder_preferences,
  public.device_tokens,
  public.consents,
  public.sync_changes
to authenticated;

grant select on public.exercise_catalog, public.meal_catalog to authenticated;

insert into storage.buckets (id, name, public)
values ('meal-images', 'meal-images', false)
on conflict (id) do update set public = false;

drop policy if exists meal_images_select_own on storage.objects;
create policy meal_images_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'meal-images'
    and (storage.foldername(name))[1] = public.current_owner_uid()
  );

drop policy if exists meal_images_insert_own on storage.objects;
create policy meal_images_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'meal-images'
    and (storage.foldername(name))[1] = public.current_owner_uid()
  );

drop policy if exists meal_images_update_own on storage.objects;
create policy meal_images_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'meal-images'
    and (storage.foldername(name))[1] = public.current_owner_uid()
  )
  with check (
    bucket_id = 'meal-images'
    and (storage.foldername(name))[1] = public.current_owner_uid()
  );

drop policy if exists meal_images_delete_own on storage.objects;
create policy meal_images_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'meal-images'
    and (storage.foldername(name))[1] = public.current_owner_uid()
  );
