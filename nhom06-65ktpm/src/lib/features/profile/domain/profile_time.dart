import 'package:timezone/data/latest.dart' as time_data;
import 'package:timezone/timezone.dart' as tz;

const defaultProfileZone = 'Asia/Ho_Chi_Minh';

final _locations = (() {
  time_data.initializeTimeZones();
  return tz.timeZoneDatabase.locations;
})();

tz.Location? profileLocation(String? name) =>
    name == 'UTC' ? tz.UTC : _locations[name];

DateTime calendarDate(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

String calendarDateKey(DateTime date) =>
    calendarDate(date).toIso8601String().split('T').first;

String clockLabel(int minute) {
  final hour = (minute ~/ 60).toString().padLeft(2, '0');
  final minutes = (minute % 60).toString().padLeft(2, '0');
  return '$hour:$minutes';
}

bool validClockMinute(int minute) => minute >= 0 && minute < 1440;
