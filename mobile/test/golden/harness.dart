// Renders screens at the mockup frame size (390 wide, 2x) so they can be
// compared with design/mockup/export/Android - *.png.
//   flutter test test/golden --update-goldens
// writes test/golden/out/*.png; tool/compare_mockups.py lays them next to
// the mockups.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/theme.dart';
import 'package:bizplan_java_agent/src/ui/ds.dart';

bool _fontsLoaded = false;

Future<void> loadFonts() async {
  if (_fontsLoaded) return;
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final f in manifest) {
    final family = (f as Map)['family'] as String;
    final loader = FontLoader(family);
    for (final a in f['fonts'] as List) {
      loader.addFont(rootBundle.load((a as Map)['asset'] as String));
    }
    await loader.load();
  }
  _fontsLoaded = true;
}

const images = [
  'assets/icon_circle.png',
  'assets/img/kawung.webp',
  'assets/img/ai_orb.webp',
  'assets/img/iso_city.webp',
  'assets/img/empty_alert.webp',
  'assets/img/empty_reports.webp',
  'assets/img/install_1.webp',
  'assets/img/install_2.webp',
  'assets/img/install_3.webp',
  'assets/img/still_temple.jpg',
  'assets/img/still_tower.jpg',
  'assets/img/still_light.jpg',
  'assets/img/scr_dash.webp',
];

/// Pumps [screen] in a 390 × [height] frame with a 36 px status bar and a
/// 20 px gesture bar, like the Android frames in the mockup.
Future<void> shoot(
  WidgetTester tester,
  String name,
  Widget screen, {
  double height = 844,
  bool dark = false,
  bool statusBar = true,
  bool lightStatus = false,
  bool gestureBar = true,
  Future<void> Function(WidgetTester)? before,
}) async {
  await loadFonts();
  tester.view.physicalSize = Size(780, height * 2);
  tester.view.devicePixelRatio = 2;
  tester.view.padding = FakeViewPadding(top: statusBar ? 72 : 0, bottom: gestureBar ? 40 : 0);
  tester.view.viewPadding = FakeViewPadding(top: statusBar ? 72 : 0, bottom: gestureBar ? 40 : 0);
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Builder(builder: (context) {
        final p = Pal.of(context);
        return Stack(children: [
          Positioned.fill(child: screen),
          if (statusBar)
            Positioned(
              left: 0, right: 0, top: 0, height: 36,
              child: Material(type: MaterialType.transparency, child: _StatusBar(color: lightStatus ? Colors.white : p.ink)),
            ),
          if (gestureBar)
            Positioned(left: 0, right: 0, bottom: 0, height: 20, child: _GestureBar(bg: p.surface, fg: p.ink)),
        ]);
      }),
    ),
  ));
  await tester.runAsync(() async {
    final ctx = key.currentContext!;
    for (final a in images) {
      await precacheImage(AssetImage(a), ctx);
    }
  });
  await tester.pump();
  if (before != null) await before(tester);
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
  await expectLater(find.byKey(key), matchesGoldenFile('out/$name.png'));
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Row(children: [
        Text('9:41', style: ts(13, w600, color)),
        const Spacer(),
        Icon(Icons.wifi, size: 16, color: color),
        const SizedBox(width: 6),
        for (final h in [5.0, 8.0, 11.0, 14.0]) ...[
          Container(width: 3, height: h, margin: const EdgeInsets.only(top: 0), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
          const SizedBox(width: 2),
        ],
        const SizedBox(width: 4),
        Container(
          width: 24,
          height: 12,
          padding: const EdgeInsets.fromLTRB(3, 2.5, 4, 2.5),
          decoration: BoxDecoration(border: Border.all(color: color, width: 1.5), borderRadius: BorderRadius.circular(3)),
          child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.5))),
        ),
      ]),
    );
  }
}

class _GestureBar extends StatelessWidget {
  const _GestureBar({required this.bg, required this.fg});
  final Color bg, fg;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: bg,
        child: Center(
          child: Container(width: 108, height: 4, decoration: BoxDecoration(color: fg.withValues(alpha: .3), borderRadius: BorderRadius.circular(2))),
        ),
      );
}
