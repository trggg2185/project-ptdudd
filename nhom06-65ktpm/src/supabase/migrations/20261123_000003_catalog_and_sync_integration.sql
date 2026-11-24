alter table public.exercise_catalog
  add column if not exists category text not null default 'general',
  add column if not exists environment text not null default 'both',
  add column if not exists budget_tier text not null default 'free',
  add column if not exists estimated_cost_vnd integer not null default 0,
  add column if not exists contraindicated_limitations jsonb not null default '[]'::jsonb,
  add column if not exists tags jsonb not null default '[]'::jsonb,
  add column if not exists reviewed_at date;

alter table public.meal_catalog
  add column if not exists meal_type text not null default 'lunch',
  add column if not exists ingredients_clear boolean not null default false,
  add column if not exists diet_tags jsonb not null default '[]'::jsonb,
  add column if not exists budget_tier text not null default 'medium',
  add column if not exists requires_cooking boolean not null default true,
  add column if not exists reviewed_at date,
  add column if not exists notes text;

-- Compare the queued owner to the JWT actually sent with this request.
create or replace function public.apply_log_sync(
  p_operation_id uuid,
  p_entity_type text,
  p_record_id uuid,
  p_operation text,
  p_payload jsonb,
  p_base_version integer,
  p_expected_owner_uid text
)
returns table (
  outcome text,
  server_version integer,
  server_record jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if nullif(p_expected_owner_uid, '') is null
     or (auth.jwt()->>'sub') is distinct from p_expected_owner_uid then
    raise exception 'Sync owner does not match the authenticated user'
      using errcode = '42501';
  end if;

  return query select result.outcome, result.server_version, result.server_record
    from public.apply_log_sync(
      p_operation_id, p_entity_type, p_record_id, p_operation,
      p_payload, p_base_version
    ) as result;
end;
$$;

revoke execute on function public.apply_log_sync(
  uuid, text, uuid, text, jsonb, integer
) from public, anon, authenticated;
revoke all on function public.apply_log_sync(
  uuid, text, uuid, text, jsonb, integer, text
) from public, anon;
grant execute on function public.apply_log_sync(
  uuid, text, uuid, text, jsonb, integer, text
) to authenticated;

-- Direct writes during rollout must also invalidate an older queued version.
create or replace function public.advance_log_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.version := old.version + 1;
  return new;
end;
$$;

do $$
declare
  log_table text;
begin
  foreach log_table in array array[
    'habit_logs', 'activity_sessions', 'meal_logs', 'sleep_logs'
  ] loop
    execute format('drop trigger if exists advance_log_version on public.%I', log_table);
    execute format(
      'create trigger advance_log_version before update on public.%I
       for each row execute function public.advance_log_version()',
      log_table
    );
  end loop;
end;
$$;
