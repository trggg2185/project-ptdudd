import 'package:flutter/material.dart';

import '../../domain/usecases/get_weekly_insights_usecase.dart';
import '../widgets/weekly_insights_dashboard_view.dart';

/// Màn hình độc lập Dashboard & tổng kết tuần (Issue #12), sẵn sàng để nhóm trưởng
/// gắn vào `AuthGate` khi tích hợp điều hướng chung (không tự chỉnh `main.dart`).
class WeeklyInsightsPage extends StatelessWidget {
  final String ownerUid;
  final GetWeeklyInsightsUseCase useCase;
  final DateTime? initialWeekAnchor;
  final DateTime? referenceDate;

  const WeeklyInsightsPage({
    super.key,
    required this.ownerUid,
    required this.useCase,
    this.initialWeekAnchor,
    this.referenceDate,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard & Tổng kết tuần')),
      body: SafeArea(
        child: WeeklyInsightsDashboardView(
          ownerUid: ownerUid,
          useCase: useCase,
          initialWeekAnchor: initialWeekAnchor,
          referenceDate: referenceDate,
        ),
      ),
    );
  }
}
