// Redesign v2 visual gate: renders a screen inside the Android frame of the
// approved mockups (design/mockup-v2, 390 wide with a 10 px bezel, so the
// screen is 370 wide at 2x) and compares it with the mockup PNG.
//
//   flutter test test/golden_v2
//
// A device pixel only counts as different when no pixel within 1 px in the
// mockup matches it (max channel delta 24). That tolerates anti-aliasing and
// sub-pixel text placement but still catches wrong colors, missing elements
// and anything shifted by more than 1 px. Small global shifts (dx +-2,
// dy +-3) are searched first, like the web gate in frontend/tools/visual.
// Each region writes test/golden_v2/out/<name>.<region>.png: mockup | app | heat.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const double frameW = 370;
const double bezel = 10;
const double statusH = 34;

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

/// A named part of the screen, in logical px inside the 370 px screen.
class Region {
  const Region(this.name, this.rect, {this.threshold = 2.0});
  final String name;
  final Rect rect;

  /// Maximum share of differing pixels, in percent.
  final double threshold;
}

class _Rgba {
  _Rgba(this.w, this.h, this.px);
  final int w, h;
  final Uint8List px;
}

Future<_Rgba> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final img = (await codec.getNextFrame()).image;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return _Rgba(img.width, img.height, data!.buffer.asUint8List());
}

/// Renders [screen] like the mockup frame and checks each region against
/// [mockup] (a path relative to the repo root).
Future<void> matchMockup(
  WidgetTester tester, {
  required String name,
  required String mockup,
  required Widget screen,
  required List<Region> regions,
  ThemeData? theme,
  List<String> precache = const [],
}) async {
  await loadFonts();
  final mockFile = File('../$mockup');
  final mockBytes = mockFile.readAsBytesSync();
  final mock = (await tester.runAsync(() => _decode(mockBytes)))!;
  // screen height = frame height minus top and bottom bezel
  final screenH = (mock.h / 2) - bezel * 2;

  tester.view.physicalSize = Size(frameW * 2, screenH * 2);
  tester.view.devicePixelRatio = 2;
  tester.view.padding = const FakeViewPadding(top: statusH * 2);
  tester.view.viewPadding = const FakeViewPadding(top: statusH * 2);
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme ?? ThemeData(useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF5F9F8)),
      // the mockup frame clips the screen to a 34 px radius inside the dark bezel
      home: ColoredBox(
        color: const Color(0xFF0B1312),
        child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: Stack(children: [
        Positioned.fill(child: screen),
        const Positioned(left: 0, right: 0, top: 0, height: statusH, child: _StatusBar()),
        Positioned(
          left: (frameW - 118) / 2,
          bottom: 5,
          child: Container(
            width: 118,
            height: 4,
            decoration: BoxDecoration(color: const Color(0xFF0F1F1D).withValues(alpha: .75), borderRadius: BorderRadius.circular(4)),
          ),
        ),
      ]),
      ),
      ),
    ),
  ));
  await tester.runAsync(() async {
    final ctx = key.currentContext!;
    for (final a in precache) {
      await precacheImage(AssetImage(a), ctx);
    }
  });
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();

  final results = <String>[];
  var failed = false;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final shot = await boundary.toImage(pixelRatio: 2);
    final data = await shot.toByteData(format: ui.ImageByteFormat.rawRgba);
    final app = _Rgba(shot.width, shot.height, data!.buffer.asUint8List());
    Directory('test/golden_v2/out').createSync(recursive: true);
    for (final r in regions) {
      final res = await _compare(mock, app, r);
      File('test/golden_v2/out/$name.${r.name}.png').writeAsBytesSync(res.sheet);
      final ok = res.score <= r.threshold;
      if (!ok) failed = true;
      results.add('${ok ? 'pass' : 'FAIL'} ${res.score.toStringAsFixed(2)}% $name.${r.name} (limit ${r.threshold}%)');
    }
  });
  for (final l in results) {
    // ignore: avoid_print
    print(l);
  }
  expect(failed, isFalse, reason: results.join('\n'));
}

class _Result {
  _Result(this.score, this.sheet);
  final double score;
  final Uint8List sheet;
}

Future<_Result> _compare(_Rgba mock, _Rgba app, Region r) async {
  final x0 = (r.rect.left * 2).round(), y0 = (r.rect.top * 2).round();
  final w = (r.rect.width * 2).round(), h = (r.rect.height * 2).round();
  final mx0 = x0 + (bezel * 2).round(), my0 = y0 + (bezel * 2).round();
  // A[x,y] mockup crop, B[x,y] app crop, both w x h
  final a = Uint8List(w * h * 4), b = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final o = (y * w + x) * 4;
      final mi = ((my0 + y) * mock.w + mx0 + x) * 4;
      final ai = ((y0 + y) * app.w + x0 + x) * 4;
      for (var c = 0; c < 4; c++) {
        a[o + c] = (my0 + y < mock.h && mx0 + x < mock.w) ? mock.px[mi + c] : 255;
        b[o + c] = (y0 + y < app.h && x0 + x < app.w) ? app.px[ai + c] : 255;
      }
    }
  }
  bool near(int i, int j) =>
      (a[i] - b[j]).abs() <= 24 && (a[i + 1] - b[j + 1]).abs() <= 24 && (a[i + 2] - b[j + 2]).abs() <= 24;
  final heat = Uint8List(w * h * 4);
  int score(int dx, int dy, bool paint) {
    var bad = 0;
    final st = paint ? 1 : 4;
    for (var y = 2; y < h - 2; y += st) {
      for (var x = 2; x < w - 2; x += st) {
        final j = (y * w + x) * 4;
        var ok = false;
        for (var oy = -1; oy <= 1 && !ok; oy++) {
          for (var ox = -1; ox <= 1 && !ok; ox++) {
            final ny = y + dy + oy, nx = x + dx + ox;
            if (ny < 0 || nx < 0 || ny >= h || nx >= w) continue;
            ok = near((ny * w + nx) * 4, j);
          }
        }
        if (!ok) bad++;
        if (paint) {
          heat[j] = ok ? 255 : 230;
          heat[j + 1] = ok ? 255 : 40;
          heat[j + 2] = ok ? 255 : 40;
          heat[j + 3] = 255;
        }
      }
    }
    return bad;
  }

  var best = (0, 0, 1 << 30);
  for (var dy = -3; dy <= 3; dy++) {
    for (var dx = -2; dx <= 2; dx++) {
      final s = score(dx, dy, false);
      if (s < best.$3) best = (dx, dy, s);
    }
  }
  final bad = score(best.$1, best.$2, true);

  Future<ui.Image> img(Uint8List px) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  final ia = await img(a), ib = await img(b), ih = await img(heat);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Rect.fromLTWH(0, 0, w * 3 + 40.0, h.toDouble()), Paint()..color = Colors.white);
  canvas.drawImage(ia, Offset.zero, Paint());
  canvas.drawImage(ib, Offset(w + 20.0, 0), Paint());
  canvas.drawImage(ih, Offset(w * 2 + 40.0, 0), Paint());
  final sheet = await rec.endRecording().toImage(w * 3 + 40, h);
  final png = await sheet.toByteData(format: ui.ImageByteFormat.png);
  return _Result(100 * bad / (w * h), png!.buffer.asUint8List());
}

/// The mockup status bar: 9:41, camera dot, "5G ▮▮▮ 86%".
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F1F1D), height: 1, letterSpacing: 0);
    return Material(
      color: Colors.white,
      child: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(children: [
              const Text('9:41', style: style),
              const Spacer(),
              const Text('5G', style: style),
              const SizedBox(width: 5.5),
              // the mockup draws three U+25AE glyphs; Poppins has none, so draw the bars
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 2.25),
                Container(width: 5, height: 9.5, margin: const EdgeInsets.only(top: 2.5), color: const Color(0xFF0F1F1D)),
              ],
              const SizedBox(width: 5.5),
              const Text('86%', style: style),
            ]),
          ),
        ),
        Positioned(
          top: 11,
          left: (frameW - 12) / 2,
          child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFF0B1312), shape: BoxShape.circle)),
        ),
      ]),
    );
  }
}
