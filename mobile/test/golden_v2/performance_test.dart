// 04 Performance (Performa tab): search, drill-down path, dump label, KPI cards
// with MoM and YoY, the 12-month trend on Okt, contribution per kecamatan and
// the first two sites (the first expanded) must match the Android mockup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/screens/performance_screen.dart';
import 'package:bizplan_java_agent/src/ui/v2.dart';

import 'harness.dart';

const _m = 1e9, _jt = 1e6;
List<double> _x(List<double> v, double k) => [for (final a in v) a * k];

/// Mockup 04 data (Kab. Garut, Oktober 2026), same numbers as
/// frontend/tools/visual/performance-fixture.mjs with the phone's shorter copy.
Map<String, dynamic> mockupPerformance() {
  const named = [
    ['Tarogong Kidul', -420.0], ['Garut Kota', -310.0], ['Karangpawitan', -185.0], ['Cibatu', -120.0], ['Leles', -60.0],
    ['Bayongbong', 45.0], ['Kadungora', 80.0], ['Malangbong', 95.0],
  ];
  // 34 other kecamatan, together −325 jt (with Leles and Bayongbong: 36 others, −340 jt)
  final others = [for (var i = 0; i < 25; i++) ['Kec ${i + 1}', -15.0], for (var i = 0; i < 9; i++) ['Kec ${i + 26}', 50 / 9]];
  final contrib = [
    for (final c in [...named, ...others]) {'name': c[0], 'key': (c[0] as String).toUpperCase(), 'value': 0, 'delta': (c[1] as double) * _jt},
  ]..sort((a, b) => (a['delta'] as double).compareTo(b['delta'] as double));
  const lbl = ['Nov', 'Des', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt'];
  const months = [202511, 202512, 202601, 202602, 202603, 202604, 202605, 202606, 202607, 202608, 202609, 202610];
  Map<String, dynamic> site(String id, String name, String kec, double rev, double rm, double pl, double pm, double av, double avPp, String st, [String note = '']) => {
        'site_id': id, 'site_name': name, 'kecamatan': kec, 'kabupaten': 'Garut', 'revenue': rev * _jt, 'revenue_mom': rm,
        'payload_gb': pl, 'payload_mom': pm, 'availability': av, 'availability_mom_pp': avPp, 'status': st, 'note': note,
      };
  return {
    'level': 'kabupaten', 'child_level': 'kecamatan', 'name': 'Kab. Garut',
    'path': [
      {'level': 'circle', 'name': 'Circle Java', 'value': ''},
      {'level': 'region', 'name': 'West Java', 'value': 'WEST JAVA'},
      {'level': 'kabupaten', 'name': 'Garut', 'value': 'GARUT'},
    ],
    'month_id': 202610, 'month_label': 'Okt 2026', 'prev_label': 'Sep 2026', 'yoy_label': 'Okt 2025',
    'kecamatan_count': 42, 'site_count': 214,
    'kpis': [
      {'key': 'revenue', 'label': 'Revenue', 'value': 38.2 * _m, 'mom_pct': -3.0, 'yoy_pct': 4.1},
      {'key': 'payload', 'label': 'Payload', 'value': 1.62e6, 'mom_pct': -9.1, 'yoy_pct': 5.9},
      {'key': 'subs', 'label': 'Pelanggan', 'value': 812e3, 'mom_pct': -0.37, 'yoy_pct': 2.8},
      {'key': 'availability', 'label': 'Availability', 'value': 99.31, 'mom_pp': -0.22, 'yoy_pp': 0.05, 'target': 99.5},
      {'key': 'sites', 'label': 'Site', 'value': 214, 'kritis': 14, 'waspada': 23, 'normal': 177},
    ],
    'trend': {
      'months': months, 'labels': lbl, 'titles': [for (var i = 0; i < 12; i++) '${lbl[i]} ${months[i] ~/ 100}'],
      'current': {
        'revenue': _x([36.1, 36.8, 36.0, 35.4, 36.6, 37.2, 38.0, 38.9, 39.6, 39.9, 39.4, 38.2], _m),
        'payload': _x([1.58, 1.60, 1.555, 1.54, 1.59, 1.62, 1.66, 1.70, 1.745, 1.78, 1.782, 1.62], 1e6),
        'subs': _x([790, 795, 792, 788, 796, 801, 806, 810, 814, 816, 815, 812], 1e3),
      },
      'previous': {
        'revenue': _x([34.0, 34.6, 34.1, 33.5, 34.4, 35.0, 35.6, 36.2, 36.8, 37.0, 36.9, 36.7], _m),
        'payload': _x([1.30, 1.33, 1.31, 1.29, 1.34, 1.38, 1.41, 1.44, 1.48, 1.50, 1.51, 1.53], 1e6),
        'subs': _x([760, 764, 762, 760, 766, 770, 774, 778, 782, 786, 788, 790], 1e3),
      },
    },
    'contrib': contrib, 'contrib_total': -1200 * _jt,
    'sites': {
      'rows': [
        site('GRT-0412', 'Tarogong Kidul 2', 'Tarogong Kidul', 412, -8.4, 96200, -14.7, 99.10, -0.6, 'kritis',
            'payload turun sejak 26 Okt, bersamaan dengan gangguan 3 jam di sektor 2.'),
        site('GRT-0388', 'Garut Kota Pasar', 'Garut Kota', 386, -6.1, 88400, -12.2, 98.42, -1.3, 'kritis'),
        site('GRT-0217', 'Karangpawitan 1', 'Karangpawitan', 301, -4.0, 70100, -9.6, 99.71, 0.1, 'waspada'),
      ],
      'total': 214, 'page': 1, 'pages': 31, 'size': 7, 'counts': {'kritis': 14, 'waspada': 23, 'normal': 177},
    },
    'source': {'kind': 'dump', 'label': 'Dump Performance 1 Nov 05.00', 'created_at': '2026-10-31T22:00:00Z', 'queries': 0},
  };
}

void main() {
  setUp(() => AuthState.user = {'username': 'rizal', 'full_name': 'Rizal Hamim', 'role': 'admin'});

  testWidgets('performance', (t) async {
    await matchMockup(
      t,
      name: 'performance',
      mockup: 'design/mockup-v2/04-performance/png/Android - Performance@2x.png',
      precache: const ['assets/icon_circle.png'],
      screen: V2Scope(
        alerts: 3,
        openAlerts: ([q]) async {},
        child: Scaffold(
          backgroundColor: V2.bg,
          body: PerformanceScreen(preview: mockupPerformance(), previewOffline: true),
          bottomNavigationBar: V2BottomNav(index: 2, onTap: (_) {}),
        ),
      ),
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('top', Rect.fromLTWH(0, 96, frameW, 156)),
        Region('kpis', Rect.fromLTWH(0, 252, frameW, 270)),
        Region('trend', Rect.fromLTWH(0, 522, frameW, 450)),
        Region('contrib', Rect.fromLTWH(0, 972, frameW, 354)),
        Region('sites', Rect.fromLTWH(0, 1326, frameW, 564)),
        Region('nav', Rect.fromLTWH(0, 1890, frameW, 81)),
      ],
    );
  });
}
