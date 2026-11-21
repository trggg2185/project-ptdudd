insert into public.exercise_catalog (
  slug,
  name,
  description,
  duration_minutes,
  equipment,
  experience_level,
  source_name,
  source_url,
  source_version,
  approved
) values
  (
    'walking',
    'Đi bộ',
    'Hoạt động có cường độ thấp, phù hợp khi có khoảng trống ngắn.',
    20,
    '[]'::jsonb,
    'beginner',
    'WHO',
    'https://www.who.int/publications/i/item/9789240015128',
    '2020 guideline',
    true
  ),
  (
    'stretching',
    'Giãn cơ',
    'Bài giãn cơ nhẹ tại nhà.',
    10,
    '[]'::jsonb,
    'beginner',
    'WHO',
    'https://www.who.int/publications/i/item/9789240015128',
    '2020 guideline',
    true
  ),
  (
    'bodyweight-workout',
    'Tập với trọng lượng cơ thể',
    'Chuỗi bài tập cơ bản không cần máy móc.',
    30,
    '["mat"]'::jsonb,
    'intermediate',
    'WHO',
    'https://www.who.int/publications/i/item/9789240015128',
    '2020 guideline',
    true
  )
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  duration_minutes = excluded.duration_minutes,
  equipment = excluded.equipment,
  experience_level = excluded.experience_level,
  source_name = excluded.source_name,
  source_url = excluded.source_url,
  source_version = excluded.source_version,
  approved = excluded.approved;

insert into public.meal_catalog (
  slug,
  name,
  description,
  ingredients,
  allergens,
  estimated_cost,
  preparation_minutes,
  source_name,
  source_url,
  source_version,
  approved
) values
  (
    'oat-yogurt-fruit',
    'Yến mạch sữa chua trái cây',
    'Bữa sáng đơn giản, có thể điều chỉnh khẩu phần.',
    '["oat", "yogurt", "fruit"]'::jsonb,
    '["dairy"]'::jsonb,
    25000,
    10,
    'Healthy diet fact sheet',
    'https://www.who.int/news-room/fact-sheets/detail/healthy-diet',
    'WHO healthy diet',
    true
  ),
  (
    'rice-vegetable-egg',
    'Cơm trứng rau',
    'Bữa ăn có tinh bột, đạm và rau; người dùng tự điều chỉnh theo nhu cầu.',
    '["rice", "egg", "vegetables"]'::jsonb,
    '["egg"]'::jsonb,
    30000,
    20,
    'Healthy diet fact sheet',
    'https://www.who.int/news-room/fact-sheets/detail/healthy-diet',
    'WHO healthy diet',
    true
  ),
  (
    'lentil-soup',
    'Súp đậu lăng',
    'Món ăn có đậu lăng, rau và gia vị.',
    '["lentils", "vegetables", "spices"]'::jsonb,
    '[]'::jsonb,
    35000,
    35,
    'Healthy diet fact sheet',
    'https://www.who.int/news-room/fact-sheets/detail/healthy-diet',
    'WHO healthy diet',
    true
  )
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  ingredients = excluded.ingredients,
  allergens = excluded.allergens,
  estimated_cost = excluded.estimated_cost,
  preparation_minutes = excluded.preparation_minutes,
  source_name = excluded.source_name,
  source_url = excluded.source_url,
  source_version = excluded.source_version,
  approved = excluded.approved;
