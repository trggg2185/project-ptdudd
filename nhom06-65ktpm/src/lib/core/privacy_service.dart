import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/domain/auth_repository.dart';
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
    this.localDatabase,
    required this.currentOwnerUid,
  });

  final SupabaseClient client;
  final LocalDatabase? localDatabase;
  final String? Function() currentOwnerUid;

  Future<String> exportMyData() async {
    final ownerUid = _requireOwner();
    try {
      final result = await client.rpc('export_my_data');
      Map<String, dynamic>? payload;
      if (result is Map) {
        payload = Map<String, dynamic>.from(result);
      } else if (result is List && result.length == 1) {
        final row = result.single;
        if (row is Map) {
          final nested = row['export_my_data'];
          if (nested is Map) {
            payload = Map<String, dynamic>.from(nested);
          }
        }
      }
      if (payload == null) {
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
    } on HttpException {
      throw const PrivacyException(
        PrivacyFailure.offline,
        'Không thể xuất dữ liệu khi đang offline.',
      );
    } on ClientException {
      throw const PrivacyException(
        PrivacyFailure.offline,
        'Không thể xuất dữ liệu khi đang offline.',
      );
    } on StorageException catch (error) {
      throw PrivacyException(
        _isNetworkCode(error.statusCode)
            ? PrivacyFailure.offline
            : PrivacyFailure.unavailable,
        'Không thể xuất dữ liệu cloud.',
      );
    } on PostgrestException catch (error) {
      throw PrivacyException(
        _isNetworkCode(error.code)
            ? PrivacyFailure.offline
            : PrivacyFailure.unavailable,
        'Không thể xuất dữ liệu cloud.',
      );
    } catch (error) {
      if (error == AuthFailure.network) {
        throw const PrivacyException(
          PrivacyFailure.offline,
          'Không thể xuất dữ liệu khi đang offline.',
        );
      }
      rethrow;
    }
  }

  Future<void> deleteMyData() async {
    final ownerUid = _requireOwner();
    try {
      await _deleteOwnerPhotos(ownerUid);
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
    } on HttpException {
      throw const PrivacyException(
        PrivacyFailure.offline,
        'Không thể xác nhận xóa dữ liệu cloud khi đang offline.',
      );
    } on ClientException {
      throw const PrivacyException(
        PrivacyFailure.offline,
        'Không thể xác nhận xóa dữ liệu cloud khi đang offline.',
      );
    } on StorageException catch (error) {
      throw PrivacyException(
        _isNetworkCode(error.statusCode)
            ? PrivacyFailure.offline
            : PrivacyFailure.unavailable,
        'Không thể xóa ảnh riêng tư trên cloud.',
      );
    } on PostgrestException catch (error) {
      throw PrivacyException(
        _isNetworkCode(error.code)
            ? PrivacyFailure.offline
            : PrivacyFailure.unavailable,
        'Không thể xác nhận xóa dữ liệu cloud.',
      );
    } catch (error) {
      if (error == AuthFailure.network) {
        throw const PrivacyException(
          PrivacyFailure.offline,
          'Không thể xác nhận xóa dữ liệu cloud khi đang offline.',
        );
      }
      rethrow;
    }

    await localDatabase?.clearOwnerData(ownerUid);
  }

  Future<void> _deleteOwnerPhotos(String ownerUid) async {
    final storage = client.storage.from('meal-images');
    var offset = 0;
    while (true) {
      final entries = await storage.list(
        path: ownerUid,
        searchOptions: SearchOptions(limit: 100, offset: offset),
      );
      if (entries.isEmpty) break;

      final paths = <String>[];
      for (final entry in entries) {
        final path = '$ownerUid/${entry.name}';
        if (entry.metadata == null) {
          await _deleteNestedPhotos(storage, path);
        } else {
          paths.add(path);
        }
      }
      if (paths.isNotEmpty) {
        await storage.remove(paths);
      }
      final entryCount = (entries as List).length;
      if (entryCount < 100) break;
      offset += entryCount;
    }
  }

  Future<void> _deleteNestedPhotos(dynamic storage, String folderPath) async {
    var offset = 0;
    while (true) {
      final entries = await storage.list(
        path: folderPath,
        searchOptions: SearchOptions(limit: 100, offset: offset),
      );
      if (entries.isEmpty) break;
      final paths = <String>[];
      for (final entry in entries) {
        final path = '$folderPath/${entry.name}';
        if (entry.metadata == null) {
          await _deleteNestedPhotos(storage, path);
        } else {
          paths.add(path);
        }
      }
      if (paths.isNotEmpty) {
        await storage.remove(paths);
      }
      final entryCount = (entries as List).length;
      if (entryCount < 100) break;
      offset += entryCount;
    }
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
