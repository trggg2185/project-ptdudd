-- Issue #5: Backend validation for public.sleep_logs and atomic merge RPC
-- for sleep window preferences inside public.profiles.living_conditions.
-- Note: Needs review by @HanHoangHa before applying to Supabase cloud.

alter table public.sleep_logs
  drop constraint if exists sleep_logs_max_duration_24h;

alter table public.sleep_logs
  add constraint sleep_logs_max_duration_24h
  check (woke_at > slept_at and woke_at <= slept_at + interval '24 hours');

create or replace function public.validate_sleep_log_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.owner_uid is null or btrim(new.owner_uid) = '' then
    raise exception 'Owner UID is required for sleep logs'
      using errcode = '22023';
  end if;

  if new.woke_at <= new.slept_at then
    raise exception 'Wake time must be after sleep time'
      using errcode = '22023';
  end if;

  if new.woke_at > new.slept_at + interval '24 hours' then
    raise exception 'Single sleep log duration must not exceed 24 hours'
      using errcode = '22023';
  end if;

  -- Allow small clock skew (+5 minutes) while rejecting future sleep records.
  if new.slept_at > now() + interval '5 minutes'
     or new.woke_at > now() + interval '5 minutes' then
    raise exception 'Sleep log cannot be recorded in the future'
      using errcode = '22023';
  end if;

  if new.feeling is not null
     and btrim(new.feeling) <> ''
     and new.feeling not in (
       'very_groggy', 'groggy', 'neutral', 'refreshed', 'energized'
     ) then
    raise exception 'Unsupported sleep alertness feeling value'
      using errcode = '22023';
  end if;

  -- Serialize overlap checks per user within the current transaction.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('sleep_logs:' || new.owner_uid)
  );

  if exists (
    select 1
    from public.sleep_logs as existing
    where existing.owner_uid = new.owner_uid
      and existing.id is distinct from new.id
      and existing.slept_at < new.woke_at
      and new.slept_at < existing.woke_at
  ) then
    raise exception 'Sleep log overlaps an existing sleep interval'
      using errcode = '23P01';
  end if;

  return new;
end;
$$;

drop trigger if exists validate_sleep_log_before_write on public.sleep_logs;
create trigger validate_sleep_log_before_write
  before insert or update on public.sleep_logs
  for each row execute function public.validate_sleep_log_before_write();

-- Atomically merge or clear sleep_start / sleep_end / sleep_label inside
-- public.profiles.living_conditions->'healthylife_profile' without overwriting
-- sibling profile preferences updated concurrently by other modules.
create or replace function public.upsert_sleep_window(
  p_sleep_start integer,
  p_sleep_end integer,
  p_sleep_label text,
  p_expected_owner_uid text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_uid text := auth.jwt()->>'sub';
  v_duration integer;
  v_current_living jsonb;
  v_profile_prefs jsonb;
  v_updated_prefs jsonb;
  v_clean_label text := nullif(btrim(coalesce(p_sleep_label, '')), '');
begin
  if nullif(p_expected_owner_uid, '') is null
     or v_owner_uid is null
     or v_owner_uid is distinct from p_expected_owner_uid then
    raise exception 'Profile owner does not match the authenticated user'
      using errcode = '42501';
  end if;

  if (p_sleep_start is null) <> (p_sleep_end is null) then
    raise exception 'Both sleep_start and sleep_end must be provided or both null'
      using errcode = '22023';
  end if;

  if p_sleep_start is not null then
    if p_sleep_start < 0 or p_sleep_start >= 1440
       or p_sleep_end < 0 or p_sleep_end >= 1440
       or p_sleep_start = p_sleep_end then
      raise exception 'Invalid sleep window clock minutes'
        using errcode = '22023';
    end if;

    v_duration := case
      when p_sleep_end > p_sleep_start then p_sleep_end - p_sleep_start
      else (1440 - p_sleep_start) + p_sleep_end
    end;

    if v_duration < 60 or v_duration > 960 then
      raise exception 'Sleep window duration must be between 60 and 960 minutes'
        using errcode = '22023';
    end if;
  end if;

  insert into public.profiles (owner_uid)
  values (v_owner_uid)
  on conflict (owner_uid) do nothing;

  select coalesce(living_conditions, '{}'::jsonb)
  into v_current_living
  from public.profiles
  where owner_uid = v_owner_uid
  for update;

  v_profile_prefs := case
    when jsonb_typeof(v_current_living->'healthylife_profile') = 'object'
      then v_current_living->'healthylife_profile'
    else '{}'::jsonb
  end;

  if p_sleep_start is null then
    v_updated_prefs := v_profile_prefs - array['sleep_start', 'sleep_end', 'sleep_label'];
  else
    v_updated_prefs := (v_profile_prefs - 'sleep_label') || jsonb_build_object(
      'sleep_start', p_sleep_start,
      'sleep_end', p_sleep_end
    );
    if v_clean_label is not null then
      v_updated_prefs := v_updated_prefs || jsonb_build_object('sleep_label', v_clean_label);
    end if;
  end if;

  update public.profiles
  set living_conditions = jsonb_set(
        v_current_living,
        '{healthylife_profile}',
        v_updated_prefs,
        true
      ),
      version = version + 1,
      updated_at = now()
  where owner_uid = v_owner_uid;

  return v_updated_prefs;
end;
$$;

revoke all on function public.upsert_sleep_window(integer, integer, text, text)
  from public, anon;
grant execute on function public.upsert_sleep_window(integer, integer, text, text)
  to authenticated;
