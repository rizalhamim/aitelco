// Brief Pagi and Tindak Lanjut on the lock screen without FCM: WorkManager runs
// a background check about every 15 minutes, asks /api/notify/pending for new
// push notifications and shows them with flutter_local_notifications. A tap
// opens the matching v3 screen (link "/brief", "/tindak?task=3", "/ruang?board=1").
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../screens/v3/brief_screen.dart';
import '../screens/v3/ruang_screen.dart';
import '../screens/v3/tindak_screen.dart';

const _task = 'agent-java-notify';
const _lastKey = 'v3_notify_last_id';
final _plugin = FlutterLocalNotificationsPlugin();
const _details = NotificationDetails(
  android: AndroidNotificationDetails('agent_java', 'Agent Java',
      channelDescription: 'Brief Pagi, tindak lanjut dan papan Ruang Saya', importance: Importance.high, priority: Priority.high),
);

@pragma('vm:entry-point')
void v3NotifyDispatcher() {
  Workmanager().executeTask((task, input) async {
    DartPluginRegistrant.ensureInitialized();
    try {
      await AuthState.load();
      if (AuthState.accessToken == null) return true;
      await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await V3Notify.check();
    } catch (_) {/* best-effort: the next run tries again */}
    return true;
  });
}

class V3Notify {
  V3Notify._();
  static GlobalKey<NavigatorState>? _nav;

  /// Called from main() once; [nav] opens the screen behind a tapped notification.
  static Future<void> init(GlobalKey<NavigatorState> nav) async {
    _nav = nav;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) => open(r.payload),
      );
      await Workmanager().initialize(v3NotifyDispatcher);
      await Workmanager().registerPeriodicTask(_task, _task,
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) _pending = launch!.notificationResponse?.payload;
    } catch (_) {/* notifications are optional; the app works without them */}
  }

  static String? _pending;

  /// Asks for the Android 13+ notification permission (after login).
  static Future<void> requestPermission() async {
    try {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Opens the screen a cold-start notification pointed to, once the shell is up.
  static void openPending() {
    final p = _pending;
    _pending = null;
    if (p != null) open(p);
  }

  static Future<void> check() async {
    final prefs = await SharedPreferences.getInstance();
    final after = prefs.getInt(_lastKey);
    // A plain GET with the stored access token: the background isolate never refreshes
    // tokens, because a rotated refresh token would log out the running app. On 401 it
    // simply waits for the app to refresh the session.
    final token = AuthState.accessToken;
    if (token == null) return;
    final res = await http
        .get(Uri.parse('${AppConfig.apiBase}/api/notify/pending').replace(queryParameters: {'after': '${after ?? 0}'}),
            headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return;
    final d = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final last = (d['last_id'] as num?)?.toInt() ?? 0;
    // first run: start from now instead of replaying every unread notification
    if (after != null) {
      for (final n in (d['items'] as List? ?? const [])) {
        final m = n as Map;
        await _plugin.show(id: (m['id'] as num).toInt(), title: '${m['title'] ?? 'Agent Java'}', body: '${m['message'] ?? ''}', notificationDetails: _details, payload: m['link']?.toString());
      }
    }
    await prefs.setInt(_lastKey, last);
  }

  static void open(String? link) {
    final nav = _nav?.currentState;
    if (link == null || nav == null) return;
    final u = Uri.parse(link);
    final Widget? screen = switch (u.path) {
      '/brief' => const BriefScreen(),
      '/tindak' => TindakScreen(task: int.tryParse(u.queryParameters['task'] ?? '')),
      '/ruang' => const RuangScreen(),
      _ => null,
    };
    if (screen != null) nav.push(MaterialPageRoute(builder: (_) => screen));
  }
}
