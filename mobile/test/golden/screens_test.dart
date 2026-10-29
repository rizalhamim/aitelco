import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';

import 'package:bizplan_java_agent/src/screens/chat_screen.dart';
import 'package:bizplan_java_agent/src/screens/login_screen.dart';
import 'package:bizplan_java_agent/src/screens/splash_screen.dart';

import 'package:bizplan_java_agent/src/ui/nav.dart';

import 'fixtures.dart';
import 'harness.dart';

Widget tab(int index, Widget body) => Scaffold(
      body: body,
      bottomNavigationBar: AppBottomNav(index: index, alertBadge: 3, onTap: (_) {}),
    );

void main() {
  testWidgets('Splash', (t) => shoot(t, 'Android - Splash', const SplashScreen(autoRoute: false, progress: .58), statusBar: false, gestureBar: false));
  testWidgets('Tanya Agent', (t) => shoot(t, 'Android - Tanya Agent',
      tab(0, ChatScreen(preview: tanyaAgentConversation(), previewTouch: 15))));
  testWidgets('Login', (t) => shoot(t, 'Android - Login', const LoginScreen(), lightStatus: true));
}
