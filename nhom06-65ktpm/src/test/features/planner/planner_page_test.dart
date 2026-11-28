import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/planner/domain/weekly_plan.dart';
import 'package:healthylife/features/planner/domain/weekly_plan_repository.dart';
import 'package:healthylife/features/planner/domain/weekly_planner.dart';
import 'package:healthylife/features/planner/presentation/planner_page.dart';
import 'package:healthylife/features/profile/domain/health_profile.dart';
import 'package:healthylife/features/profile/domain/profile_repository.dart';
import 'package:healthylife/features/profile/domain/schedule_block.dart';
import 'package:healthylife/features/recommendations/data/repositories/fixture_catalog_repository.dart';
import 'package:healthylife/features/recommendations/domain/usecases/get_recommendations_usecase.dart';

void main() {
  testWidgets('blocked suggestions keep week navigation and reload available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlannerPage(
          profileRepository: _ProfileRepository(),
          repository: _PlanRepository(),
          planner: const WeeklyPlanner(
            GetRecommendationsUseCase(repository: FixtureCatalogRepository()),
          ),
          profilePageBuilder: (_) => const SizedBox.shrink(),
          journalPageBuilder: (_) => const SizedBox.shrink(),
          now: () => DateTime.utc(2026, 12, 7, 9),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tạo lịch nháp'));
    await tester.pumpAndSettle();

    expect(find.text('Bạn vẫn có thể thêm hoạt động thủ công.'), findsOneWidget);
    expect(find.text('Tải lại'), findsOneWidget);
    expect(find.text('Hủy bản nháp'), findsNothing);
    await tester.tap(find.byTooltip('Tuần trước'));
    await tester.pumpAndSettle();
    expect(find.text('2026-11-30 – 2026-12-06'), findsOneWidget);
    await tester.tap(find.byTooltip('Tuần sau'));
    await tester.pumpAndSettle();
    expect(find.text('2026-12-07 – 2026-12-13'), findsOneWidget);
  });

  testWidgets(
    'a manually planned item needs approval before journaling and reaches the weekly summary',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _PlanRepository();
      var now = DateTime.utc(2026, 12, 7, 9);
      await tester.pumpWidget(
        MaterialApp(
          home: PlannerPage(
            profileRepository: _ProfileRepository(),
            repository: repo,
            planner: const WeeklyPlanner(
              GetRecommendationsUseCase(repository: FixtureCatalogRepository()),
            ),
            profilePageBuilder: (_) =>
                Scaffold(appBar: AppBar(), body: const Text('Hồ sơ thử')),
            journalPageBuilder: (item) =>
                Scaffold(appBar: AppBar(), body: Text('Nhật ký ${item.title}')),
            now: () => now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mở hồ sơ'));
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ thử'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thứ 3 · 8/12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm hoạt động'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tên hoạt động'),
        'Đi bộ sau giờ làm',
      );
      await tester.tap(find.text('Giữ trong bản nháp'));
      await tester.pumpAndSettle();
      expect(find.text('Đi bộ sau giờ làm'), findsOneWidget);
      expect(find.text('Ghi nhật ký'), findsNothing);
      expect(repo.current, isNull);

      await tester.tap(find.text('Duyệt lịch'));
      await tester.pumpAndSettle();
      expect(repo.current!.items.single.isLocked, isTrue);
      expect(repo.current!.items.single.status, PlanItemStatus.approved);
      expect(find.text('Đã duyệt lịch tuần.'), findsOneWidget);

      now = DateTime.utc(2026, 12, 9, 19);
      await tester.tap(find.text('Tải lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ghi nhật ký'));
      await tester.pumpAndSettle();
      expect(find.text('Nhật ký Đi bộ sau giờ làm'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Hoàn thành'));
      await tester.pumpAndSettle();
      expect(repo.current!.items.single.status, PlanItemStatus.completed);
      expect(find.text('Hoàn thành 1/1 · Bỏ qua 0'), findsOneWidget);
    },
  );
}

class _PlanRepository implements WeeklyPlanRepository {
  WeeklyPlan? current;

  @override
  Future<WeeklyPlan?> load(PlanWeek week) async => current;

  @override
  Future<WeeklyPlan> approve({
    required PlanWeek week,
    required int? expectedVersion,
    required List<PlanItem> items,
  }) async => current = WeeklyPlan(
    version: 1,
    items: items.map((item) => _withStatus(item, PlanItemStatus.approved)),
  );

  @override
  Future<WeeklyPlan> recordOutcome({
    required PlanWeek week,
    required int expectedVersion,
    required String itemId,
    required PlanItemStatus outcome,
  }) async => current = WeeklyPlan(
    version: expectedVersion + 1,
    items: current!.items.map(
      (item) => item.id == itemId ? _withStatus(item, outcome) : item,
    ),
  );

  PlanItem _withStatus(PlanItem item, PlanItemStatus status) => PlanItem(
    id: item.id,
    kind: item.kind,
    title: item.title,
    startsAt: item.startsAt,
    endsAt: item.endsAt,
    isLocked: item.isLocked,
    status: status,
  );
}

class _ProfileRepository implements ProfileRepository {
  @override
  Future<ProfileData> load() async =>
      (profile: HealthProfile(timeZone: 'UTC'), blocks: <ScheduleBlock>[]);

  @override
  Future<void> saveProfile(HealthProfile profile) async {}

  @override
  Future<void> saveBlock(ScheduleBlock block) async {}

  @override
  Future<void> deleteBlock(String id) async {}
}
