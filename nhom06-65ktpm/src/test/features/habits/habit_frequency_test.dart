import 'package:flutter_test/flutter_test.dart';
import 'package:healthylife/features/habits/domain/entities/habit_frequency.dart';

void main() {
  group('HabitFrequency Tests', () {
    test('Daily frequency is due every day of the week', () {
      const freq = HabitFrequency.daily();
      expect(freq.type, equals(FrequencyType.daily));
      expect(freq.scheduledDays.length, equals(7));

      for (int day = 1; day <= 7; day++) {
        // Monday (2026-11-23) to Sunday (2026-11-29)
        final testDate = DateTime(2026, 11, 22 + day);
        expect(freq.isDueOn(testDate), isTrue);
      }
      expect(freq.displayLabel, equals('Hằng ngày'));
    });

    test('Weekdays frequency is due on Mon-Fri and rest on Sat-Sun', () {
      const freq = HabitFrequency.weekdays();
      expect(freq.type, equals(FrequencyType.customDays));
      expect(freq.scheduledDays, equals({1, 2, 3, 4, 5}));

      final monday = DateTime(2026, 11, 23); // Mon
      final friday = DateTime(2026, 11, 27); // Fri
      final saturday = DateTime(2026, 11, 28); // Sat
      final sunday = DateTime(2026, 11, 29); // Sun

      expect(freq.isDueOn(monday), isTrue);
      expect(freq.isDueOn(friday), isTrue);
      expect(freq.isDueOn(saturday), isFalse);
      expect(freq.isDueOn(sunday), isFalse);
      expect(freq.displayLabel, equals('Ngày trong tuần (T2 - T6)'));
    });

    test('Weekends frequency is due only on Sat-Sun', () {
      const freq = HabitFrequency.weekends();
      expect(freq.type, equals(FrequencyType.customDays));
      expect(freq.scheduledDays, equals({6, 7}));

      final wednesday = DateTime(2026, 11, 25);
      final saturday = DateTime(2026, 11, 28);
      final sunday = DateTime(2026, 11, 29);

      expect(freq.isDueOn(wednesday), isFalse);
      expect(freq.isDueOn(saturday), isTrue);
      expect(freq.isDueOn(sunday), isTrue);
      expect(freq.displayLabel, equals('Cuối tuần (T7, CN)'));
    });

    test('Custom days frequency behaves as expected', () {
      final freq = HabitFrequency.custom({1, 3, 5}); // T2, T4, T6
      expect(freq.type, equals(FrequencyType.customDays));

      final mon = DateTime(2026, 11, 23);
      final tue = DateTime(2026, 11, 24);
      final wed = DateTime(2026, 11, 25);

      expect(freq.isDueOn(mon), isTrue);
      expect(freq.isDueOn(tue), isFalse);
      expect(freq.isDueOn(wed), isTrue);
      expect(freq.displayLabel, equals('T2, T4, T6'));
    });

    test('toJson and fromJson preserves equality', () {
      final original = HabitFrequency.custom({2, 4, 6});
      final json = original.toJson();
      final restored = HabitFrequency.fromJson(json);

      expect(restored, equals(original));
      expect(restored.scheduledDays, equals({2, 4, 6}));
      expect(restored.displayLabel, equals('T3, T5, T7'));
    });
  });
}
