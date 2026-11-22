import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/habits/data/repositories/in_memory_habit_repository.dart';
import 'features/habits/data/repositories/supabase_habit_repository.dart';
import 'features/habits/domain/repositories/habit_repository.dart';
import 'features/habits/presentation/pages/habits_page.dart';

/// Khởi tạo và phân giải repository phù hợp:
/// - Khi Supabase đã được cấu hình và khởi tạo (`isInitialized == true`):
///   kết nối trực tiếp với backend qua `SupabaseHabitRepository`.
/// - Khi chạy độc lập hoặc offline (chưa khởi tạo Supabase):
///   tự động kích hoạt `InMemoryHabitRepository(seedWithSamples: true)` ở chế độ **Demo ngoại tuyến (In-Memory)**.
///   (Lưu ý: Ở chế độ demo offline này, dữ liệu chỉ lưu trên RAM và không được bảo lưu khi restart app).
HabitRepository resolveHabitRepository({HabitRepository? customRepository}) {
  if (customRepository != null) return customRepository;

  try {
    if (Supabase.instance.isInitialized) {
      return SupabaseHabitRepository();
    }
  } catch (_) {
    // Supabase chưa được khởi tạo
  }

  return InMemoryHabitRepository(seedWithSamples: true);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo repository theo cấu hình môi trường
  final repository = resolveHabitRepository();

  runApp(HealthyLifeApp(habitRepository: repository));
}

/// Ứng dụng HealthyLife — Trợ lý kỷ luật và lối sống lành mạnh.
class HealthyLifeApp extends StatelessWidget {
  final HabitRepository? habitRepository;

  const HealthyLifeApp({super.key, this.habitRepository});

  @override
  Widget build(BuildContext context) {
    final repo = resolveHabitRepository(customRepository: habitRepository);

    return MaterialApp(
      title: 'HealthyLife - Trợ lý kỷ luật',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00897B), // Teal / Emerald chủ đạo cho sức khỏe và kỷ luật
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: HabitsPage(
        repository: repo,
        currentUserId: 'demo-user-duc-2351170585',
      ),
    );
  }
}
