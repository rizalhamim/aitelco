// Illustration data matching the numbers drawn in the mockups.
import 'dart:math' as math;

import 'package:bizplan_java_agent/src/api/models.dart';

List<Map<String, dynamic>> dailyRevenue() {
  // Okt total Rp 412,6 M (−2,4% vs Sep), gross add 286 rb (+3,8%).
  final rows = <Map<String, dynamic>>[];
  for (var d = 1; d <= 31; d++) {
    final okt = 13.31 + 1.3 * math.sin(d * .62 + 2.2) + .35 * math.sin(d * 1.3);
    final sep = 13.64 + 1.0 * math.sin(d * .62 + 2.9) + .3 * math.cos(d * 1.1);
    rows.add({
      'tanggal': '2026-10-${d.toString().padLeft(2, '0')}',
      'revenue': okt * 1e9,
      'revenue_bulan_lalu': sep * 1e9,
      'gross_add': 9226 + 600 * math.sin(d * .7),
      'gross_add_bulan_lalu': 8888 + 500 * math.cos(d * .5),
    });
  }
  // Pin the tooltip day to the mockup values (16 Okt: Rp 13,1 M vs Rp 13,7 M).
  rows[15]['revenue'] = 13.1e9;
  rows[15]['revenue_bulan_lalu'] = 13.7e9;
  // Scale to the exact monthly totals.
  double sum(String k) => rows.fold(0.0, (s, r) => s + (r[k] as double));
  void scale(String k, double total) {
    final f = total / sum(k);
    for (final r in rows) {
      r[k] = (r[k] as double) * f;
    }
  }

  scale('revenue', 412.6e9);
  scale('revenue_bulan_lalu', 412.6e9 / (1 - .024));
  scale('gross_add', 286e3);
  scale('gross_add_bulan_lalu', 286e3 / 1.038);
  return rows;
}

List<ChatMessage> tanyaAgentConversation() {
  final rows = dailyRevenue();
  final a = ChatMessage(
    isUser: false,
    content: 'Revenue Jawa Barat **Rp 412,6 M, turun 2,4%** vs September. Penurunan terbesar di **Garut** (−7,9%) dan **Cianjur** (−6,2%).',
    result: ResultTable(
      ['tanggal', 'revenue', 'revenue_bulan_lalu', 'gross_add', 'gross_add_bulan_lalu'],
      rows,
      rows.length,
      chart: {
        'type': 'line',
        'x': 'tanggal',
        'y': ['revenue', 'revenue_bulan_lalu'],
        'y2': <String>[],
        'series_by': null,
        'label': null,
        'formats': {'revenue': 'currency', 'revenue_bulan_lalu': 'currency'},
        'sort': null,
        'top_n': null,
        'map_key': null,
        'alternatives': <String>[],
        'title': 'Revenue harian Jawa Barat',
      },
    ),
  )
    ..steps = 5
    ..elapsed = const Duration(milliseconds: 8200)
    ..validated = true;
  return [
    ChatMessage(isUser: true, content: 'Performa revenue Jawa Barat bulan ini vs bulan lalu? Kabupaten mana paling turun?'),
    a,
  ];
}
