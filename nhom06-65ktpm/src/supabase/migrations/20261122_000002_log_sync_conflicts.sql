create table if not exists public.sync_receipts (
  owner_uid text not null references public.profiles(owner_uid) on delete cascade,
  operation_id uuid not null,
  entity_type text not null,
  record_id uuid not null,
  operation text not null check (operation in ('upsert', 'delete')),
  request_payload jsonb,
  base_version integer,
  outcome text check (outcome in ('applied', 'conflict')),
  server_version integer,
  server_record jsonb,
  created_at timestamptz not null default now(),
  primary key (owner_uid, operation_id)
);

alter table public.sync_receipts enable row level security;
revoke all on public.sync_receipts from anon, authenticated;

-- During the rollout, repositories still write directly. Keep RLS as the
-- authorization boundary until every log repository calls apply_log_sync.
grant insert, update, delete on
  public.habit_logs,
  public.activity_sessions,
  public.meal_logs,
  public.sleep_logs
to authenticated;

create or replace function public.apply_log_sync(
  p_operation_id uuid,
  p_entity_type text,
  p_record_id uuid,
  p_operation text,
  p_payload jsonb,
  p_base_version integer
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
declare
  v_owner_uid text := auth.jwt()->>'sub';
  v_table text;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb)
    - array['id', 'owner_uid', 'version', 'created_at', 'updated_at'];
  v_insert_payload jsonb;
  v_existing public.sync_receipts%rowtype;
  v_outcome text;
  v_server_version integer;
  v_server_record jsonb;
  v_columns text;
  v_merged_columns text;
  v_match_clause text := 'target.id = $3';
  v_row_count integer;
begin
  if p_operation_id is null or p_record_id is null then
    raise exception 'Operation ID and record ID are required'
      using errcode = '22023';
  end if;

  if v_owner_uid is null or v_owner_uid = '' then
    raise exception 'Authenticated Firebase UID is required'
      using errcode = '28000';
  end if;

  insert into public.profiles (owner_uid)
  values (v_owner_uid)
  on conflict (owner_uid) do nothing;

  if p_entity_type is null or p_entity_type not in (
    'habit_log', 'activity_session', 'meal_log', 'sleep_log'
  ) then
    raise exception 'Unsupported log entity type'
      using errcode = '22023';
  end if;

  if p_operation is null or p_operation not in ('upsert', 'delete') then
    raise exception 'Unsupported log operation'
      using errcode = '22023';
  end if;

  if p_operation = 'upsert'
     and (p_payload is null or jsonb_typeof(p_payload) <> 'object') then
    raise exception 'Upsert payload must be a JSON object'
      using errcode = '22023';
  end if;
  if p_operation = 'delete' and p_payload is not null then
    raise exception 'Delete payload must be null'
      using errcode = '22023';
  end if;
  if p_base_version < 0 then
    raise exception 'Base version must not be negative'
      using errcode = '22023';
  end if;

  insert into public.sync_receipts (
    owner_uid,
    operation_id,
    entity_type,
    record_id,
    operation,
    request_payload,
    base_version
  )
  values (
    v_owner_uid,
    p_operation_id,
    p_entity_type,
    p_record_id,
    p_operation,
    p_payload,
    p_base_version
  )
  on conflict (owner_uid, operation_id) do nothing;

  get diagnostics v_row_count = row_count;
  if v_row_count = 0 then
    select *
    into v_existing
    from public.sync_receipts
    where owner_uid = v_owner_uid
      and operation_id = p_operation_id;

    if not found then
      raise exception 'Could not load idempotency receipt'
        using errcode = '40001';
    end if;

    if v_existing.entity_type is distinct from p_entity_type
       or v_existing.record_id is distinct from p_record_id
       or v_existing.operation is distinct from p_operation
       or v_existing.request_payload is distinct from p_payload
       or v_existing.base_version is distinct from p_base_version then
      raise exception 'Operation ID was reused for a different change'
        using errcode = '22023';
    end if;

    return query
      select v_existing.outcome,
             v_existing.server_version,
             v_existing.server_record;
    return;
  end if;

  v_table := case p_entity_type
    when 'habit_log' then 'habit_logs'
    when 'activity_session' then 'activity_sessions'
    when 'meal_log' then 'meal_logs'
    when 'sleep_log' then 'sleep_logs'
  end;

  if p_operation = 'upsert' and p_base_version is null then
    v_insert_payload := v_payload || jsonb_build_object(
      'id', p_record_id,
      'owner_uid', v_owner_uid,
      'version', 1,
      'created_at', now(),
      'updated_at', now()
    );
    if p_entity_type = 'habit_log'
       and not (v_payload ? 'logged_at') then
      v_insert_payload := v_insert_payload
        || jsonb_build_object('logged_at', now());
    elsif p_entity_type = 'activity_session'
       and not (v_payload ? 'route_saved') then
      v_insert_payload := v_insert_payload
        || jsonb_build_object('route_saved', false);
    end if;

    execute format(
      'insert into public.%1$I as target
       select * from jsonb_populate_record(null::public.%1$I, $1)
       on conflict do nothing
       returning target.version, to_jsonb(target)',
      v_table
    )
    into v_server_version, v_server_record
    using v_insert_payload;

    get diagnostics v_row_count = row_count;
    if v_row_count = 1 then
      v_outcome := 'applied';
    else
      v_outcome := 'conflict';
    end if;
  elsif p_operation = 'upsert' then
    if p_entity_type = 'habit_log' then
      v_match_clause := $match$
        (
          target.id = $3
          or (
            target.habit_id = ($1->>'habit_id')::uuid
            and target.local_date = ($1->>'local_date')::date
          )
        )
      $match$;
    end if;

    select string_agg(format('%I', column_name), ', ' order by ordinal_position),
           string_agg(format('merged.%I', column_name), ', ' order by ordinal_position)
    into v_columns, v_merged_columns
    from information_schema.columns
    where table_schema = 'public'
      and table_name = v_table
      and column_name not in (
        'id', 'owner_uid', 'version', 'created_at', 'updated_at'
      );

    execute format(
      'update public.%1$I as target
       set (%2$s, version, updated_at) = (
         select %3$s, target.version + 1, now()
         from jsonb_populate_record(
           null::public.%1$I,
           to_jsonb(target) || $1
         ) as merged
       )
       where target.owner_uid = $2
         and %4$s
         and target.version = $4
       returning target.version, to_jsonb(target)',
      v_table,
      v_columns,
      v_merged_columns,
      v_match_clause
    )
    into v_server_version, v_server_record
    using v_payload, v_owner_uid, p_record_id, p_base_version;

    get diagnostics v_row_count = row_count;
    if v_row_count = 1 then
      v_outcome := 'applied';
    else
      v_outcome := 'conflict';
    end if;
  elsif p_base_version is null then
    execute format(
      'select target.version, to_jsonb(target)
       from public.%I as target
       where target.owner_uid = $1 and target.id = $2',
      v_table
    )
    into v_server_version, v_server_record
    using v_owner_uid, p_record_id;

    v_outcome := case
      when v_server_record is null then 'applied'
      else 'conflict'
    end;
  else
    execute format(
      'delete from public.%I as target
       where target.owner_uid = $1
         and target.id = $2
         and target.version = $3
       returning target.version, to_jsonb(target)',
      v_table
    )
    into v_server_version, v_server_record
    using v_owner_uid, p_record_id, p_base_version;

    get diagnostics v_row_count = row_count;
    if v_row_count = 1 then
      v_outcome := 'applied';
    else
      v_outcome := 'conflict';
    end if;
  end if;

  if v_outcome = 'conflict' then
    v_server_version := null;
    v_server_record := null;

    execute format(
      'select target.version, to_jsonb(target)
       from public.%I as target
       where target.owner_uid = $1 and target.id = $2',
      v_table
    )
    into v_server_version, v_server_record
    using v_owner_uid, p_record_id;

    if v_server_record is null
       and p_entity_type = 'habit_log'
       and p_payload ? 'habit_id'
       and p_payload ? 'local_date' then
      execute $lookup$
        select target.version, to_jsonb(target)
         from public.habit_logs as target
         where target.owner_uid = $1
           and target.habit_id = ($2->>'habit_id')::uuid
           and target.local_date = ($2->>'local_date')::date
         limit 1
        $lookup$
      into v_server_version, v_server_record
      using v_owner_uid, p_payload;
    end if;
  end if;

  update public.sync_receipts
  set outcome = v_outcome,
      server_version = v_server_version,
      server_record = v_server_record
  where owner_uid = v_owner_uid
    and operation_id = p_operation_id;

  return query select v_outcome, v_server_version, v_server_record;
end;
$$;

revoke all on function public.apply_log_sync(
  uuid, text, uuid, text, jsonb, integer
) from public, anon;
grant execute on function public.apply_log_sync(
  uuid, text, uuid, text, jsonb, integer
) to authenticated;
