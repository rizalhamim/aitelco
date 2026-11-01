// 06 Laporan (Laporan tab): search, kind filters, the Performance Outlook on a
// featured card, the library rows and the auto-send schedules must match the
// Android mockup (a scrolled long screen).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/screens/report_list_screen.dart';
import 'package:bizplan_java_agent/src/services/report_export.dart';
import 'package:bizplan_java_agent/src/ui/v2.dart';

import 'harness.dart';

Map<String, dynamic> _item(String id, String kind, String title, String meta, [Map<String, dynamic>? doc]) =>
    {'id': id, 'kind': kind, 'title': title, 'meta': meta, if (doc != null) 'doc': doc};

/// Mockup 06 data, same as frontend/tools/visual/report-fixture.mjs.
Map<String, dynamic> mockupLibrary() => {
      'month_id': 202610, 'month_label': 'Oktober 2026', 'month_short': 'Okt 2026',
      'lead': [
        {..._item('doc:outlook:', 'analis', 'Performance Outlook Circle Java', '9 bagian · termasuk Site productivity', {'kind': 'outlook', 'region': ''}), 'pages': 6, 'sections': 9},
        _item('doc:bulanan:WEST JAVA', 'bulanan', 'Performa Bulanan West Java', 'PDF 2 hlm · Okt 2026', {'kind': 'bulanan', 'region': 'WEST JAVA'}),
        _item('doc:profile:GARUT', 'profile', 'Profile Kab. Garut', '24 bagian · revenue, site, FWA, 5G', {'kind': 'profile', 'kabupaten': 'GARUT'}),
        {..._item('perf:GARUT', 'performance', 'Site Performance Kab. Garut', '214 site · dari dump Parquet'), 'kabupaten': 'GARUT'},
      ],
      'rest': [
        _item('doc:bulanan:CENTRAL JAVA', 'bulanan', 'Performa Bulanan Central Java', 'PDF 2 hlm · Okt 2026', {'kind': 'bulanan', 'region': 'CENTRAL JAVA'}),
        _item('doc:bulanan:EAST JAVA', 'bulanan', 'Performa Bulanan East Java', 'PDF 2 hlm · Okt 2026', {'kind': 'bulanan', 'region': 'EAST JAVA'}),
        _item('doc:bulanan:', 'bulanan', 'Performa Bulanan Circle Java', 'PDF 2 hlm · Okt 2026', {'kind': 'bulanan', 'region': ''}),
        _item('doc:profile:KOTA SEMARANG', 'profile', 'Profile Kota Semarang', '24 bagian · revenue, site, FWA, 5G', {'kind': 'profile', 'kabupaten': 'KOTA SEMARANG'}),
        _item('doc:profile:KOTA SURABAYA', 'profile', 'Profile Kota Surabaya', '24 bagian · revenue, site, FWA, 5G', {'kind': 'profile', 'kabupaten': 'KOTA SURABAYA'}),
      ],
    };

List<Map<String, dynamic>> mockupSchedules() {
  List<String> mails(int n) => [for (var i = 0; i < n; i++) 'user${i + 1}@bizplan-java.com'];
  return [
    {'id': 1, 'name': 'Performance Outlook Circle Java', 'region': '', 'frequency': 'bulanan', 'weekday': 0, 'monthday': 2, 'hour': 7, 'recipients': mails(12), 'active': true},
    {'id': 2, 'name': 'Performa Mingguan per region', 'region': '', 'frequency': 'mingguan', 'weekday': 0, 'monthday': 1, 'hour': 7, 'recipients': mails(8), 'active': true},
    {'id': 3, 'name': 'Profile Kab. Garut', 'region': 'WEST JAVA', 'frequency': 'bulanan', 'weekday': 0, 'monthday': 5, 'hour': 7, 'recipients': mails(3), 'active': false},
  ];
}

List<Map<String, dynamic>> mockupRuns() => [
      {'id': 12, 'schedule_id': 2, 'title': 'Performa Mingguan Central Java', 'kind': 'mingguan', 'region': 'CENTRAL JAVA', 'recipients': 8, 'failed': 0, 'status': 'terkirim', 'created_at': '2026-10-26T00:00:00Z'},
      {'id': 9, 'schedule_id': 1, 'title': 'Performance Outlook Circle Java', 'kind': 'bulanan', 'region': '', 'recipients': 12, 'failed': 1, 'status': 'terkirim', 'created_at': '2026-10-02T00:00:00Z'},
    ];

List<AdhocReport> mockupAdhoc() => [
      AdhocReport(
        id: 'p1',
        title: 'Revenue West Java vs bulan lalu',
        columns: const ['bulan', 'revenue'],
        rows: [for (var i = 0; i < 12; i++) {'bulan': 'M$i', 'revenue': 4e11 + i * 1e9}],
        savedAt: DateTime.utc(2026, 10, 31, 9),
      ),
    ];

void main() {
  setUp(() => AuthState.user = {'username': 'rizal', 'full_name': 'Rizal Hamim', 'role': 'admin'});

  testWidgets('laporan', (t) async {
    await matchMockup(
      t,
      name: 'laporan',
      mockup: 'design/mockup-v2/06-laporan/png/Android - Laporan@2x.png',
      precache: const ['assets/icon_circle.png'],
      screen: V2Scope(
        alerts: 3,
        openAlerts: ([q]) async {},
        child: Scaffold(
          backgroundColor: V2.bg,
          body: ReportListScreen(
            previewLibrary: mockupLibrary(),
            previewSchedules: mockupSchedules(),
            previewRuns: mockupRuns(),
            previewAdhoc: mockupAdhoc(),
            previewNow: DateTime.utc(2026, 11, 1, 6),
          ),
          bottomNavigationBar: V2BottomNav(index: 4, onTap: (_) {}),
        ),
      ),
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('top', Rect.fromLTWH(0, 96, frameW, 104)),
        Region('featured', Rect.fromLTWH(0, 200, frameW, 328)),
        Region('list', Rect.fromLTWH(0, 528, frameW, 416)),
        Region('sched', Rect.fromLTWH(0, 944, frameW, 246)),
        Region('nav', Rect.fromLTWH(0, 1190, frameW, 91)),
      ],
    );
  });
}
