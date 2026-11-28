import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/local_database.dart';
import '../../../../firebase_options.dart';
import '../../domain/services/fcm_background_message_processor.dart';
import '../stores/sqlite_notification_background_state_store.dart';
import 'firebase_messaging_gateway.dart';
import 'flutter_local_notifications_gateway.dart';

/// Điểm vào nền cấp cao nhất cho `FirebaseMessaging.onBackgroundMessage` (background / terminated).
///
/// Chạy trong Dart isolate tách biệt trên Android khi nhận FCM **data-only**:
/// - Khởi tạo Firebase (nếu cần) để đối chiếu UID đang đăng nhập khi store chưa có bản ghi.
/// - Đọc trạng thái tài khoản, giờ yên lặng và sổ chống trùng Local ↔ FCM dùng chung qua SQLite.
/// - Chỉ hiển thị thông báo nội dung trung tính (`NotificationVisibility.private`) qua
///   `FlutterLocalNotificationsGateway` nếu không bị trùng và hợp lệ theo chủ tài khoản.
@pragma('vm:entry-point')
Future<void> healthyLifeFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    // Vẫn cho phép xử lý dựa trên trạng thái cục bộ nếu Firebase chưa sẵn sàng ở isolate nền.
  }

  final incoming = FirebaseMessagingGateway.mapRemoteMessage(message);
  String? firebaseUid;
  try {
    if (Firebase.apps.isNotEmpty) {
      firebaseUid = FirebaseAuth.instance.currentUser?.uid;
    }
  } catch (_) {}

  final localDatabase = LocalDatabase();
  final stateStore = SqliteNotificationBackgroundStateStore(localDatabase);
  final gateway = FlutterLocalNotificationsGateway();
  try {
    final processor = FcmBackgroundMessageProcessor(
      gateway: gateway,
      stateStore: stateStore,
    );
    await processor.process(
      incoming,
      fallbackOwnerUid: firebaseUid,
      isBackgroundIsolate: true,
    );
  } catch (_) {
    // Không để ngoại lệ trong isolate nền làm crash tiến trình nhận tin Android.
  } finally {
    await localDatabase.close();
  }
}

/// Đăng ký `FirebaseMessaging.onBackgroundMessage` an toàn trong `main()` trên Android/iOS.
void registerHealthyLifeFcmBackgroundHandler() {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  try {
    FirebaseMessaging.onBackgroundMessage(healthyLifeFcmBackgroundHandler);
  } catch (_) {
    // Bỏ qua an toàn trong môi trường test không gắn plugin native.
  }
}
