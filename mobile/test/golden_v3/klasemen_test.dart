// 03 Klasemen: segment and metric chip, basis line, podium, rows 4 to 6, the
// folded middle, my row and the bottom two must match the Android mockup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/screens/v3/klasemen_screen.dart';

import '../golden_v2/harness.dart';
import 'common.dart';

void main() {
  setUp(v3Setup);

  testWidgets('klasemen', (t) async {
    final d = fixture('/api/klasemen');
    (d['source'] as Map)['short'] = 'Dump 5 Nov';
    await matchMockup(
      t,
      name: 'v3-klasemen',
      mockup: '$m3/03-klasemen/Android - Klasemen@2x.png',
      precache: const ['assets/icon_circle.png'],
      screen: KlasemenScreen(preview: d),
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        // "data ilustrasi" in the mockup, the dump date in the app
        Region('top', Rect.fromLTWH(0, 96, frameW, 204), masks: [Rect.fromLTWH(206, 152, 100, 22)]),
        Region('table', Rect.fromLTWH(0, 300, frameW, 400)),
        Region('nav', Rect.fromLTWH(0, 800, frameW, 80)),
      ],
    );
  });
}
