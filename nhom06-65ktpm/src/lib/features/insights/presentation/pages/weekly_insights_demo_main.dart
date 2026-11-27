import 'package:flutter/material.dart';

import '../../data/fixtures/sample_weekly_insights_fixture.dart';
import '../../domain/usecases/get_weekly_insights_usecase.dart';
import '../widgets/weekly_insights_dashboard_view.dart';

/// Điểm chạy xem trước độc lập cho Dashboard & Tổng kết tuần (Issue #12) bằng
/// dữ liệu fixture mẫu (mock), phục vụ kiểm tra giao diện responsive trên
/// Android và Web mà không chỉnh sửa `lib/main.dart` hay bỏ qua xác thực/RLS.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WeeklyInsightsDemoApp());
}

class WeeklyInsightsDemoApp extends StatelessWidget {
  const WeeklyInsightsDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final useCase = GetWeeklyInsightsUseCase(
      source: FixtureWeeklyInsightsSource(),
    );
    final demoDate = DateTime(2026, 11, 27);

    return MaterialApp(
      title: 'HealthyLife - Xem trước Dashboard tuần (Mock)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff216a52)),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard & Tổng kết tuần'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(32),
            child: Container(
              width: double.infinity,
              color: const Color(0xFFFFF8E1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: const Text(
                'Chế độ xem trước độc lập bằng dữ liệu fixture mẫu (mock) — không kết nối backend.',
                style: TextStyle(fontSize: 12, color: Color(0xFF6D4C00)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: WeeklyInsightsDashboardView(
            ownerUid: 'uid-demo',
            useCase: useCase,
            initialWeekAnchor: demoDate,
            referenceDate: demoDate,
          ),
        ),
      ),
    );
  }
}
