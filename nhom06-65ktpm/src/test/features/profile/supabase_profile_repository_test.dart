import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/profile/data/supabase_profile_repository.dart';
import 'package:healthylife/features/profile/domain/health_profile.dart';
import 'package:healthylife/features/profile/domain/schedule_block.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'Supabase transport keeps profile metadata and round-trips the night shift',
    () async {
      const owner = 'firebase-owner';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'local-test-key',
      );
      final errors = <Object>[];
      addTearDown(() async {
        await client.dispose();
        await server.close(force: true);
        expect(errors, isEmpty);
      });
      final row = <String, dynamic>{
        'owner_uid': owner,
        'updated_at': '2026-11-24T10:00:00+00:00',
        'timezone': 'Asia/Ho_Chi_Minh',
        'living_conditions': {'existing_key': 'keep'},
      };
      Map<String, dynamic>? slot;
      server.listen((request) async {
        final response = request.response;
        response.headers.contentType = ContentType.json;
        try {
          final query = request.uri.queryParameters;
          final body = await utf8.decoder.bind(request).join();
          switch ((request.method, request.uri.path)) {
            case ('GET', '/rest/v1/profiles'):
              expect(query['owner_uid'], 'eq.$owner');
              final accept = request.headers.value(HttpHeaders.acceptHeader);
              response.write(
                jsonEncode(
                  accept == 'application/vnd.pgrst.object+json' ? row : [row],
                ),
              );
            case ('POST', '/rest/v1/profiles'):
              expect(jsonDecode(body), {'owner_uid': owner});
              expect(
                request.headers.value('prefer'),
                contains('resolution=ignore-duplicates'),
              );
              response.statusCode = HttpStatus.created;
            case ('PATCH', '/rest/v1/profiles'):
              expect(query['owner_uid'], 'eq.$owner');
              expect(query['updated_at'], 'eq.${row['updated_at']}');
              row.addAll(jsonDecode(body) as Map<String, dynamic>);
              response.write(jsonEncode({'owner_uid': owner}));
            case ('GET', '/rest/v1/availability_blocks'):
              expect(query['owner_uid'], 'eq.$owner');
              response.write(jsonEncode([?slot]));
            case ('POST', '/rest/v1/availability_blocks'):
              slot = jsonDecode(body) as Map<String, dynamic>;
              expect(slot!['owner_uid'], owner);
              response.statusCode = HttpStatus.created;
            case ('DELETE', '/rest/v1/availability_blocks'):
              expect(query['owner_uid'], 'eq.$owner');
              expect(query['id'], 'eq.${slot?['id']}');
              slot = null;
              response.statusCode = HttpStatus.noContent;
            default:
              throw StateError(
                'Unexpected ${request.method} ${request.uri.path}',
              );
          }
        } catch (error) {
          errors.add(error);
          response.statusCode = HttpStatus.internalServerError;
          response.write(jsonEncode({'message': 'Unexpected test request'}));
        } finally {
          await response.close();
        }
      });

      final repository = SupabaseProfileRepository(client, owner);
      final initial = await repository.load();
      expect(initial.profile.timeZone, 'Asia/Ho_Chi_Minh');
      expect(initial.profile.adultConfirmed, isFalse);
      expect(initial.blocks, isEmpty);

      await repository.saveProfile(
        HealthProfile(
          adultConfirmed: true,
          timeZone: 'Asia/Ho_Chi_Minh',
          goal: ProfileGoal.regularSleep,
          activityLevel: ActivityLevel.beginner,
          occupation: 'shift',
        ),
      );
      expect(row['living_conditions']['existing_key'], 'keep');
      final block = ScheduleBlock.fromLocal(
        id: '3b4c3f44-8a69-4d25-9926-e27b7c946e81',
        kind: ScheduleKind.work,
        title: 'Ca đêm',
        timeZone: 'Asia/Ho_Chi_Minh',
        date: DateTime.utc(2026, 11, 24),
        startMinute: 1320,
        endMinute: 360,
        travelMinutes: 20,
        repeatsWeekly: true,
        exceptionDates: [DateTime.utc(2026, 12, 1)],
      );
      await repository.saveBlock(block);
      expect(slot?['start_at'], '2026-11-24T15:00:00.000Z');
      expect(slot?['end_at'], '2026-11-24T23:00:00.000Z');
      expect(slot?['exception_dates'], ['2026-12-01']);

      final saved = await repository.load();
      expect(saved.profile.goal, ProfileGoal.regularSleep);
      expect(saved.profile.adultConfirmed, isTrue);
      final restored = saved.blocks.single;
      expect(restored.kind, ScheduleKind.work);
      expect(restored.localEnd.day, 25);
      expect(restored.travelMinutes, 20);
      expect(restored.occupiedTimeOn(DateTime.utc(2026, 12, 1)), isNull);
      await repository.deleteBlock(block.id);
      expect((await repository.load()).blocks, isEmpty);
    },
  );
}
