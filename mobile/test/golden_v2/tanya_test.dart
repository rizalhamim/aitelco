// 02 Tanya Agent: app bar with history, conversation (question bubble, answer
// card with pills, text, headline KPIs, Grafik tab with the tooltip on 16 Okt),
// follow-up chips and the composer must match the Android mockup.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/api/models.dart';
import 'package:bizplan_java_agent/src/screens/chat_screen.dart';
import 'package:bizplan_java_agent/src/ui/v2.dart';

import 'harness.dart';

double _r2(double v) => (v * 100).round() / 100;

/// Same series as frontend/tools/visual/chat-fixture.mjs (daily revenue, Okt vs Sep 2026).
List<Map<String, dynamic>> revenueRows() {
  final rows = <Map<String, dynamic>>[];
  for (var d = 1; d <= 31; d++) {
    final wk = math.sin(((d + 2) / 7) * 2 * math.pi);
    final okt = _r2(13.3 + 1.1 * wk + 0.35 * math.sin(d * 1.7) - (d > 12 && d < 20 ? 0.9 : 0));
    rows.add({'hari': d, 'bulan': '2026-10', 'revenue': okt * 1e9});
    if (d <= 30) {
      final sep = _r2(14.1 + 1.0 * math.sin(((d + 1) / 7) * 2 * math.pi) + 0.3 * math.cos(d * 1.3));
      rows.add({'hari': d, 'bulan': '2026-09', 'revenue': sep * 1e9});
    }
  }
  return rows;
}

List<ChatMessage> mockupConversation() {
  final rows = revenueRows();
  final answer = ChatMessage(
    isUser: false,
    content: 'Revenue West Java **Rp 412,6 M**, turun 2,4% vs September. Terbesar di **Garut (−7,9%)** dan **Cianjur (−6,2%)**.',
    result: ResultTable(['hari', 'bulan', 'revenue'], rows, rows.length, chart: {
      'type': 'line', 'x': 'hari', 'y': ['revenue'], 'series_by': 'bulan', 'formats': {'revenue': 'currency'},
      'map_key': 'kabupaten', 'title': 'Revenue harian, Okt vs Sep 2026',
    }),
  )
    ..steps = 5
    ..elapsed = const Duration(milliseconds: 8200)
    ..validated = true
    ..kpis = [
      {'column': 'revenue', 'label': 'Revenue', 'value': 412.6e9, 'format': 'currency', 'prev': 422.7e9, 'delta': -2.39, 'delta_unit': '%', 'vs': '2026-09', 'spark': []},
      {'column': 'site_di_bawah_target', 'label': 'Site di bawah target', 'value': 37, 'format': 'number', 'prev': 28, 'delta': 32.1, 'delta_unit': '%', 'vs': '2026-09', 'spark': []},
    ];
  return [
    ChatMessage(isUser: true, content: 'Revenue West Java bulan ini vs bulan lalu? Kabupaten mana paling turun?'),
    answer,
  ];
}

void main() {
  setUp(() => AuthState.user = {'username': 'rizal', 'full_name': 'Rizal Hamim', 'role': 'admin'});

  testWidgets('tanya', (t) async {
    await matchMockup(
      t,
      name: 'tanya',
      mockup: 'design/mockup-v2/02-tanya-agent/png/Android - Tanya Agent@2x.png',
      precache: const ['assets/icon_circle.png'],
      screen: V2Scope(
        alerts: 3,
        openAlerts: ([q]) async {},
        child: Scaffold(
          backgroundColor: V2.bg,
          body: ChatScreen(preview: mockupConversation(), previewTouch: 15, onOpenMap: () {}),
          bottomNavigationBar: V2BottomNav(index: 0, onTap: (_) {}),
        ),
      ),
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('answer', Rect.fromLTWH(0, 96, frameW, 498)),
        Region('dock', Rect.fromLTWH(0, 594, frameW, 150)),
        Region('nav', Rect.fromLTWH(0, 744, frameW, 81)),
      ],
    );
  });
}
