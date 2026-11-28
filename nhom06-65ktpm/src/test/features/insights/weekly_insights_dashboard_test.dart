import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/habits/domain/entities/habit.dart';
import 'package:healthylife/features/habits/domain/entities/habit_frequency.dart';
import 'package:healthylife/features/insights/data/fixtures/sample_weekly_insights_fixture.dart';
import 'package:healthylife/features/insights/domain/entities/weekly_insights_summary.dart';
import 'package:healthylife/features/insights/domain/repositories/weekly_insights_source.dart';
import 'package:healthylife/features/insights/domain/services/insights_display_formatter.dart';
import 'package:healthylife/features/insights/domain/usecases/get_weekly_insights_usecase.dart';
import 'package:healthylife/features/insights/presentation/pages/weekly_insights_page.dart';

class _FlakyInsightsSource implements WeeklyInsightsSource {
  int loadCalls = 0;
  bool shouldFail = true;

  @override
  Future<WeeklyInsightsRawData> loadWeeklyData({
    required String ownerUid,
    required DateTime weekStart,
    required DateTime weekEnd,
    required DateTime referenceDate,
  }) async {
    loadCalls++;
    if (shouldFail) {
      throw StateError('Simulated network error');
    }
    if (ownerUid == 'uid-b') {
      return const WeeklyInsightsRawData();
    }
    return SampleWeeklyInsightsFixture.balancedWeek(ownerUid: ownerUid);
  }
}

void main() {
  group('InsightsDisplayFormatter & ranh giới phi y khoa (Issue #12 - Tiêu chí 2)', () {
    test('phát hiện đúng cụm từ điểm sức khỏe/y khoa nhưng cho phép tuyên bố phủ định chuẩn', () {
      expect(
        InsightsDisplayFormatter.containsForbiddenHealthScoreClaim(
          'Điểm sức khỏe tuần này: 85/100',
        ),
        isTrue,
      );
      expect(
        InsightsDisplayFormatter.containsForbiddenHealthScoreClaim(
          'Weekly Health Score: 90',
        ),
        isTrue,
      );
      expect(
        InsightsDisplayFormatter.containsForbiddenHealthScoreClaim(
          WeeklyInsightsSummary.nonMedicalDisclaimer,
        ),
        isFalse,
      );
    });

    test('định dạng rõ nguồn nhập tay / thiết bị GPS / camera và không dùng nhãn điểm sức khỏe', () async {
      final useCase = GetWeeklyInsightsUseCase(
        source: FixtureWeeklyInsightsSource(),
      );
      final summary = await useCase(
        ownerUid: 'uid-demo',
        referenceDate: DateTime(2026, 11, 27),
      );

      final activitySources = InsightsDisplayFormatter.formatActivitySources(
        summary.activity,
      );
      expect(activitySources, contains('Thiết bị (GPS trong phiên): 1 buổi'));
      expect(activitySources, contains('Nhập tay: 1 buổi'));

      final mealSources = InsightsDisplayFormatter.formatMealSources(
        summary.meals,
      );
      expect(mealSources, contains('Camera / Thư viện ảnh: 1 bữa'));
      expect(mealSources, contains('Nhập tay: 1 bữa'));

      final notes = InsightsDisplayFormatter.buildNeutralWeeklyNotes(summary);
      expect(notes, isNotEmpty);
      for (final note in notes) {
        expect(
          InsightsDisplayFormatter.containsForbiddenHealthScoreClaim(note),
          isFalse,
        );
      }
    });
  });

  group('Widget tests WeeklyInsightsPage & DashboardView (Issue #12 - Tiêu chí 2)', () {
    testWidgets(
      'hiển thị tách biệt chưa ghi nhận với không hoàn thành, nguồn nhập tay/thiết bị và tuyệt đối không gọi là điểm sức khỏe',
      (tester) async {
        final useCase = GetWeeklyInsightsUseCase(
          source: FixtureWeeklyInsightsSource(),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WeeklyInsightsPage(
              ownerUid: 'uid-demo',
              useCase: useCase,
              referenceDate: DateTime(2026, 11, 27),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Lưu ý phi y khoa luôn hiển thị
        expect(
          find.text(WeeklyInsightsSummary.nonMedicalDisclaimer),
          findsOneWidget,
        );

        // Thói quen & Streak: tách bạch Không hoàn thành (1) vs Chưa ghi nhận (2)
        expect(find.text('Tỷ lệ hoàn thành: 66.7%'), findsOneWidget);
        expect(find.textContaining('Streak hiện tại cao nhất: 6 ngày'), findsOneWidget);
        expect(find.text('Không hoàn thành: 1'), findsOneWidget);
        expect(find.text('Chưa ghi nhận: 2'), findsOneWidget);

        // Thời lượng tập luyện & nguồn nhập tay / GPS
        expect(find.text('Tổng thời lượng tập: 50 phút'), findsOneWidget);
        expect(
          find.textContaining('Thiết bị (GPS trong phiên): 1 buổi'),
          findsOneWidget,
        );
        expect(find.textContaining('Nhập tay: 1 buổi'), findsOneWidget);

        // Cuộn xuống kiểm tra Giấc ngủ tự khai báo & Bữa ăn
        final scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Giấc ngủ tự ghi theo tuần'),
          200,
          scrollable: scrollable,
        );
        expect(
          find.text('Trung bình ngày đã ghi: 7 giờ 30 phút'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Nguồn: Tự khai báo (không đo bằng cảm biến'),
          findsOneWidget,
        );
        expect(find.text('Chưa ghi nhận: 2 ngày'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Nhật ký bữa ăn theo tuần'),
          200,
          scrollable: scrollable,
        );
        expect(
          find.textContaining('Camera / Thư viện ảnh: 1 bữa'),
          findsOneWidget,
        );

        // Quét toàn bộ Text đang hiển thị: không có bất kỳ nhãn nào gọi là "điểm sức khỏe"
        for (final element in find.byType(Text).evaluate()) {
          final widget = element.widget as Text;
          final data = widget.data ?? '';
          expect(
            InsightsDisplayFormatter.containsForbiddenHealthScoreClaim(data),
            isFalse,
            reason: 'Nhãn không được gọi là điểm sức khỏe: "$data"',
          );
        }
      },
    );

    testWidgets(
      'tuần thiếu dữ liệu chỉ báo Chưa ghi nhận, không biến ngày trống thành Không hoàn thành',
      (tester) async {
        final useCase = GetWeeklyInsightsUseCase(
          source: FixtureWeeklyInsightsSource(
            builder: (uid) => WeeklyInsightsRawData(
              habits: [
                Habit(
                  id: 'h-only',
                  ownerUid: uid,
                  name: 'Uống đủ nước',
                  frequency: const HabitFrequency.daily(),
                  createdAt: DateTime(2026, 11, 23),
                ),
              ],
            ),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: WeeklyInsightsPage(
              ownerUid: 'uid-missing',
              useCase: useCase,
              referenceDate: DateTime(2026, 11, 24), // Thứ Ba
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Không hoàn thành: 0'), findsOneWidget);
        expect(find.text('Chưa ghi nhận: 2'), findsOneWidget);
        expect(
          find.text('Tổng thời lượng tập: Chưa ghi nhận'),
          findsOneWidget,
        );

        final scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Trung bình ngày đã ghi: Chưa ghi nhận'),
          200,
          scrollable: scrollable,
        );
        expect(
          find.text('Trung bình ngày đã ghi: Chưa ghi nhận'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'xử lý lỗi tải có nút Thử lại và xóa cache khi đổi ownerUid',
      (tester) async {
        final flakySource = _FlakyInsightsSource();
        final useCase = GetWeeklyInsightsUseCase(source: flakySource);

        await tester.pumpWidget(
          MaterialApp(
            home: WeeklyInsightsPage(
              ownerUid: 'uid-a',
              useCase: useCase,
              referenceDate: DateTime(2026, 11, 27),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Không thể tải dữ liệu tổng kết tuần'),
          findsOneWidget,
        );
        expect(find.text('Thử lại'), findsOneWidget);

        // Thử lại thành công cho uid-a
        flakySource.shouldFail = false;
        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();
        expect(find.text('Tổng thời lượng tập: 50 phút'), findsOneWidget);

        // Đổi sang uid-b (tài khoản trống) -> không còn hiển thị số liệu của uid-a
        await tester.pumpWidget(
          MaterialApp(
            home: WeeklyInsightsPage(
              ownerUid: 'uid-b',
              useCase: useCase,
              referenceDate: DateTime(2026, 11, 27),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Tổng thời lượng tập: 50 phút'), findsNothing);
        expect(
          find.text('Tổng thời lượng tập: Chưa ghi nhận'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'giao diện responsive 1 cột (Android 390px) và 2 cột (Web 1280px) cùng điều hướng tuần',
      (tester) async {
        final useCase = GetWeeklyInsightsUseCase(
          source: FixtureWeeklyInsightsSource(),
        );

        // 1. Mobile 390x844
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: WeeklyInsightsPage(
              ownerUid: 'uid-demo',
              useCase: useCase,
              referenceDate: DateTime(2026, 11, 27),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Tuần 23/11/2026 – 29/11/2026'), findsOneWidget);

        // Chuyển sang tuần trước rồi quay lại tuần hiện tại
        await tester.tap(find.byTooltip('Tuần trước'));
        await tester.pumpAndSettle();
        expect(find.text('Tuần 16/11/2026 – 22/11/2026'), findsOneWidget);
        expect(find.text('Về tuần hiện tại'), findsOneWidget);

        await tester.tap(find.text('Về tuần hiện tại'));
        await tester.pumpAndSettle();
        expect(find.text('Tuần 23/11/2026 – 29/11/2026'), findsOneWidget);

        // 2. Web 1280x800 (2 cột)
        tester.view.physicalSize = const Size(1280, 800);
        await tester.pumpWidget(
          MaterialApp(
            home: WeeklyInsightsPage(
              ownerUid: 'uid-demo',
              useCase: useCase,
              referenceDate: DateTime(2026, 11, 27),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Kỷ luật thói quen & Streak'), findsOneWidget);
        expect(find.text('Thời lượng tập luyện theo tuần'), findsOneWidget);
        expect(find.text('Giấc ngủ tự ghi theo tuần'), findsOneWidget);
        expect(find.text('Nhật ký bữa ăn theo tuần'), findsOneWidget);
      },
    );
  });
}
