import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/activity/data/repositories/in_memory_activity_repository.dart';
import 'package:healthylife/features/activity/domain/entities/activity_session.dart';
import 'package:healthylife/features/activity/presentation/pages/activity_page.dart';

void main() {
  testWidgets('ActivityPage supports manual activity log entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityPage(
          repository: InMemoryActivityRepository(),
          ownerUid: 'activity-test-user',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nhật ký vận động'), findsOneWidget);
    expect(find.text('Hoặc nhập thủ công'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('manual-duration')), '35');
    await tester.tap(find.byKey(const Key('save-manual-session')));
    await tester.pumpAndSettle();

    expect(find.textContaining('35 phút'), findsOneWidget);
  });

  testWidgets('ActivityPage renders Start, Pause and Stop controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityPage(
          repository: InMemoryActivityRepository(),
          ownerUid: 'activity-test-user',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('loading can complete after leaving the activity page', (
    tester,
  ) async {
    final repository = _DelayedActivityRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ActivityPage(
          repository: repository,
          ownerUid: 'activity-test-user',
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    repository.sessions.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _DelayedActivityRepository extends InMemoryActivityRepository {
  final sessions = Completer<List<ActivitySession>>();

  @override
  Future<List<ActivitySession>> getSessions({required String ownerUid}) =>
      sessions.future;
}
