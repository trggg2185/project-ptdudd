import 'health_profile.dart';
import 'schedule_block.dart';

typedef ProfileData = ({HealthProfile profile, List<ScheduleBlock> blocks});

abstract interface class ProfileRepository {
  Future<ProfileData> load();
  Future<void> saveProfile(HealthProfile profile);
  Future<void> saveBlock(ScheduleBlock block);
  Future<void> deleteBlock(String id);
}
