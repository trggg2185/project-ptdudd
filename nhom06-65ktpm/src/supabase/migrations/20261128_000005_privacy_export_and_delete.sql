create or replace function public.export_my_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  owner_uid text := public.current_owner_uid();
  result jsonb;
begin
  if owner_uid is null or owner_uid = '' then
    raise exception 'Authenticated owner UID is required';
  end if;

  select jsonb_build_object(
    'profile', (
      select to_jsonb(p) from public.profiles p where p.owner_uid = owner_uid
    ),
    'availability_blocks', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at), '[]'::jsonb)
      from public.availability_blocks r where r.owner_uid = owner_uid
    ),
    'goals', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at), '[]'::jsonb)
      from public.goals r where r.owner_uid = owner_uid
    ),
    'habits', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at), '[]'::jsonb)
      from public.habits r where r.owner_uid = owner_uid
    ),
    'habit_logs', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.logged_at), '[]'::jsonb)
      from public.habit_logs r where r.owner_uid = owner_uid
    ),
    'plans', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at), '[]'::jsonb)
      from public.plans r where r.owner_uid = owner_uid
    ),
    'plan_items', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at), '[]'::jsonb)
      from public.plan_items r where r.owner_uid = owner_uid
    ),
    'activity_sessions', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at), '[]'::jsonb)
      from public.activity_sessions r where r.owner_uid = owner_uid
    ),
    'route_points', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.recorded_at), '[]'::jsonb)
      from public.route_points r where r.owner_uid = owner_uid
    ),
    'meal_logs', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.consumed_at), '[]'::jsonb)
      from public.meal_logs r where r.owner_uid = owner_uid
    ),
    'sleep_logs', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.slept_at), '[]'::jsonb)
      from public.sleep_logs r where r.owner_uid = owner_uid
    ),
    'reminder_preferences', (
      select to_jsonb(r) from public.reminder_preferences r where r.owner_uid = owner_uid
    ),
    'device_tokens', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at), '[]'::jsonb)
      from public.device_tokens r where r.owner_uid = owner_uid
    ),
    'consents', (
      select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at), '[]'::jsonb)
      from public.consents r where r.owner_uid = owner_uid
    )
  ) into result;

  return result;
end;
$$;

revoke all on function public.export_my_data() from public;
grant execute on function public.export_my_data() to authenticated;

create or replace function public.delete_my_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  owner_uid text := public.current_owner_uid();
  deleted_photos integer := 0;
begin
  if owner_uid is null or owner_uid = '' then
    raise exception 'Authenticated owner UID is required';
  end if;

  delete from storage.objects
  where bucket_id = 'meal-images'
    and (storage.foldername(name))[1] = owner_uid;
  get diagnostics deleted_photos = row_count;

  delete from public.profiles where owner_uid = owner_uid;

  return jsonb_build_object(
    'owner_uid', owner_uid,
    'deleted_photos', deleted_photos,
    'deleted_at', now()
  );
end;
$$;

revoke all on function public.delete_my_data() from public;
grant execute on function public.delete_my_data() to authenticated;
