-- Catalog data from catalog_seed.json. Apply the migrations before this seed.
-- Supabase assigns UUIDs. The fixture IDs in the JSON are ignored.

insert into public.exercise_catalog (
  slug,
  name,
  description,
  source_name,
  source_url,
  source_version,
  reviewed_at,
  approved,
  duration_minutes,
  equipment,
  experience_level,
  category,
  environment,
  budget_tier,
  estimated_cost_vnd,
  contraindicated_limitations,
  tags
)
select * from jsonb_to_recordset($catalog$
[
  {"id": "ex-walking", "slug": "walking", "name": "Đi bộ ngoài trời", "category": "walking", "duration_minutes": 20, "equipment": [], "experience_level": "beginner", "environment": "outdoor", "budget_tier": "free", "estimated_cost_vnd": 0, "contraindicated_limitations": [], "tags": ["outdoor", "low_impact", "no_equipment", "walking", "daily_habit"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Đi bộ nhịp đều ngoài trời, dễ lồng ghép vào khoảng trống ngắn trong ngày."},
  {"id": "ex-stretching", "slug": "stretching", "name": "Giãn cơ nhẹ tại nhà", "category": "flexibility", "duration_minutes": 10, "equipment": [], "experience_level": "beginner", "environment": "indoor", "budget_tier": "free", "estimated_cost_vnd": 0, "contraindicated_limitations": [], "tags": ["indoor", "low_impact", "no_equipment", "flexibility", "recovery"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Chuỗi động tác giãn cơ nhẹ giúp thư giãn sau giờ học, giờ làm hoặc ca trực."},
  {"id": "ex-desk-mobility", "slug": "desk-mobility-break", "name": "Vận động linh hoạt cổ vai gáy", "category": "flexibility", "duration_minutes": 15, "equipment": [], "experience_level": "beginner", "environment": "indoor", "budget_tier": "free", "estimated_cost_vnd": 0, "contraindicated_limitations": [], "tags": ["indoor", "low_impact", "no_equipment", "desk_worker", "flexibility"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bài vận động nhẹ tại chỗ phù hợp với sinh viên và nhân viên văn phòng ngồi nhiều."},
  {"id": "ex-yoga-mobility", "slug": "yoga-mobility", "name": "Yoga cơ bản và thăng bằng", "category": "flexibility", "duration_minutes": 25, "equipment": ["mat"], "experience_level": "beginner", "environment": "both", "budget_tier": "low", "estimated_cost_vnd": 0, "contraindicated_limitations": [], "tags": ["indoor", "outdoor", "low_impact", "yoga", "flexibility"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Các tư thế yoga cơ bản hỗ trợ thăng bằng và duy trì nhịp sinh hoạt ổn định."},
  {"id": "ex-bodyweight", "slug": "bodyweight-workout", "name": "Tập với trọng lượng cơ thể", "category": "strength", "duration_minutes": 30, "equipment": ["mat"], "experience_level": "intermediate", "environment": "indoor", "budget_tier": "low", "estimated_cost_vnd": 0, "contraindicated_limitations": ["knee_impact"], "tags": ["indoor", "strength", "bodyweight", "full_body"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Chuỗi bài tập sức mạnh cơ bản bằng trọng lượng cơ thể, không cần máy móc."},
  {"id": "ex-resistance-band", "slug": "resistance-band-strength", "name": "Tập kháng lực với dây đàn hồi", "category": "strength", "duration_minutes": 20, "equipment": ["resistance_band"], "experience_level": "beginner", "environment": "indoor", "budget_tier": "low", "estimated_cost_vnd": 0, "contraindicated_limitations": ["shoulder_pain"], "tags": ["indoor", "strength", "low_impact", "compact"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Tăng cường nhóm cơ chính tại nhà bằng dây kháng lực gọn nhẹ, dễ điều chỉnh lực."},
  {"id": "ex-jump-rope", "slug": "jump-rope", "name": "Nhảy dây nhịp trung bình", "category": "cardio", "duration_minutes": 15, "equipment": ["jump_rope"], "experience_level": "intermediate", "environment": "both", "budget_tier": "low", "estimated_cost_vnd": 0, "contraindicated_limitations": ["knee_impact", "ankle_injury", "high_intensity_restricted"], "tags": ["cardio", "short_session", "indoor", "outdoor"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bài tập tim mạch thời lượng ngắn với dây nhảy, phù hợp người đã quen vận động."},
  {"id": "ex-jogging-easy", "slug": "jogging-easy", "name": "Chạy bộ chậm công viên", "category": "cardio", "duration_minutes": 30, "equipment": ["running_shoes"], "experience_level": "intermediate", "environment": "outdoor", "budget_tier": "low", "estimated_cost_vnd": 0, "contraindicated_limitations": ["knee_impact", "ankle_injury"], "tags": ["outdoor", "cardio", "running"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Chạy bộ tốc độ thoải mái ngoài trời, chú trọng duy trì đều đặn theo thể lực."},
  {"id": "ex-dumbbell-full-body", "slug": "dumbbell-full-body", "name": "Tập sức mạnh toàn thân với tạ đơn", "category": "strength", "duration_minutes": 35, "equipment": ["dumbbells", "mat"], "experience_level": "intermediate", "environment": "indoor", "budget_tier": "medium", "estimated_cost_vnd": 0, "contraindicated_limitations": ["lower_back_strain", "shoulder_pain"], "tags": ["indoor", "strength", "full_body"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bài tập nhóm cơ toàn thân với cặp tạ đơn mức vừa sức tại nhà hoặc phòng tập."},
  {"id": "ex-cycling", "slug": "cycling-steady", "name": "Đạp xe nhịp đều ngoài trời", "category": "cycling", "duration_minutes": 40, "equipment": ["bicycle"], "experience_level": "beginner", "environment": "outdoor", "budget_tier": "medium", "estimated_cost_vnd": 0, "contraindicated_limitations": [], "tags": ["outdoor", "cardio", "low_impact", "cycling"], "approved": true, "source_name": "WHO — Physical activity guidelines", "source_url": "https://www.who.int/publications/i/item/9789240015128/", "source_version": "WHO 2020 (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Đạp xe tốc độ vừa phải ở khu vực an toàn, ít áp lực lên khớp gối."}
]
$catalog$::jsonb) as item (
  slug text,
  name text,
  description text,
  source_name text,
  source_url text,
  source_version text,
  reviewed_at date,
  approved boolean,
  duration_minutes integer,
  equipment jsonb,
  experience_level text,
  category text,
  environment text,
  budget_tier text,
  estimated_cost_vnd integer,
  contraindicated_limitations jsonb,
  tags jsonb
)
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  source_name = excluded.source_name,
  source_url = excluded.source_url,
  source_version = excluded.source_version,
  reviewed_at = excluded.reviewed_at,
  approved = excluded.approved,
  duration_minutes = excluded.duration_minutes,
  equipment = excluded.equipment,
  experience_level = excluded.experience_level,
  category = excluded.category,
  environment = excluded.environment,
  budget_tier = excluded.budget_tier,
  estimated_cost_vnd = excluded.estimated_cost_vnd,
  contraindicated_limitations = excluded.contraindicated_limitations,
  tags = excluded.tags;

insert into public.meal_catalog (
  slug,
  name,
  description,
  source_name,
  source_url,
  source_version,
  reviewed_at,
  approved,
  ingredients,
  allergens,
  estimated_cost,
  preparation_minutes,
  meal_type,
  ingredients_clear,
  diet_tags,
  budget_tier,
  requires_cooking,
  notes
)
select * from jsonb_to_recordset($catalog$
[
  {"id": "meal-oat-yogurt-fruit", "slug": "oat-yogurt-fruit", "name": "Yến mạch sữa chua trái cây", "meal_type": "breakfast", "ingredients": ["yen_mach", "sua_chua_khong_duong", "chuoi", "tao"], "ingredients_clear": true, "allergens": ["dairy"], "diet_tags": ["balanced", "vegetarian", "quick_prep", "no_cook"], "requires_cooking": false, "budget_tier": "low", "estimated_cost": 25000, "preparation_minutes": 10, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bữa sáng nhanh gọn kết hợp ngũ cốc nguyên hạt, sữa chua ít đường và trái cây tươi.", "notes": "Người dùng tự điều chỉnh khẩu phần theo nhu cầu sinh hoạt hằng ngày."},
  {"id": "meal-peanut-banana-toast", "slug": "peanut-banana-wholewheat-toast", "name": "Bánh mì nguyên cám bơ đậu phộng chuối", "meal_type": "breakfast", "ingredients": ["banh_mi_nguyen_cam", "bo_dau_phong", "chuoi"], "ingredients_clear": true, "allergens": ["gluten", "peanut"], "diet_tags": ["balanced", "vegetarian", "quick_prep", "no_cook"], "requires_cooking": false, "budget_tier": "low", "estimated_cost": 22000, "preparation_minutes": 5, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bữa sáng không cần nấu, tiện mang đi học hoặc đi làm sớm.", "notes": "Chứa gluten và đậu phộng; chọn bơ đậu phộng ít đường, ít muối."},
  {"id": "meal-chicken-pho", "slug": "chicken-vegetable-pho", "name": "Phở gà nạc nhiều rau", "meal_type": "breakfast", "ingredients": ["banh_pho", "thit_ga_nac", "gia_do", "hanh_la", "rau_thom"], "ingredients_clear": true, "allergens": [], "diet_tags": ["balanced", "high_protein"], "requires_cooking": true, "budget_tier": "medium", "estimated_cost": 45000, "preparation_minutes": 20, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bữa sáng ấm bụng có tinh bột, thịt gà nạc và nhiều rau thơm, giá đỗ.", "notes": "Hạn chế nêm quá mặn khi nấu nước dùng tại nhà."},
  {"id": "meal-rice-vegetable-egg", "slug": "rice-vegetable-egg", "name": "Cơm gạo lứt trứng luộc và rau luộc", "meal_type": "lunch", "ingredients": ["gao_lut", "trung_ga", "bong_cai_xanh", "ca_rot"], "ingredients_clear": true, "allergens": ["egg"], "diet_tags": ["balanced", "vegetarian", "budget_friendly"], "requires_cooking": true, "budget_tier": "low", "estimated_cost": 30000, "preparation_minutes": 20, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bữa trưa đủ tinh bột, đạm từ trứng và rau củ luộc dễ chuẩn bị.", "notes": "Có thể nấu cơm trước để tiết kiệm thời gian giữa giờ làm."},
  {"id": "meal-chicken-sweet-potato", "slug": "grilled-chicken-sweet-potato", "name": "Ức gà áp chảo khoai lang và rau cải", "meal_type": "lunch", "ingredients": ["uc_ga", "khoai_lang", "cai_thia", "dau_oliu"], "ingredients_clear": true, "allergens": [], "diet_tags": ["balanced", "high_protein"], "requires_cooking": true, "budget_tier": "medium", "estimated_cost": 45000, "preparation_minutes": 25, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bữa chính cân đối gồm thịt gia cầm nạc, khoai lang và rau xanh áp chảo ít dầu.", "notes": "Dùng lượng dầu thực vật vừa phải và ưu tiên nêm gia vị nhẹ."},
  {"id": "meal-shrimp-spring-rolls", "slug": "shrimp-fresh-spring-rolls", "name": "Gỏi cuốn tôm thịt rau sống", "meal_type": "lunch", "ingredients": ["banh_trang", "bun_tuoi", "tom", "thit_heo_nac", "rau_xa_lach", "dua_leo", "tuong_dau_nanh", "dau_phong"], "ingredients_clear": true, "allergens": ["shellfish", "seafood", "peanut", "soy"], "diet_tags": ["balanced", "light", "quick_prep"], "requires_cooking": false, "budget_tier": "medium", "estimated_cost": 45000, "preparation_minutes": 15, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Món cuốn thanh nhẹ nhiều rau sống kèm nước chấm tương đậu phộng, phù hợp ngày bận hoặc thời tiết nóng.", "notes": "Bao gồm nước chấm tương đậu nành và đậu phộng; chứa hải sản, đậu phộng và đậu nành."},
  {"id": "meal-lentil-soup", "slug": "lentil-soup", "name": "Súp đậu lăng rau củ", "meal_type": "dinner", "ingredients": ["dau_lang", "ca_rot", "can_tay", "ca_chua", "hanh_tay"], "ingredients_clear": true, "allergens": [], "diet_tags": ["balanced", "vegetarian", "high_fiber"], "requires_cooking": true, "budget_tier": "low", "estimated_cost": 35000, "preparation_minutes": 30, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bữa tối giàu chất xơ từ họ đậu và rau củ, không chứa các dị nguyên phổ biến.", "notes": "Có thể chia sẵn hộp cho người làm ca tối hoặc về muộn."},
  {"id": "meal-tofu-mushroom-rice", "slug": "tofu-mushroom-rice", "name": "Cơm đậu phụ sốt nấm và rau cải", "meal_type": "dinner", "ingredients": ["gao_te", "dau_phu", "nam_huong", "cai_ngot", "toi"], "ingredients_clear": true, "allergens": ["soy"], "diet_tags": ["balanced", "vegetarian", "budget_friendly"], "requires_cooking": true, "budget_tier": "low", "estimated_cost": 32000, "preparation_minutes": 20, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bữa tối đạm thực vật đơn giản, chi phí hợp lý với sinh viên và người đi làm.", "notes": "Chứa đậu nành từ đậu phụ."},
  {"id": "meal-salmon-rice-bowl", "slug": "salmon-brown-rice-bowl", "name": "Cơm gạo lứt cá hồi áp chảo và bơ", "meal_type": "dinner", "ingredients": ["gao_lut", "ca_hoi", "qua_bo", "dua_leo", "me_rang"], "ingredients_clear": true, "allergens": ["fish", "seafood", "sesame"], "diet_tags": ["balanced", "high_protein"], "requires_cooking": true, "budget_tier": "high", "estimated_cost": 85000, "preparation_minutes": 25, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bữa tối có cá béo, ngũ cốc nguyên hạt và rau tươi cho ngày cần đổi vị.", "notes": "Chứa cá và mè rang; tự điều chỉnh khẩu phần theo ngân sách."},
  {"id": "meal-corn-fruit-snack", "slug": "steamed-corn-fruit-snack", "name": "Bắp luộc và trái cây tươi", "meal_type": "snack", "ingredients": ["bap_nep", "oi", "tao"], "ingredients_clear": true, "allergens": [], "diet_tags": ["balanced", "vegetarian", "quick_prep", "no_cook"], "requires_cooking": false, "budget_tier": "low", "estimated_cost": 20000, "preparation_minutes": 10, "approved": true, "source_name": "WHO — Healthy diet", "source_url": "https://www.who.int/news-room/fact-sheets/detail/healthy-diet", "source_version": "WHO Healthy Diet fact sheet (tham khảo 15/11/2026)", "reviewed_at": "2026-11-22", "description": "Bữa phụ đơn giản từ thực phẩm ít chế biến, phù hợp giữa giờ học hoặc ca làm.", "notes": "Rửa sạch trái cây trước khi dùng; không cần thêm đường hay muối chấm."}
]
$catalog$::jsonb) as item (
  slug text,
  name text,
  description text,
  source_name text,
  source_url text,
  source_version text,
  reviewed_at date,
  approved boolean,
  ingredients jsonb,
  allergens jsonb,
  estimated_cost numeric,
  preparation_minutes integer,
  meal_type text,
  ingredients_clear boolean,
  diet_tags jsonb,
  budget_tier text,
  requires_cooking boolean,
  notes text
)
on conflict (slug) do update set
  name = excluded.name,
  description = excluded.description,
  source_name = excluded.source_name,
  source_url = excluded.source_url,
  source_version = excluded.source_version,
  reviewed_at = excluded.reviewed_at,
  approved = excluded.approved,
  ingredients = excluded.ingredients,
  allergens = excluded.allergens,
  estimated_cost = excluded.estimated_cost,
  preparation_minutes = excluded.preparation_minutes,
  meal_type = excluded.meal_type,
  ingredients_clear = excluded.ingredients_clear,
  diet_tags = excluded.diet_tags,
  budget_tier = excluded.budget_tier,
  requires_cooking = excluded.requires_cooking,
  notes = excluded.notes;
