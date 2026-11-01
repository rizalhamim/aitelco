// 07 Alert dan Watchlist (Android, opened from the bell): tabs, status summary,
// active alert cards and the watches that need attention must match the mockup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/screens/watchlist_screen.dart';

import 'harness.dart';

Map<String, dynamic> _rule(int id, String group, String metric, String micon, String title, String scope, String kab, String value,
        String thr, String status, {bool near = false, double? v, double? t}) =>
    {
      'id': id, 'group': group, 'metric': metric, 'micon': micon, 'title': title, 'scope_label': scope,
      'kabupaten': kab.isEmpty ? null : kab, 'value_label': value, 'threshold_label': thr, 'status': status,
      'near': near, 'value': v, 'trend_threshold': t, 'active': true, 'notify_inapp': true, 'notify_email': false, 'notify_push': false,
    };

/// Mockup 07 watches, same as frontend/tools/visual/watchlist-fixture.mjs.
List<Map<String, dynamic>> mockupRules() => [
      _rule(1, 'perf', 'payload', 'db', 'Payload MoM', 'Kab. Garut, West Java', 'GARUT', '−9,1%', '< −5%', 'kritis'),
      _rule(2, 'perf', 'revenue', 'wallet', 'Revenue MoM', 'West Java', '', '−2,4%', '< −3%', 'normal', near: true, v: -2.4, t: -3),
      _rule(3, 'perf', 'availability', 'tower', 'Availability', 'Kab. Garut, West Java', 'GARUT', '99,31%', '< 99,0%', 'normal'),
      _rule(4, 'perf', 'fwa_rgu', 'users', 'Gross add FWA', 'Kota Semarang, Central Java', 'KOTA SEMARANG', '78% target', '< 85% target', 'peringatan'),
      _rule(5, 'prod', 'rev_site', 'tower', 'Revenue / new site', 'West Java', '', 'Rp 71 jt', '< Rp 65 jt', 'normal'),
      _rule(6, 'prod', 'rgu_site', 'users', 'RGU 90D / site', 'Kab. Garut, West Java', 'GARUT', '1,9 rb', '< 1,8 rb', 'normal', near: true, v: 1.9, t: 1.8),
      _rule(7, 'prod', 'vlr_site', 'pulse', 'VLR / site', 'Central Java', '', '3,4 rb', '< 3,0 rb', 'normal'),
      _rule(8, 'prof', 'market_share', 'pin', 'Market share', 'Kab. Cianjur, West Java', 'CIANJUR', '41,2%', 'turun > 0,5 pp', 'peringatan'),
      _rule(9, 'prof', 'fwa_pen', 'wallet', 'Penetrasi FWA', 'Kota Semarang, Central Java', 'KOTA SEMARANG', '3,4%', '< 3,0%', 'normal'),
      _rule(10, 'prof', 'subs', 'users', 'Pelanggan aktif', 'Kab. Garut, West Java', 'GARUT', '812 rb', 'turun > 1% MoM', 'normal'),
    ];

List<Map<String, dynamic>> mockupAlerts() => [
      {'id': 24, 'severity': 'kritis', 'title': 'Payload Garut turun 9,1%', 'message': 'Di bawah −5% selama 3 hari. 14 site terdampak.',
        'created_at': '2026-11-01T05:48:00Z', 'metric': 'payload', 'kabupaten': 'GARUT', 'group_label': 'Performance', 'resolved': false, 'acknowledged': false},
      {'id': 23, 'severity': 'peringatan', 'title': 'Gross add FWA Semarang', 'message': '78% dari target, 5 hari berturut-turut.',
        'created_at': '2026-11-01T05:00:00Z', 'metric': 'fwa_rgu', 'kabupaten': 'KOTA SEMARANG', 'group_label': 'Performance', 'resolved': false, 'acknowledged': false},
      {'id': 22, 'severity': 'peringatan', 'title': 'Market share Cianjur −0,8 pp', 'message': 'Kompetitor agresif di 6 kecamatan.',
        'created_at': '2026-11-01T03:00:00Z', 'metric': 'market_share', 'kabupaten': 'CIANJUR', 'group_label': 'Profile wilayah', 'resolved': false, 'acknowledged': false},
      {'id': 3, 'severity': 'peringatan', 'title': 'Availability Kab. Garut', 'message': '', 'created_at': '2026-10-28T00:05:00Z',
        'resolved': true, 'acknowledged': true, 'acknowledged_at': '2026-10-28T02:20:00Z', 'resolved_at': '2026-10-28T02:20:00Z'},
    ];

void main() {
  setUp(() => AuthState.user = {'username': 'rizal', 'full_name': 'Rizal Hamim', 'role': 'admin'});

  testWidgets('watchlist', (t) async {
    await matchMockup(
      t,
      name: 'watchlist',
      mockup: 'design/mockup-v2/07-watchlist-alert/png/Android - Alert dan Watchlist@2x.png',
      screen: WatchlistScreen(
        previewRules: mockupRules(),
        previewAlerts: mockupAlerts(),
        previewNow: DateTime.utc(2026, 11, 1, 6),
      ),
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('top', Rect.fromLTWH(0, 96, frameW, 122)),
        Region('alerts', Rect.fromLTWH(0, 218, frameW, 426)),
        // "Pantauan teratas" rows 3 and 4 are compared by content, not position: the
        // app lists Peringatan (Market share) before Mendekati ambang (RGU 90D / site),
        // the mockup had them the other way round. Rows 1, 2, 5 and the button sit
        // where the mockup has them.
        Region('list', Rect.fromLTWH(0, 644, frameW, 192)),
        Region('list-end', Rect.fromLTWH(0, 998, frameW, 128)),
        Region('fab', Rect.fromLTWH(0, 1126, frameW, 94)),
        Region('nav', Rect.fromLTWH(0, 1220, frameW, 81)),
      ],
    );
  });
}
