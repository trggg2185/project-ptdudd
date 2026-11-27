import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/backend.dart';
import 'core/local_database.dart';
import 'features/activity/data/repositories/in_memory_activity_repository.dart';
import 'features/activity/data/repositories/supabase_activity_repository.dart';
import 'features/activity/domain/repositories/activity_repository.dart';
import 'features/activity/presentation/pages/activity_page.dart';
import 'features/auth/domain/auth_repository.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/habits/data/repositories/in_memory_habit_repository.dart';
import 'features/habits/data/repositories/supabase_habit_repository.dart';
import 'features/habits/domain/repositories/habit_repository.dart';
import 'features/habits/presentation/pages/habits_page.dart';
import 'features/notifications/data/gateways/flutter_local_notifications_gateway.dart';
import 'features/notifications/data/gateways/in_memory_local_notification_gateway.dart';
import 'features/notifications/data/repositories/in_memory_notification_repository.dart';
import 'features/notifications/data/repositories/supabase_notification_repository.dart';
import 'features/notifications/domain/repositories/local_notification_gateway.dart';
import 'features/notifications/domain/repositories/notification_repository.dart';
import 'features/notifications/domain/services/notification_account_coordinator.dart';
import 'features/notifications/presentation/pages/notifications_page.dart';
import 'features/nutrition/presentation/pages/meal_journal_page.dart';
import 'features/sleep/data/repositories/in_memory_sleep_repository.dart';
import 'features/sleep/data/repositories/supabase_sleep_repository.dart';
import 'features/sleep/domain/repositories/sleep_repository.dart';
import 'features/sleep/presentation/pages/sleep_page.dart';
import 'features/profile/data/supabase_profile_repository.dart';
import 'features/profile/presentation/profile_page.dart';

/// Khởi tạo và phân giải repository phù hợp cho module Thói quen:
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

/// Khởi tạo và phân giải repository phù hợp cho module Giấc ngủ & Lịch sinh hoạt (Issue #5):
/// - Khi Supabase đã khởi tạo: kết nối qua `SupabaseSleepRepository`.
/// - Khi chạy độc lập/offline: dùng `InMemorySleepRepository(seedWithSamples: true)` (demo ngoại tuyến).
SleepRepository resolveSleepRepository({SleepRepository? customRepository}) {
  if (customRepository != null) return customRepository;

  try {
    if (Supabase.instance.isInitialized) {
      return SupabaseSleepRepository();
    }
  } catch (_) {
    // Supabase chưa được khởi tạo
  }

  return InMemorySleepRepository(seedWithSamples: true);
}

ActivityRepository resolveActivityRepository({
  ActivityRepository? customRepository,
}) {
  if (customRepository != null) return customRepository;

  try {
    if (Supabase.instance.isInitialized) {
      return SupabaseActivityRepository();
    }
  } catch (_) {}

  return InMemoryActivityRepository();
}

/// Khởi tạo và phân giải repository phù hợp cho module Nhắc lịch & Giờ yên lặng (Issue #6):
/// - Khi Supabase đã khởi tạo: kết nối qua `SupabaseNotificationRepository`.
/// - Khi chạy độc lập/offline: dùng `InMemoryNotificationRepository(seedWithSamples: true)`.
NotificationRepository resolveNotificationRepository({
  NotificationRepository? customRepository,
}) {
  if (customRepository != null) return customRepository;

  try {
    if (Supabase.instance.isInitialized) {
      return SupabaseNotificationRepository();
    }
  } catch (_) {
    // Supabase chưa được khởi tạo
  }

  return InMemoryNotificationRepository(seedWithSamples: true);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthyLifeApp());
}

/// Ứng dụng HealthyLife — Trợ lý kỷ luật và lối sống lành mạnh.
class HealthyLifeApp extends StatefulWidget {
  final HabitRepository? habitRepository;
  final SleepRepository? sleepRepository;
  final NotificationRepository? notificationRepository;
  final LocalNotificationGateway? notificationGateway;

  const HealthyLifeApp({
    super.key,
    this.habitRepository,
    this.sleepRepository,
    this.notificationRepository,
    this.notificationGateway,
  });

  @override
  State<HealthyLifeApp> createState() => _HealthyLifeAppState();
}

class _HealthyLifeAppState extends State<HealthyLifeApp> {
  late Future<AuthRepository?> _startup = _start();
  late final _mealDatabase = LocalDatabase();
  late final LocalNotificationGateway _notificationGateway =
      widget.notificationGateway ?? FlutterLocalNotificationsGateway();
  late final NotificationAccountCoordinator _notificationAccountCoordinator =
      NotificationAccountCoordinator(
        gateway: _notificationGateway,
        repositoryResolver: () {
          try {
            if (Supabase.instance.isInitialized) {
              return SupabaseNotificationRepository();
            }
          } catch (_) {}
          return null;
        },
      );

  Future<AuthRepository?> _start() async {
    try {
      return await initializeBackend();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nếu được truyền notificationRepository cụ thể (ví dụ trong widget test hoặc demo độc lập):
    if (widget.notificationRepository != null) {
      final demoGateway =
          widget.notificationGateway ?? InMemoryLocalNotificationGateway();
      return MaterialApp(
        title: 'HealthyLife - Nhắc lịch & Giờ yên lặng',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff216a52)),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: NotificationsPage(
          repository: widget.notificationRepository!,
          gateway: demoGateway,
          currentUserId: 'demo-user-duc-2351170585',
        ),
      );
    }
    // Nếu được truyền sleepRepository cụ thể (ví dụ trong widget test hoặc demo độc lập):
    if (widget.sleepRepository != null) {
      return MaterialApp(
        title: 'HealthyLife - Giấc ngủ & Lịch sinh hoạt',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff216a52)),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: SleepPage(
          repository: widget.sleepRepository!,
          currentUserId: 'demo-user-duc-2351170585',
        ),
      );
    }

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
              profilePageBuilder: (session) => ProfilePage(
                repository: SupabaseProfileRepository(
                  Supabase.instance.client,
                  session.uid,
                ),
              ),
              habitsPageBuilder: (session) => HabitsPage(
                repository: SupabaseHabitRepository(),
                currentUserId: session.uid,
              ),
              sleepPageBuilder: (session) => SleepPage(
                repository: SupabaseSleepRepository(),
                currentUserId: session.uid,
              ),
              nutritionPageBuilder: (session) => MealJournalPage(
                client: Supabase.instance.client,
                ownerUid: session.uid,
                currentOwnerUid: () => FirebaseAuth.instance.currentUser?.uid,
                localDatabase:
                    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                    ? _mealDatabase
                    : null,
              ),
              activityPageBuilder: (session) => ActivityPage(
                repository: resolveActivityRepository(),
                ownerUid: session.uid,
              ),
              notificationsPageBuilder: (session) => NotificationsPage(
                repository: SupabaseNotificationRepository(),
                gateway: _notificationGateway,
                currentUserId: session.uid,
                accountCoordinator: _notificationAccountCoordinator,
              ),
              onBeforeSignOut:
                  _notificationAccountCoordinator.handleBeforeSignOut,
              onAccountChanged: (previousUid, nextUid) =>
                  _notificationAccountCoordinator.handleAccountChanged(
                    previousUid: previousUid,
                    nextUid: nextUid,
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
