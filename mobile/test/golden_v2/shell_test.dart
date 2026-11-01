// Fondasi: the v2 app bar (logo, title, bell with badge, avatar with lime ring)
// and the five-tab bottom nav must match the Android Dashboard mockup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/ui/v2.dart';

import 'harness.dart';

void main() {
  setUp(() => AuthState.user = {'username': 'rizal', 'full_name': 'Rizal Hamim', 'role': 'admin'});

  testWidgets('shell', (t) async {
    const mock = 'design/mockup-v2/03-dashboard/png/Android - Dashboard@2x.png';
    await matchMockup(
      t,
      name: 'shell',
      mockup: mock,
      precache: const ['assets/icon_circle.png'],
      screen: Builder(builder: (context) {
        final h = MediaQuery.sizeOf(context).height;
        return Scaffold(
          backgroundColor: const Color(0xFFF5F9F8),
          body: Column(children: [
            const SizedBox(height: statusH),
            const V2AppBar(title: 'Dashboard', subtitle: 'Circle Java · Okt 2026', subtitleDot: Color(0xFF2E9E57), alertCount: 3),
            SizedBox(height: h - statusH - 62 - 80),
          ]),
          bottomNavigationBar: V2BottomNav(index: 1, onTap: (_) {}),
        );
      }),
      regions: [
        const Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('nav', Rect.fromLTWH(0, 1701 - 80, frameW, 80)),
      ],
    );
  });
}
