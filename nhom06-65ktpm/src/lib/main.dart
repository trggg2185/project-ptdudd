import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/backend.dart';
import 'features/auth/domain/auth_repository.dart';
import 'features/auth/presentation/auth_gate.dart';
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
  runApp(const HealthyLifeApp());
}

/// Ứng dụng HealthyLife — Trợ lý kỷ luật và lối sống lành mạnh.
class HealthyLifeApp extends StatefulWidget {
  final HabitRepository? habitRepository;

  const HealthyLifeApp({super.key, this.habitRepository});

  @override
  State<HealthyLifeApp> createState() => _HealthyLifeAppState();
}

class _HealthyLifeAppState extends State<HealthyLifeApp> {
  late Future<AuthRepository?> _startup = _start();

  Future<AuthRepository?> _start() async {
    try {
      return await initializeBackend();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nếu được truyền habitRepository cụ thể (ví dụ trong widget test hoặc demo độc lập):
    if (widget.habitRepository != null) {
      return MaterialApp(
        title: 'HealthyLife - Trợ lý kỷ luật',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff216a52)),
        ),
        home: HabitsPage(
          repository: widget.habitRepository!,
          currentUserId: 'demo-user-duc-2351170585',
        ),
      );
    }

    return MaterialApp(
      title: 'HealthyLife',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff216a52)),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: FutureBuilder<AuthRepository?>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.data case final auth?) {
            return AuthGate(
              auth: auth,
              habitsPageBuilder: (session) => HabitsPage(
                repository: SupabaseHabitRepository(),
                currentUserId: session.uid,
              ),
            );
          }

          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Không thể khởi động HealthyLife.'),
                  TextButton(
                    onPressed: () => setState(() => _startup = _start()),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
