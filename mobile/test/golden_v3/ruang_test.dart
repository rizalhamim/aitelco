// 04 Ruang Saya on the phone: board chips, freshness row and three pins (daily
// chart, KPI tiles, a pin whose data is not in the dump yet).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/screens/v3/ruang_screen.dart';

import '../golden_v2/harness.dart';
import 'common.dart';

void main() {
  setUp(v3Setup);

  testWidgets('ruang', (t) async {
    final boards = fixture('/api/ruang/boards');
    final b = fixture('/api/ruang/boards/1');
    final pins = {for (final p in b['pins'] as List) (p as Map)['id']: p};
    // the phone mockup shows one column: the daily chart, two KPI tiles and the unavailable pin
    final daily = pins[1] as Map, kpi = pins[5] as Map, na = pins[4] as Map;
    kpi
      ..['col'] = 0
      ..['position'] = 1;
    ((kpi['data'] as Map)['tiles'] as List)
      ..removeRange(2, 4)
      ..[0] = {'label': 'Site < target', 'value': '37', 'delta_label': '▲9', 'good': false}
      ..[1] = {'label': 'Availability', 'value': '99,58%', 'delta_label': '+0,04', 'good': true};
    na
      ..['col'] = 0
      ..['position'] = 2;
    (na['data'] as Map)['detail'] = 'Akan terisi otomatis saat data masuk.';
    b['pins'] = [daily, kpi, na];
    b['members'] = (b['members'] as List).take(3).toList();
    await matchMockup(
      t,
      name: 'v3-ruang',
      mockup: '$m3/04-ruang-saya/Android - Ruang Saya@2x.png',
      screen: RuangScreen(previewBoards: boards, previewBoard: b),
      precache: const ['assets/icon_circle.png'],
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('boards', Rect.fromLTWH(0, 96, frameW, 88)),
        Region('daily', Rect.fromLTWH(0, 184, frameW, 248)),
        Region('kpi', Rect.fromLTWH(0, 432, frameW, 140)),
        Region('na', Rect.fromLTWH(0, 572, frameW, 150)),
        Region('fab', Rect.fromLTWH(0, 722, frameW, 78)),
        Region('nav', Rect.fromLTWH(0, 800, frameW, 80)),
      ],
    );
  });
}
