// 03 Dashboard: app bar, period switch and region chip, the agent summary
// hero, four KPI cards with sparklines, revenue per region bars with the Okt
// tooltip, active alerts and target achievement must match the Android mockup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/screens/dashboard_screen.dart';
import 'package:bizplan_java_agent/src/ui/v2.dart';

import 'harness.dart';

const _t = 1e12, _m = 1e9, _jt = 1e6, _pb = 1e6;
List<double> _x(List<double> v, double k) => [for (final a in v) a * k];
const _days = ['22 Okt', '23 Okt', '24 Okt', '25 Okt', '26 Okt', '27 Okt', '28 Okt', '29 Okt', '30 Okt', '31 Okt'];

/// Mockup 03 data (Circle Java, Oktober 2026), same numbers as
/// frontend/tools/visual/dashboard-fixture.mjs with the phone's shorter copy.
Map<String, dynamic> mockupOverview() => {
      'month_id': 202610,
      'month_label': 'Okt 2026',
      'month_labels': ['Nov', 'Des', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt'],
      'scope': {'circle': 'JAVA', 'region': null, 'regions': ['EAST JAVA', 'CENTRAL JAVA', 'WEST JAVA']},
      'kpis': [
        {'key': 'revenue', 'label': 'Revenue', 'format': 'currency', 'value': 1.84 * _t, 'pct_change': 1.2,
          'spark_daily': _x([1.71, 1.74, 1.73, 1.77, 1.79, 1.78, 1.81, 1.80, 1.82, 1.84], _t), 'spark_daily_labels': _days},
        {'key': 'subs', 'label': 'Pelanggan aktif', 'format': 'number', 'value': 41.3 * _jt, 'pct_change': 0.6,
          'spark_daily': _x([40.1, 40.3, 40.2, 40.6, 40.7, 40.9, 40.8, 41.0, 41.1, 41.3], _jt), 'spark_daily_labels': _days},
        {'key': 'payload', 'label': 'Payload data', 'format': 'gb', 'value': 84.2 * _pb, 'pct_change': -0.4,
          'spark_daily': _x([85.9, 85.2, 85.6, 84.9, 85.1, 84.6, 84.8, 84.3, 84.5, 84.2], _pb), 'spark_daily_labels': _days},
        {'key': 'availability', 'label': 'Site availability', 'format': 'percent', 'value': 99.62, 'pct_change': 0.12, 'change_unit': 'pp',
          'spark_daily': [99.41, 99.48, 99.45, 99.52, 99.5, 99.55, 99.53, 99.58, 99.6, 99.62], 'spark_daily_labels': _days},
      ],
      'revenue_by_region': {
        'months': [202605, 202606, 202607, 202608, 202609, 202610],
        'labels': ['Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt'],
        'series': [
          {'name': 'EAST JAVA', 'values': _x([742, 751, 760, 770, 772, 788], _m)},
          {'name': 'CENTRAL JAVA', 'values': _x([618, 622, 629, 636, 631, 640], _m)},
          {'name': 'WEST JAVA', 'values': _x([431, 428, 425, 420, 422.7, 412.6], _m)},
        ],
      },
      'regions': [
        {'region': 'EAST JAVA', 'revenue': 788 * _m, 'achievement_pct': 101.4, 'share_pct': 42.8},
        {'region': 'CENTRAL JAVA', 'revenue': 640 * _m, 'achievement_pct': 98.7, 'share_pct': 34.8},
        {'region': 'WEST JAVA', 'revenue': 412.6 * _m, 'achievement_pct': 93.2, 'share_pct': 22.4},
      ],
      'has_targets': true,
      'summary': {
        'text': 'Revenue Circle Java **naik 1,2% MoM**. Perlu perhatian: **payload Garut −9,1%** dan **gross add FWA Semarang**.',
      },
      'source': {'kind': 'dump', 'label': 'Dump Performance 1 Nov 05.00', 'created_at': '2026-10-31T22:10:00Z'},
    };

const mockupAlerts = [
  {'id': 1, 'severity': 'kritis', 'title': 'Payload Garut turun 9,1%', 'message': 'Di bawah ambang 5% selama 3 hari.',
    'created_at': '2026-11-01T05:48:00Z', 'scope_label': 'West Java'},
  {'id': 2, 'severity': 'peringatan', 'title': 'Gross add FWA Semarang', 'message': '78% dari target harian, 5 hari.',
    'created_at': '2026-11-01T05:00:00Z', 'scope_label': 'Central Java'},
  {'id': 3, 'severity': 'peringatan', 'title': 'Market share Cianjur −0,8 pp', 'message': 'Kompetitor agresif di 6 kecamatan selatan.',
    'created_at': '2026-11-01T03:00:00Z', 'scope_label': 'West Java'},
];

void main() {
  setUp(() => AuthState.user = {'username': 'rizal', 'full_name': 'Rizal Hamim', 'role': 'admin'});

  testWidgets('dashboard', (t) async {
    await matchMockup(
      t,
      name: 'dashboard',
      mockup: 'design/mockup-v2/03-dashboard/png/Android - Dashboard@2x.png',
      precache: const ['assets/icon_circle.png'],
      screen: V2Scope(
        alerts: 3,
        openAlerts: ([q]) async {},
        child: Scaffold(
          backgroundColor: V2.bg,
          body: DashboardScreen(
            preview: mockupOverview(),
            previewAlerts: mockupAlerts,
            previewNow: DateTime.utc(2026, 11, 1, 6),
          ),
          bottomNavigationBar: V2BottomNav(index: 1, onTap: (_) {}),
        ),
      ),
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('top', Rect.fromLTWH(0, 96, frameW, 246)),
        Region('kpis', Rect.fromLTWH(0, 342, frameW, 300)),
        Region('chart', Rect.fromLTWH(0, 642, frameW, 440)),
        Region('alerts', Rect.fromLTWH(0, 1082, frameW, 264)),
        Region('targets', Rect.fromLTWH(0, 1346, frameW, 274)),
        Region('nav', Rect.fromLTWH(0, 1620, frameW, 81)),
      ],
    );
  });
}
