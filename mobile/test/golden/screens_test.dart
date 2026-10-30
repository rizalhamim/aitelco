import 'package:flutter_test/flutter_test.dart';

import 'package:flutter/material.dart';

import 'package:bizplan_java_agent/src/screens/chat_screen.dart';
import 'package:bizplan_java_agent/src/screens/dashboard_screen.dart';
import 'package:bizplan_java_agent/src/screens/download_screen.dart';
import 'package:bizplan_java_agent/src/screens/login_screen.dart';
import 'package:bizplan_java_agent/src/screens/map_screen.dart';
import 'package:bizplan_java_agent/src/screens/report_list_screen.dart';
import 'package:bizplan_java_agent/src/geo/geo_assets.dart';
import 'package:bizplan_java_agent/src/screens/splash_screen.dart';
import 'package:bizplan_java_agent/src/screens/stats_screen.dart';
import 'package:bizplan_java_agent/src/screens/watchlist_screen.dart';

import 'package:bizplan_java_agent/src/ui/nav.dart';

import 'fixtures.dart';
import 'harness.dart';

final _now = DateTime(2026, 10, 30, 8, 30);

Widget dashboard() => tab(1, DashboardScreen(preview: dashboardOverview(), previewNow: _now, previewTouch: 3, alertCount: 3));

Widget tab(int index, Widget body) => Scaffold(
      body: body,
      bottomNavigationBar: AppBottomNav(index: index, alertBadge: 3, onTap: (_) {}),
    );

void main() {
  testWidgets('Splash', (t) => shoot(t, 'Android - Splash', const SplashScreen(autoRoute: false, progress: .58), statusBar: false, gestureBar: false));
  testWidgets('Tanya Agent', (t) => shoot(t, 'Android - Tanya Agent',
      tab(0, ChatScreen(preview: tanyaAgentConversation(), previewTouch: 15))));
  testWidgets('Login', (t) => shoot(t, 'Android - Login', const LoginScreen(), lightStatus: true));
  testWidgets('Dashboard', (t) => shoot(t, 'Android - Dashboard', dashboard(), height: 1660));
  testWidgets('Dashboard (Gelap)', (t) => shoot(t, 'Android - Dashboard (Gelap)', dashboard(), height: 1660, dark: true));
  testWidgets('Watchlist', (t) => shoot(t, 'Android - Watchlist dan Alert',
      tab(2, WatchlistScreen(previewAlerts: watchAlerts(), previewRules: watchRules(), previewNow: _now))));
  testWidgets('Laporan', (t) {
    final adhoc = laporanAdhoc();
    return shoot(t, 'Android - Laporan', Stack(children: [
      tab(3, ReportListScreen(previewOverview: const {'month_label': 'Okt 2026', 'scope': {'regions': []}},
          previewSchedules: laporanSchedules, previewRuns: laporanRuns, previewAdhoc: adhoc, previewNow: _now)),
      const Positioned.fill(child: ColoredBox(color: Color(0x610F1F1D))),
      Positioned(
        left: 0, right: 0, top: 484, height: 460,
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: ReportExportSheet(item: ReportItem(id: 'x', kind: 'adhoc', title: adhoc[0].title, format: 'PDF', adhoc: adhoc[0])),
        ),
      ),
    ]));
  });
  testWidgets('Peta', (t) async {
    await t.runAsync(() => GeoAssets.load('kabupaten'));
    await shoot(t, 'Android - Peta',
        tab(4, MapScreen(previewItems: petaItems(), previewDetail: petaGarut(), previewFocus: 'JAWA BARAT')));
  });
  testWidgets('Statistik', (t) => shoot(t, 'Android - Statistik (admin)', StatsScreen(preview: statsFixture(), previewNow: _now)));
  testWidgets('Unduh APK', (t) => shoot(t, 'Android - Unduh APK',
      DownloadScreen(previewVersion: apkVersion(), previewReleases: apkReleases()), height: 2080));
}
