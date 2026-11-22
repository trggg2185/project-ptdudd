import 'package:flutter/material.dart';

import 'features/habits/data/repositories/in_memory_habit_repository.dart';
import 'features/habits/data/repositories/supabase_habit_repository.dart';
import 'features/habits/domain/repositories/habit_repository.dart';
import 'features/habits/presentation/pages/habits_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo repository mặc định với dữ liệu mẫu phong phú phục vụ kiểm thử và chạy độc lập
  final HabitRepository repository = InMemoryHabitRepository(seedWithSamples: true);

  runApp(HealthyLifeApp(habitRepository: repository));
}

/// Ứng dụng HealthyLife — Trợ lý kỷ luật và lối sống lành mạnh.
class HealthyLifeApp extends StatelessWidget {
  final HabitRepository? habitRepository;

  const HealthyLifeApp({super.key, this.habitRepository});

  @override
  Widget build(BuildContext context) {
    // Ưu tiên repository được truyền vào, fallback Supabase (nếu có) hoặc InMemory có dữ liệu mẫu
    final repo = habitRepository ??
        (SupabaseHabitRepository().toString().isNotEmpty
            ? InMemoryHabitRepository(seedWithSamples: true)
            : InMemoryHabitRepository(seedWithSamples: true));

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
