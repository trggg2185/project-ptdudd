import 'dart:async';

import '../../domain/repositories/fcm_messaging_gateway.dart';

/// Gateway FCM In-Memory phục vụ unit/widget test cho luồng đăng ký token,
/// xoay vòng token (`onTokenRefresh`) và chống trùng Local ↔ FCM (`onForegroundMessage`).
class InMemoryFcmMessagingGateway implements FcmMessagingGateway {
  @override
  final String platformName;

  String? currentToken;
  int deleteTokenCallCount = 0;
  final List<String> deletedTokens = [];
  int _tokenSequence = 1;
  final bool autoGenerateTokenAfterDelete;
  final _tokenRefreshController = StreamController<String>.broadcast();
  final _foregroundMessageController =
      StreamController<IncomingFcmMessage>.broadcast();

  InMemoryFcmMessagingGateway({
    this.currentToken = 'mock-fcm-device-token',
    this.platformName = 'android',
    this.autoGenerateTokenAfterDelete = true,
  });

  @override
  Future<String?> getToken() async => currentToken;

  @override
  Future<void> deleteToken() async {
    deleteTokenCallCount++;
    if (currentToken != null) {
      deletedTokens.add(currentToken!);
    }
    if (autoGenerateTokenAfterDelete) {
      _tokenSequence++;
      currentToken = 'mock-fcm-device-token-$_tokenSequence';
    } else {
      currentToken = null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _tokenRefreshController.stream;

  @override
  Stream<IncomingFcmMessage> get onForegroundMessage =>
      _foregroundMessageController.stream;

  void emitTokenRefresh(String newToken) {
    currentToken = newToken;
    _tokenRefreshController.add(newToken);
  }

  void emitForegroundMessage(IncomingFcmMessage message) {
    _foregroundMessageController.add(message);
  }

  Future<void> dispose() async {
    await _tokenRefreshController.close();
    await _foregroundMessageController.close();
  }
}
