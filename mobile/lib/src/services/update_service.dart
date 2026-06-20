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

/// In-app APK updater. Checks the backend's /api/app/version, and if the
/// server build number is higher than this build, downloads the APK and
/// launches the Android package installer.
class UpdateService {
  /// Returns an [UpdateInfo] when a newer build is available, else null.
  static Future<UpdateInfo?> check() async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;

      final res = await http
          .get(Uri.parse('${AppConfig.apiBase}/api/app/version'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final m = jsonDecode(res.body) as Map<String, dynamic>;

      final serverCode = (m['version_code'] as num?)?.toInt() ?? 0;
      final available = m['available'] == true;
      if (!available || serverCode <= currentCode) return null;

      final rawUrl = (m['download_url'] as String?) ?? '/api/app/download';
      final url = rawUrl.startsWith('http')
          ? rawUrl
          : '${AppConfig.apiBase}$rawUrl';

      return UpdateInfo(
        versionName: (m['version_name'] as String?) ?? '',
        versionCode: serverCode,
        notes: (m['notes'] as String?) ?? '',
        mandatory: m['mandatory'] == true,
        downloadUrl: url,
        sizeBytes: (m['size_bytes'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('UpdateService.check failed: $e');
      return null;
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
      final file = File('${dir.path}/Bizplan-Java-Agent-${info.versionCode}.apk');
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
