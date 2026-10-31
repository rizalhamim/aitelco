import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

import '../config.dart';

/// Result of checking the backend for a newer APK.
class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String notes;
  final bool mandatory;
  final String downloadUrl; // absolute
  final int sizeBytes;

  UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.notes,
    required this.mandatory,
    required this.downloadUrl,
    required this.sizeBytes,
  });
}

class UpdateCheckException implements Exception {
  final String message;
  const UpdateCheckException(this.message);

  @override
  String toString() => message;
}

/// In-app APK updater. Checks the backend's /api/app/version, and if the
/// server build number is higher than this build, downloads the APK and
/// launches the Android package installer.
class UpdateService {
  /// Null means no newer build, never a failed network/version check.
  static Future<UpdateInfo?> check() async {
    if (!Platform.isAndroid) return null;
    final info = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(info.buildNumber);
    if (currentCode == null) {
      throw const UpdateCheckException(
          'Versi aplikasi terpasang tidak terbaca.');
    }
    return checkVersion(currentCode: currentCode);
  }

  static Future<UpdateInfo?> checkVersion({
    required int currentCode,
    http.Client? client,
    Uri? baseUri,
  }) async {
    final base = baseUri ?? Uri.parse(AppConfig.apiBase);
    final transport = client ?? http.Client();
    try {
      final res =
          await transport.get(base.resolve('/api/app/version'), headers: {
        'Accept': 'application/json',
        'Cache-Control': 'no-cache',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw UpdateCheckException(
            'Server pembaruan belum tersedia (HTTP ${res.statusCode}).');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['version_code'] is! num ||
          (decoded['version_code'] as num) <= 0 ||
          (decoded['version_code'] as num).toInt() != decoded['version_code'] ||
          decoded['available'] is! bool) {
        throw const UpdateCheckException(
            'Informasi versi dari server tidak valid.');
      }
      final m = decoded;
      final serverCode = (m['version_code'] as num).toInt();
      if (serverCode <= currentCode) return null;
      if (m['available'] != true) {
        throw const UpdateCheckException(
            'Versi baru terdeteksi, tetapi file pembaruan belum tersedia.');
      }

      final rawUrl = (m['download_url'] as String?) ?? '/api/app/download';
      final url = base.resolve(rawUrl);
      if (!['http', 'https'].contains(url.scheme) || url.host.isEmpty) {
        throw const UpdateCheckException(
            'Alamat unduhan pembaruan tidak valid.');
      }

      return UpdateInfo(
        versionName: (m['version_name'] as String?) ?? '',
        versionCode: serverCode,
        notes: (m['notes'] as String?) ?? '',
        mandatory: m['mandatory'] == true,
        downloadUrl: url.toString(),
        sizeBytes: (m['size_bytes'] as num?)?.toInt() ?? 0,
      );
    } on UpdateCheckException {
      rethrow;
    } on FormatException {
      throw const UpdateCheckException('Respons server pembaruan tidak valid.');
    } on TimeoutException {
      throw const UpdateCheckException(
          'Pengecekan pembaruan terlalu lama. Periksa koneksi dan coba lagi.');
    } catch (e) {
      debugPrint('UpdateService.check failed: $e');
      throw const UpdateCheckException(
          'Tidak dapat memeriksa pembaruan. Periksa koneksi internet dan coba lagi.');
    } finally {
      if (client == null) transport.close();
    }
  }

  /// Downloads the APK, reporting progress 0..1, then launches the installer.
  /// Returns null on success or an error message on failure.
  static Future<String?> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      // Ask for install permission (Android 8+).
      if (await Permission.requestInstallPackages.isDenied) {
        final status = await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          return 'Izin instal aplikasi ditolak. Aktifkan "Install unknown apps" untuk Bizplan Java Agent.';
        }
      }

      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final file =
          File('${dir.path}/Bizplan-Java-Agent-${info.versionCode}.apk');
      if (await file.exists()) {
        await file.delete();
      }

      final client = http.Client();
      final req = http.Request('GET', Uri.parse(info.downloadUrl));
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        client.close();
        return 'Gagal mengunduh (HTTP ${resp.statusCode}).';
      }

      final total = resp.contentLength ?? info.sizeBytes;
      final sink = file.openWrite();
      int received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
      client.close();

      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        return 'Tidak bisa membuka installer: ${result.message}';
      }
      return null;
    } catch (e) {
      debugPrint('UpdateService.downloadAndInstall failed: $e');
      return 'Terjadi kesalahan saat update: $e';
    }
  }
}
