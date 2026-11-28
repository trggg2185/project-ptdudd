alter table public.plans add column if not exists timezone text;

alter table public.plan_items
  add column if not exists title text,
  add column if not exists is_locked boolean not null default false,
  add column if not exists meal_type text;

alter table public.plan_items drop constraint if exists plan_items_item_type_check;
alter table public.plan_items add constraint plan_items_item_type_check
  check (item_type in ('exercise', 'meal', 'sleep', 'habit', 'manual'));

create or replace function public.weekly_plan_snapshot(p_plan_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(plan) || jsonb_build_object(
    'plan_items', coalesce((
      select jsonb_agg(to_jsonb(item) order by item.start_at, item.id)
      from public.plan_items as item
      where item.owner_uid = plan.owner_uid and item.plan_id = plan.id
    ), '[]'::jsonb)
  )
  from public.plans as plan
  where plan.id = p_plan_id and plan.owner_uid = public.current_owner_uid();
$$;

create or replace function public.approve_weekly_plan(
  p_expected_owner_uid text,
  p_week_start date,
  p_timezone text,
  p_expected_version integer,
  p_items jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_owner text := public.current_owner_uid();
  v_plan public.plans;
  v_start timestamptz;
  v_end timestamptz;
  v_now timestamptz := statement_timestamp();
begin
  if nullif(v_owner, '') is null or v_owner is distinct from p_expected_owner_uid then
    raise exception 'Planner owner does not match the authenticated user' using errcode = '42501';
  end if;
  if p_week_start is null or extract(isodow from p_week_start) <> 1
     or not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone)
     or jsonb_typeof(p_items) is distinct from 'array' then
    raise exception 'Invalid planning week or timezone' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 150 then
    raise exception 'Too many items in one week' using errcode = '22023';
  end if;
  v_start := p_week_start::timestamp at time zone p_timezone;
  v_end := (p_week_start + 7)::timestamp at time zone p_timezone;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_owner || ':weekly-plan', 0)
  );
  select * into v_plan from public.plans
  where owner_uid = v_owner and week_start = p_week_start and status = 'approved'
  for update;
  if v_plan.version is distinct from p_expected_version then
    raise exception 'Another session changed this weekly plan' using errcode = '40001';
  end if;

  if exists (
    select 1 from jsonb_to_recordset(p_items) as i(
      id uuid, item_type text, title text, start_at timestamptz,
      end_at timestamptz, meal_type text
    )
    where i.id is null or i.item_type is null
      or i.item_type not in ('exercise', 'meal', 'sleep', 'habit', 'manual')
      or coalesce(length(btrim(i.title)), 0) not between 1 and 80
      or i.start_at is null or i.end_at is null or i.end_at <= i.start_at
      or i.start_at < v_start or i.start_at <= v_now or i.end_at > v_end
      or (i.meal_type is not null and (
        i.item_type <> 'meal' or i.meal_type not in ('breakfast', 'lunch', 'dinner', 'snack')
      ))
  ) then
    raise exception 'Invalid scheduled item' using errcode = '22023';
  end if;

  if v_plan.id is null then
    insert into public.profiles (owner_uid) values (v_owner)
      on conflict (owner_uid) do nothing;
    insert into public.plans (owner_uid, week_start, timezone, status)
      values (v_owner, p_week_start, p_timezone, 'approved')
      returning * into v_plan;
  else
    update public.plans
    set version = version + 1, timezone = p_timezone
    where id = v_plan.id and owner_uid = v_owner
    returning * into v_plan;
  end if;

  -- Keep recorded outcomes and elapsed items on this plan for every revision.
  delete from public.plan_items
  where owner_uid = v_owner and plan_id = v_plan.id
    and status in ('draft', 'approved') and start_at > v_now;

  insert into public.plan_items
    (id, plan_id, owner_uid, item_type, title, start_at, end_at,
     status, is_locked, recommendation_reason, meal_type)
  select i.id, v_plan.id, v_owner, i.item_type, btrim(i.title), i.start_at, i.end_at,
    'approved', coalesce(i.is_locked, false), i.recommendation_reason, i.meal_type
  from jsonb_to_recordset(p_items) as i(
    id uuid, item_type text, title text, start_at timestamptz, end_at timestamptz,
    is_locked boolean, recommendation_reason text, meal_type text
  );

  if exists (
    select 1
    from public.plan_items as a
    join public.plan_items as b
      on b.owner_uid = a.owner_uid and b.id <> a.id
    join public.plans as reserved_plan
      on reserved_plan.owner_uid = b.owner_uid and reserved_plan.id = b.plan_id
      and reserved_plan.status = 'approved'
    where a.owner_uid = v_owner and a.plan_id = v_plan.id
      and a.status = 'approved' and a.start_at > v_now
      and b.status <> 'skipped'
      and a.start_at < coalesce(b.end_at, b.start_at + interval '1 minute')
      and b.start_at < a.end_at
  ) then
    raise exception 'The weekly plan contains overlapping items' using errcode = '22023';
  end if;

  return public.weekly_plan_snapshot(v_plan.id);
end;
$$;

create or replace function public.record_weekly_plan_outcome(
  p_expected_owner_uid text,
  p_week_start date,
  p_expected_version integer,
  p_item_id uuid,
  p_outcome text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_owner text := public.current_owner_uid();
  v_plan public.plans;
begin
  if nullif(v_owner, '') is null or v_owner is distinct from p_expected_owner_uid then
    raise exception 'Planner owner does not match the authenticated user' using errcode = '42501';
  end if;
  if p_week_start is null or p_outcome is null
     or p_outcome not in ('completed', 'skipped') then
    raise exception 'Invalid planner outcome' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_owner || ':weekly-plan', 0)
  );
  select * into v_plan from public.plans
  where owner_uid = v_owner and week_start = p_week_start and status = 'approved'
  for update;
  if v_plan.id is null or v_plan.version is distinct from p_expected_version then
    raise exception 'Another session changed this weekly plan' using errcode = '40001';
  end if;

  update public.plan_items set status = p_outcome, version = version + 1
  where owner_uid = v_owner and plan_id = v_plan.id and id = p_item_id
    and status = 'approved' and start_at <= statement_timestamp();
  if not found then
    raise exception 'This item is not ready to record' using errcode = '22023';
  end if;

  update public.plans set version = version + 1
  where id = v_plan.id and owner_uid = v_owner;
  return public.weekly_plan_snapshot(v_plan.id);
end;
$$;

revoke all on function public.weekly_plan_snapshot(uuid) from public, anon;
revoke all on function public.approve_weekly_plan(text, date, text, integer, jsonb) from public, anon;
revoke all on function public.record_weekly_plan_outcome(text, date, integer, uuid, text) from public, anon;
grant execute on function public.weekly_plan_snapshot(uuid) to authenticated;
grant execute on function public.approve_weekly_plan(text, date, text, integer, jsonb) to authenticated;
grant execute on function public.record_weekly_plan_outcome(text, date, integer, uuid, text) to authenticated;
