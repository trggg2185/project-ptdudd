import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/backend.dart';
import 'core/local_database.dart';
import 'core/privacy_service.dart';
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
import 'features/notifications/data/gateways/firebase_messaging_background_handler.dart';
import 'features/notifications/data/gateways/firebase_messaging_gateway.dart';
import 'features/notifications/data/gateways/flutter_local_notifications_gateway.dart';
import 'features/notifications/data/gateways/in_memory_local_notification_gateway.dart';
import 'features/notifications/data/repositories/in_memory_notification_repository.dart';
import 'features/notifications/data/repositories/supabase_notification_repository.dart';
import 'features/notifications/data/stores/in_memory_notification_background_state_store.dart';
import 'features/notifications/data/stores/sqlite_notification_background_state_store.dart';
import 'features/notifications/domain/repositories/fcm_messaging_gateway.dart';
import 'features/notifications/domain/repositories/local_notification_gateway.dart';
import 'features/notifications/domain/repositories/notification_background_state_store.dart';
import 'features/notifications/domain/repositories/notification_repository.dart';
import 'features/notifications/domain/services/notification_account_coordinator.dart';
import 'features/notifications/presentation/pages/notifications_page.dart';
import 'features/nutrition/presentation/pages/meal_journal_page.dart';
import 'features/sleep/data/repositories/in_memory_sleep_repository.dart';
import 'features/sleep/data/repositories/supabase_sleep_repository.dart';
import 'features/sleep/domain/repositories/sleep_repository.dart';
import 'features/sleep/presentation/pages/sleep_page.dart';
import 'features/planner/data/supabase_weekly_plan_repository.dart';
import 'features/planner/domain/weekly_plan.dart';
import 'features/planner/domain/weekly_planner.dart';
import 'features/planner/presentation/planner_page.dart';
import 'features/profile/data/supabase_profile_repository.dart';
import 'features/profile/presentation/profile_page.dart';
import 'features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'features/recommendations/domain/usecases/get_recommendations_usecase.dart';

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
  registerHealthyLifeFcmBackgroundHandler();
  runApp(const HealthyLifeApp());
}

/// Ứng dụng HealthyLife — Trợ lý kỷ luật và lối sống lành mạnh.
class HealthyLifeApp extends StatefulWidget {
  final HabitRepository? habitRepository;
  final SleepRepository? sleepRepository;
  final NotificationRepository? notificationRepository;
  final LocalNotificationGateway? notificationGateway;
  final FcmMessagingGateway? fcmMessagingGateway;

  const HealthyLifeApp({
    super.key,
    this.habitRepository,
    this.sleepRepository,
    this.notificationRepository,
    this.notificationGateway,
    this.fcmMessagingGateway,
  });

  @override
  State<HealthyLifeApp> createState() => _HealthyLifeAppState();
}

class _HealthyLifeAppState extends State<HealthyLifeApp>
    with WidgetsBindingObserver {
  late Future<AuthRepository?> _startup = _start();
  late final _mealDatabase = LocalDatabase();
  late final LocalNotificationGateway _notificationGateway =
      widget.notificationGateway ?? FlutterLocalNotificationsGateway();
  late final FcmMessagingGateway _fcmMessagingGateway =
      widget.fcmMessagingGateway ?? FirebaseMessagingGateway();
  late final NotificationBackgroundStateStore _notificationBackgroundStore =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? SqliteNotificationBackgroundStateStore(_mealDatabase)
      : InMemoryNotificationBackgroundStateStore();
  late final NotificationAccountCoordinator _notificationAccountCoordinator =
      NotificationAccountCoordinator(
        gateway: _notificationGateway,
        fcmGateway: _fcmMessagingGateway,
        backgroundStateStore: _notificationBackgroundStore,
        repositoryResolver: () {
          if (widget.notificationRepository != null) {
            return widget.notificationRepository;
          }
          try {
            if (Supabase.instance.isInitialized) {
              return SupabaseNotificationRepository();
            }
          } catch (_) {}
          return null;
        },
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationAccountCoordinator.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_notificationAccountCoordinator.handleAppResumed());
    }
  }

  Future<AuthRepository?> _start() async {
    try {
      return await initializeBackend();
    } catch (_) {
      return null;
    }
  }

  Widget _mealJournal(AuthSession session, {PlanItem? item}) => MealJournalPage(
    client: Supabase.instance.client,
    ownerUid: session.uid,
    currentOwnerUid: () => FirebaseAuth.instance.currentUser?.uid,
    localDatabase: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? _mealDatabase
        : null,
    initialMealName: item?.title,
    mealType: item?.mealType ?? 'lunch',
  );

  Widget _activityJournal(AuthSession session, {PlanItem? item}) =>
      ActivityPage(
        repository: resolveActivityRepository(),
        ownerUid: session.uid,
        initialActivityName: item?.title,
      );

  Widget _sleepJournal(AuthSession session) => SleepPage(
    repository: SupabaseSleepRepository(),
    currentUserId: session.uid,
  );

  Widget _habits(AuthSession session) => HabitsPage(
    repository: SupabaseHabitRepository(),
    currentUserId: session.uid,
  );

  Widget _planner(AuthSession session) {
    final client = Supabase.instance.client;
    final profile = SupabaseProfileRepository(client, session.uid);
    return PlannerPage(
      profileRepository: profile,
      repository: SupabaseWeeklyPlanRepository(client, session.uid),
      planner: const WeeklyPlanner(
        GetRecommendationsUseCase(repository: FixtureCatalogRepository()),
      ),
      profilePageBuilder: (_) => ProfilePage(repository: profile),
      journalPageBuilder: (item) => switch (item.kind) {
        PlanItemKind.meal => _mealJournal(session, item: item),
        PlanItemKind.sleep => _sleepJournal(session),
        PlanItemKind.exercise => _activityJournal(session, item: item),
        PlanItemKind.habit || PlanItemKind.manual => _habits(session),
      },
    );
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
                plannerPageBuilder: (_) => _planner(session),
              ),
              plannerPageBuilder: _planner,
              habitsPageBuilder: _habits,
              sleepPageBuilder: _sleepJournal,
              nutritionPageBuilder: _mealJournal,
              activityPageBuilder: _activityJournal,
              notificationsPageBuilder: (session) => NotificationsPage(
                repository: SupabaseNotificationRepository(),
                gateway: _notificationGateway,
                currentUserId: session.uid,
                accountCoordinator: _notificationAccountCoordinator,
              ),
              privacyServiceBuilder: (session) => PrivacyService(
                client: Supabase.instance.client,
                localDatabase:
                    !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                    ? _mealDatabase
                    : null,
                currentOwnerUid: () => session.uid,
              ),
              onSessionAuthorized:
                  _notificationAccountCoordinator.activateAuthorizedSession,
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
