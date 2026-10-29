// Illustration data matching the numbers drawn in the mockups.
import 'dart:math' as math;

import 'package:bizplan_java_agent/src/api/models.dart';
import 'package:bizplan_java_agent/src/services/report_export.dart';

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

/// Wavy sparkline: [n] points around [base] with a drift of [trend] per point.
List<double> _spark(double base, double amp, double trend, {int n = 14, double phase = 0}) => [
      for (var i = 0; i < n; i++) base + trend * i + amp * math.sin(i * 1.15 + phase) + amp * .45 * math.sin(i * 2.7 + phase),
    ];

/// GET /api/dashboard/overview as the mockup shows it (Okt 2026, all of Java).
Map<String, dynamic> dashboardOverview() => {
      'month_label': 'Okt 2026',
      'prev_label': 'Sep 2026',
      'scope': {'regions': ['JAWA TIMUR', 'JAWA BARAT', 'JATENG DIY', 'JABODETABEK']},
      'kpis': [
        {'key': 'revenue', 'label': 'Revenue', 'format': 'currency', 'value': 1.84e12, 'prev': 1.82e12, 'pct_change': 1.2,
            'note_prev_label': 'Sep', 'spark': _spark(10, 1.2, .35)},
        {'key': 'subs', 'label': 'Pelanggan', 'format': 'number', 'value': 41.3e6, 'prev': 41.054e6, 'pct_change': .6,
            'note_prev_label': 'Sep', 'spark': _spark(10, 1.2, .3, phase: .4)},
        {'key': 'payload', 'label': 'Payload', 'format': 'gb', 'value': 84.2e6, 'prev': 84.54e6, 'pct_change': -.4,
            'note_prev_label': 'Sep', 'spark': _spark(10, 1.2, -.4, phase: 1.1)},
        {'key': 'availability', 'label': 'Availability', 'format': 'percent', 'value': 99.62, 'prev': 99.52, 'pct_change': .1,
            'change_unit': 'pp', 'target': 99.5, 'note_prev_label': 'Sep', 'spark': _spark(10, 1.2, .3, phase: .2)},
      ],
      'revenue_by_region': {
        'labels': ['Mei', 'Jul', 'Sep', 'Okt'],
        'months': ['202605', '202607', '202609', '202610'],
        'series': [
          {'name': 'JAWA TIMUR', 'values': [733e9, 752e9, 772e9, 788e9]},
          {'name': 'JAWA BARAT', 'values': [431e9, 405e9, 398e9, 413e9]},
          {'name': 'JATENG DIY', 'values': [512e9, 498e9, 534e9, 639e9]},
        ],
      },
      'summary': {
        'text': 'Revenue **naik 1,2%** MoM ditopang Jawa Timur. Perhatian: **payload Garut −9,1%** dan gross add FWA Semarang di bawah target.',
        'attention': 2,
      },
    };

/// GET /api/watchlist/alerts?status=all as drawn in the mockup (now = 30 Okt 08.30).
List<Map<String, dynamic>> watchAlerts() => [
      {'id': 1, 'severity': 'kritis', 'title': 'Payload Garut turun 9,1%', 'message': 'Di bawah ambang 5% selama 3 hari. 14 site terdampak.',
          'created_at': '2026-10-30T08:18:00', 'resolved': false, 'acknowledged': false, 'scope_label': 'Jawa Barat', 'metric_label': 'Payload'},
      {'id': 2, 'severity': 'peringatan', 'title': 'Gross add FWA Semarang di bawah target', 'message': 'Realisasi 78% dari target harian.',
          'created_at': '2026-10-30T07:30:00', 'resolved': false, 'acknowledged': false, 'scope_label': 'Jawa Tengah'},
      {'id': 3, 'severity': 'peringatan', 'title': 'Market share Cianjur −0,8 pp', 'message': 'Kompetitor agresif di 6 kecamatan selatan.',
          'created_at': '2026-10-29T21:10:00', 'resolved': false, 'acknowledged': true, 'scope_label': 'Jawa Barat'},
      {'id': 4, 'severity': 'pulih', 'title': 'Pulih: Availability Bekasi pulih', 'message': 'Kembali 99,7% setelah 6 jam.',
          'created_at': '2026-10-29T16:02:00', 'resolved': true, 'acknowledged': true, 'scope_label': 'Jawa Barat'},
    ];

List<Map<String, dynamic>> watchRules() => [
      for (var i = 0; i < 8; i++) {'id': i + 1, 'metric': 'revenue', 'metric_label': 'Revenue', 'scope_label': 'Jawa', 'status': 'normal'},
    ];

/// Laporan as drawn: one weekly schedule, two emailed runs and two ad-hoc answers.
final laporanSchedules = [
  {'id': 1, 'name': 'Performa Bulanan Region Jawa', 'frequency': 'mingguan', 'weekday': 0, 'hour': 8, 'active': true,
      'last_sent_on': '2026-10-28', 'region': '', 'recipients': ['rizal@ioh.co.id'], 'description': 'tiap Senin 08.00 WIB'},
];
final laporanRuns = [
  {'id': 7, 'title': 'Site availability mingguan', 'kind': 'mingguan', 'region': '', 'recipients': 3, 'status': 'terkirim',
      'created_at': '2026-10-27T01:00:00Z'},
  {'id': 5, 'title': 'Top 20 kabupaten payload', 'kind': 'mingguan', 'region': '', 'recipients': 3, 'status': 'terkirim',
      'created_at': '2026-10-21T01:00:00Z'},
];
List<AdhocReport> laporanAdhoc() => [
      AdhocReport(id: 'a', title: 'Revenue Jawa Barat vs Sep', columns: const ['kabupaten', 'revenue'],
          rows: [for (var i = 0; i < 100; i++) {'kabupaten': 'K$i', 'revenue': i * 1e9}], savedAt: DateTime(2026, 10, 30, 7, 50)),
      AdhocReport(id: 'b', title: 'Market share FWA Jateng', columns: const ['kecamatan', 'share'], rows: const [],
          savedAt: DateTime(2026, 10, 24, 15), format: 'PDF'),
    ];
