// 01 Login, Android frame: poster (video off in tests), brand, tagline, card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/screens/login_screen.dart';

import 'harness.dart';

void main() {
  testWidgets('login', (t) async {
    await matchMockup(
      t,
      name: 'login',
      mockup: 'design/mockup-v2/01-login/png/Android - Login@2x.png',
      screen: const LoginScreen(playVideo: false),
      precache: const ['assets/img/login_poster.jpg', 'assets/icon_circle.png'],
      statusHeight: 36,
      statusLight: true,
      homeBottom: 26,
      homeWidth: 120,
      homeOpacity: .8,
      regions: const [
        Region('top', Rect.fromLTWH(0, 0, frameW, 380)),
        Region('card', Rect.fromLTWH(0, 380, frameW, 444)),
      ],
    );
  });
}
