import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/nutrition/data/repositories/jpeg_meal_photo_compressor.dart';
import 'package:healthylife/features/nutrition/data/repositories/supabase_meal_log_repository.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_log.dart';
import 'package:healthylife/features/nutrition/domain/entities/meal_photo_attachment.dart';
import 'package:healthylife/features/nutrition/domain/services/meal_photo_processor.dart';
import 'package:healthylife/features/nutrition/domain/services/meal_photo_validator.dart';
import 'package:image/image.dart' as image;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('runtime processor resizes and transcodes a selected PNG', () async {
    final original = image.Image(width: 1800, height: 1100);
    image.fill(original, color: image.ColorRgb8(12, 123, 45));
    final prepared =
        await const DefaultMealPhotoProcessor(
          compressor: JpegMealPhotoCompressor(),
        ).prepare(
          SelectedMealPhoto(
            source: MealPhotoSource.gallery,
            fileName: 'meal.png',
            mimeType: 'image/png',
            bytes: image.encodePng(original),
          ),
        );
    final decoded = image.decodeJpg(prepared.bytes);
    expect(decoded?.width, 1600);
    expect(prepared.extension, 'jpg');
    expect(prepared.compressed, isTrue);
    expect(prepared.sizeBytes, lessThanOrEqualTo(1024 * 1024));
    expect(
      const MealPhotoValidator().containsExifOrSensitiveMetadata(
        prepared.bytes,
        mimeType: prepared.mimeType,
      ),
      isFalse,
    );
  });

  test('online journal persists named meals for the active account', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-publishable-key',
      accessToken: () async => 'test-firebase-id-token',
    );
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });

    var active = 'firebase-a';
    final calls = <(String, String, String?)>[];
    final now = DateTime.utc(2026, 11, 27, 5);
    Map<String, dynamic>? payload;
    server.listen((request) async {
      calls.add((
        request.method,
        request.uri.path,
        request.uri.queryParameters['owner_uid'],
      ));
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' && request.uri.path.endsWith('/meal_logs')) {
        payload = jsonDecode(body) as Map<String, dynamic>;
      }
      if (request.method == 'GET') {
        request.response.write(
          jsonEncode([
            {
              ...payload!,
              'created_at': now.toIso8601String(),
              'updated_at': now.toIso8601String(),
            },
          ]),
        );
      }
      await request.response.close();
    });

    final repository = SupabaseMealLogRepository(
      client,
      currentOwnerUid: () => active,
    );
    await repository.saveMealLog(
      MealLog(
        id: '3b4c3f44-8a69-4d25-9926-e27b7c946e81',
        ownerUid: 'firebase-a',
        mealName: 'Cơm trứng',
        consumedAt: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final logs = await repository.getMealLogs(ownerUid: 'firebase-a');
    expect(logs.single.mealName, 'Cơm trứng');
    expect(payload?['owner_uid'], 'firebase-a');
    expect(calls, [
      ('POST', '/rest/v1/profiles', null),
      ('POST', '/rest/v1/meal_logs', null),
      ('GET', '/rest/v1/meal_logs', 'eq.firebase-a'),
    ]);

    active = 'firebase-b';
    await expectLater(
      repository.getMealLogs(ownerUid: 'firebase-a'),
      throwsStateError,
    );
    expect(calls, hasLength(3));
  });
}
