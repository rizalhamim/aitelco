// 06 Simulasi Target on the phone: estimate hero, gap and per-day cards, the fan
// chart against the target path and the scenario card with two levers set.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/screens/v3/simulasi_screen.dart';

import '../golden_v2/harness.dart';
import 'common.dart';

void main() {
  setUp(v3Setup);

  testWidgets('simulasi', (t) async {
    final d = fixture('/api/simulasi');
    await matchMockup(
      t,
      name: 'v3-simulasi',
      mockup: '$m3/06-simulasi-target/Android - Simulasi Target@2x.png',
      screen: SimulasiScreen(preview: d, scenario: const {'rate': 1.5, 'recover': 1}),
      precache: const ['assets/icon_circle.png'],
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('hero', Rect.fromLTWH(0, 96, frameW, 148)),
        Region('cards', Rect.fromLTWH(0, 244, frameW, 86)),
        Region('fan', Rect.fromLTWH(0, 330, frameW, 260)),
        Region('scenario', Rect.fromLTWH(0, 590, frameW, 326)),
        Region('rest', Rect.fromLTWH(0, 916, frameW, 160)),
        Region('nav', Rect.fromLTWH(0, 1080, frameW, 80)),
      ],
    );
  });
}
