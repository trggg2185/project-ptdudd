import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_database.dart';

enum PrivacyFailure { offline, unavailable, unexpected }

class PrivacyException implements Exception {
  const PrivacyException(this.failure, this.message);

  final PrivacyFailure failure;
  final String message;
}

class PrivacyService {
  PrivacyService({
    required this.client,
    required this.localDatabase,
    required this.currentOwnerUid,
  });

  final SupabaseClient client;
  final LocalDatabase localDatabase;
  final String? Function() currentOwnerUid;

  Future<String> exportMyData() async {
    final ownerUid = _requireOwner();
    try {
      final result = await client.rpc('export_my_data');
      if (result is! List || result.length != 1) {
        throw const PrivacyException(
          PrivacyFailure.unavailable,
          'Máy chủ không trả dữ liệu xuất theo định dạng mong đợi.',
        );
      }
      final row = result.single;
      if (row is! Map<String, dynamic>) {
        throw const PrivacyException(
          PrivacyFailure.unavailable,
          'Máy chủ không trả dữ liệu xuất hợp lệ.',
        );
      }
      final payload = row['export_my_data'];
      if (payload is! Map) {
        throw const PrivacyException(
          PrivacyFailure.unavailable,
          'Dữ liệu xuất không hợp lệ.',
        );
      }
      final export = <String, Object?>{
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'ownerUid': ownerUid,
        'data': Map<String, Object?>.from(payload),
      };
      return const JsonEncoder.withIndent('  ').convert(export);
    } on PrivacyException {
      rethrow;
    } on SocketException {
      throw const PrivacyException(
        PrivacyFailure.offline,
        'Không thể xuất dữ liệu khi đang offline.',
      );
    } on TimeoutException {
      throw const PrivacyException(
        PrivacyFailure.offline,
        'Không thể xuất dữ liệu khi đang offline.',
      );
    } on PostgrestException catch (error) {
      throw PrivacyException(
        _isNetworkCode(error.code)
            ? PrivacyFailure.offline
            : PrivacyFailure.unavailable,
        'Không thể xuất dữ liệu cloud.',
      );
    }
  }

  Future<void> deleteMyData() async {
    _requireOwner();
    try {
      await client.rpc('delete_my_data');
    } on SocketException {
      throw const PrivacyException(
        PrivacyFailure.offline,
        'Không thể xác nhận xóa dữ liệu cloud khi đang offline.',
      );
    } on TimeoutException {
      throw const PrivacyException(
        PrivacyFailure.offline,
        'Không thể xác nhận xóa dữ liệu cloud khi đang offline.',
      );
    } on PostgrestException catch (error) {
      throw PrivacyException(
        _isNetworkCode(error.code)
            ? PrivacyFailure.offline
            : PrivacyFailure.unavailable,
        'Không thể xác nhận xóa dữ liệu cloud.',
      );
    }

    await localDatabase.clearOwnerData(_requireOwner());
  }

  String _requireOwner() {
    final ownerUid = currentOwnerUid()?.trim();
    if (ownerUid == null || ownerUid.isEmpty) {
      throw const PrivacyException(
        PrivacyFailure.unavailable,
        'Cần đăng nhập để thực hiện tác vụ bảo mật.',
      );
    }
    return ownerUid;
  }

  bool _isNetworkCode(String? code) {
    final normalized = code?.toLowerCase();
    return normalized == 'network-request-failed' ||
        normalized == 'timeout' ||
        normalized == 'socketexception';
  }
}
