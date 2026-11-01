// 08 Profil (Android, opened from the avatar): identity card, installed app,
// grouped settings rows and Keluar must match the mockup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/screens/profile_screen.dart';

import 'harness.dart';

/// Mockup 08 profile, same people and numbers as frontend/tools/visual/profile-fixture.mjs.
Map<String, dynamic> mockupProfile() => {
      'user': {
        'id': 1, 'username': 'rizal', 'full_name': 'Rizal', 'email': 'rizal@bizplan-java.com',
        'department': 'Business Planning', 'role': 'admin', 'default_region': 'JAVA', 'default_region_label': 'Circle Java',
      },
      'stats': {'login_count': 128, 'questions_month': 342, 'month_short': 'Nov'},
      'security': {'password_days': 41},
      'devices': [
        {'id': null, 'kind': 'android', 'name': 'Android · Agent Java', 'sub': 'Samsung SM-A556E · aktif sekarang', 'current': true, 'can_sign_out': false},
        {'id': null, 'kind': 'web', 'name': 'Chrome · Windows', 'sub': 'masuk 2 jam lalu', 'current': false, 'can_sign_out': false},
      ],
      'apk': {'installed_devices': 1},
      'prefs': {
        'theme': 'light', 'animation': true, 'quiet_hours': true, 'default_region': 'JAVA',
        'notify': {'alert_kritis': {'email': true, 'push': true}},
      },
      'options': {'regions': [], 'departments': []},
      'admin': {'active_users_7d': 48, 'accounts': 52, 'inactive': 3, 'pending': 3, 'version_name': '1.50.0'},
    };

void main() {
  setUp(() => AuthState.user = {'username': 'rizal', 'full_name': 'Rizal', 'role': 'admin'});

  testWidgets('profil', (t) async {
    await matchMockup(
      t,
      name: 'profil',
      mockup: 'design/mockup-v2/08-profil/png/Android - Profil@2x.png',
      screen: ProfileScreen(alerts: 3, preview: mockupProfile(), previewInstalled: '1.50.0 (69)'),
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('identity', Rect.fromLTWH(0, 96, frameW, 234)),
        Region('akun', Rect.fromLTWH(0, 330, frameW, 214)),
        Region('pref', Rect.fromLTWH(0, 544, frameW, 347)),
        Region('admin', Rect.fromLTWH(0, 891, frameW, 257)),
        Region('bottom', Rect.fromLTWH(0, 1148, frameW, 92)),
        Region('nav', Rect.fromLTWH(0, 1240, frameW, 81)),
      ],
    );
  });
}
