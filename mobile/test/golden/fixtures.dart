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

/// /api/map/kabupaten?metric=revenue for Jawa Barat, coloured as in the mockup.
List<Map<String, dynamic>> petaItems() => [
      for (final (k, v) in const [
        ('BOGOR', 1.8), ('KOTA BOGOR', 3.4), ('KOTA DEPOK', 1.5), ('BEKASI', 1.6), ('KOTA BEKASI', 1.2), ('KARAWANG', 1.9),
        ('PURWAKARTA', 1.4), ('SUBANG', 2.1), ('INDRAMAYU', 1.7), ('MAJALENGKA', 3.6), ('CIREBON', -1.2), ('KOTA CIREBON', -0.8),
        ('KUNINGAN', -1.1), ('SUMEDANG', 0.6), ('BANDUNG', 0.4), ('BANDUNG BARAT', 0.5), ('KOTA BANDUNG', 1.3), ('KOTA CIMAHI', 0.9),
        ('SUKABUMI', -1.4), ('KOTA SUKABUMI', 3.1), ('CIANJUR', -6.2), ('GARUT', -7.9), ('TASIKMALAYA', -3.4),
        ('KOTA TASIKMALAYA', 0.3), ('CIAMIS', -1.0), ('KOTA BANJAR', 0.2), ('PANGANDARAN', -0.9),
      ])
        {'kabkot_id': '$k|JAWA BARAT', 'kabupaten': k, 'provinsi': 'JAWA BARAT', 'region': 'JAWA BARAT', 'value': v},
    ];

Map<String, dynamic> petaGarut() => {
      'kabupaten': 'GARUT', 'provinsi': 'JAWA BARAT', 'region': 'JAWA BARAT', 'status': 'kritis', 'prev_label': 'Sep 2026',
      'kpis': [
        {'key': 'revenue', 'label': 'Revenue', 'format': 'currency', 'value': 18.4e9, 'pct_change': -7.9},
        {'key': 'payload', 'label': 'Payload', 'format': 'gb', 'value': 2.1e6, 'pct_change': -9.1},
        {'key': 'availability', 'label': 'Availability', 'format': 'percent', 'value': 98.71, 'pct_change': -0.62, 'change_unit': 'pp'},
        {'key': 'gross_add', 'label': 'Gross add', 'format': 'number', 'value': 41200, 'pct_change': -4.2},
      ],
      'explanation': {
        'text': '14 site di selatan Garut turun availability sejak 24 Okt (pemadaman listrik PLN). Penurunan payload '
            'terkonsentrasi di Cikelet, Pameungpeuk dan Cisompet.',
        'actions': ['Pulihkan 9 site dengan availability di bawah 99%'],
      },
      'sites': [
        for (final (la, lo, bad) in const [
          (-7.205, 107.995, true), (-7.17, 108.04, false), (-7.155, 108.045, false), (-7.255, 107.92, true), (-7.245, 107.94, false),
          (-7.275, 108.0, false), (-7.275, 107.73, true), (-7.335, 107.825, false), (-7.365, 107.815, true), (-7.40, 107.80, false),
          (-7.425, 107.795, false), (-7.455, 107.865, true), (-7.475, 107.88, false), (-7.46, 107.92, true), (-7.48, 107.915, true),
          (-7.35, 107.95, false), (-7.31, 107.935, false),
        ])
          {'site_id': 'S$la', 'lat': la, 'lon': lo, 'status': bad ? 'bad' : 'ok'},
      ],
    };

/// GET /api/admin/app-stats?days=30 as drawn.
Map<String, dynamic> statsFixture() => {
      'latest_release': {'version_name': '1.43.1', 'mandatory': true, 'released_at': '2026-10-06'},
      'kpis': {'downloads_period': 1284, 'devices_installed': 962, 'dau': 214, 'failed_logins': 37, 'pct_on_latest': 78.0},
      'trend': {'downloads_period': 12.8, 'devices_installed': 4.1, 'dau': 6.0, 'failed_logins': -9.0},
      'versions': [
        {'version': '1.43.1', 'users': 750}, {'version': '1.42.2', 'users': 80}, {'version': '1.42.0', 'users': 35},
        {'version': '1.41.3', 'users': 58}, {'version': '1.40.1', 'users': 25}, {'version': '1.39.0', 'users': 14},
      ],
      'outdated_users': [for (var i = 0; i < 212; i++) {'id': i}],
      'users': [
        {'full_name': 'Hendra Wijaya', 'department': 'Sales Jateng', 'status': 'tidak_aktif', 'last_seen': '2026-10-09T08:00:00'},
        {'full_name': 'Sri Wahyuni', 'department': 'Finance', 'status': 'tidak_aktif', 'last_seen': '2026-10-14T08:00:00'},
        for (var i = 0; i < 16; i++) {'full_name': 'Pengguna $i', 'department': 'Ops', 'status': 'tidak_aktif', 'last_seen': '2026-10-15T09:00:00'},
      ],
    };

Map<String, dynamic> apkVersion() => {
      'version_name': '1.43.1',
      'version_code': 14301,
      'available': true,
      'mandatory': false,
      'download_url': '/api/app/download',
      'size_bytes': 50541363,
      'released_at': '2026-10-21',
      'min_android': '8.0',
    };

List<Map<String, dynamic>> apkReleases() => [
      {
        'version_name': '1.43.1',
        'released_at': '2026-10-21',
        'latest': true,
        'mandatory': false,
        'notes': ['Grafik bisa di-drill-down dari region ke site', 'Peta kabupaten lebih cepat 2×', 'Perbaikan sinkron alert di Android 14'],
      },
      {'version_name': '1.43.0', 'released_at': '2026-10-06', 'mandatory': true, 'notes': []},
      {'version_name': '1.42.3', 'released_at': '2026-09-18', 'mandatory': false, 'notes': []},
    ];
