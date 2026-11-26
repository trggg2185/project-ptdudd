-- Enforce server-side MIME type (JPEG/PNG/WebP) and size limit (1 MB)
-- on the private meal-images bucket while preserving public = false
-- and existing per-UID RLS policies on storage.objects.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'meal-images',
  'meal-images',
  false,
  1048576,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set
  public = false,
  file_size_limit = 1048576,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];
