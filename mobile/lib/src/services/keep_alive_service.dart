import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app's process alive while a chat/query is still loading, so that
/// switching to another app (backgrounding) does NOT let Android pause or kill
/// the in-flight SSE stream. Implemented as an Android foreground service with a
/// lightweight "sedang memproses" notification that the user can see.
///
/// Lifecycle: call [start] right when a request begins (busy = true) and [stop]
/// when it finishes/errors. Safe to call repeatedly; no-op on non-Android.
class KeepAliveService {
  static bool _initialized = false;
  static bool _running = false;

  /// One-time channel/options setup. Call once at app startup.
  static void init() {
    if (!_isAndroid || _initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'bizplan_keepalive',
        channelName: 'Pemrosesan Bizplan',
        channelDescription:
            'Menjaga proses analisis tetap berjalan saat aplikasi di latar belakang.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  /// Request the runtime notification permission (Android 13+). Returns true if
  /// granted or not required. Best-effort — never throws.
  static Future<bool> ensurePermission() async {
    if (!_isAndroid) return true;
    try {
      final p = await FlutterForegroundTask.checkNotificationPermission();
      if (p == NotificationPermission.granted) return true;
      final r = await FlutterForegroundTask.requestNotificationPermission();
      return r == NotificationPermission.granted;
    } catch (_) {
      return false;
    }
  }

  /// Start (or update) the foreground service while a request is running.
  static Future<void> start({String text = 'Sedang memproses analisis…'}) async {
    if (!_isAndroid) return;
    if (!_initialized) init();
    try {
      await ensurePermission();
      if (_running) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'Bizplan Java Agent',
          notificationText: text,
        );
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 4869,
        notificationTitle: 'Bizplan Java Agent',
        notificationText: text,
      );
      _running = true;
    } catch (e) {
      debugPrint('KeepAliveService.start failed: $e');
    }
  }

  /// Stop the foreground service when the request finishes.
  static Future<void> stop() async {
    if (!_isAndroid || !_running) return;
    try {
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('KeepAliveService.stop failed: $e');
    } finally {
      _running = false;
    }
  }

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;
}
