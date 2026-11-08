// 05 Tindak Lanjut on the phone: "Milik saya" grouped by due date, with the
// Garut task expanded (criterion, progress, checklist, photos, nearest site).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/screens/v3/tindak_screen.dart';

import '../golden_v2/harness.dart';
import 'common.dart';

void main() {
  setUp(v3Setup);

  testWidgets('tindak', (t) async {
    final d = fixture('/api/tindak/tasks');
    final garut = ((d['lanes'] as Map)['dikerjakan'] as List).firstWhere((c) => (c as Map)['id'] == 3) as Map;
    // the phone copy of the mockup
    garut
      ..['criterion'] = 'Selesai jika payload Garut kembali ≥ −3%'
      ..['photos'] = 2;
    await matchMockup(
      t,
      name: 'v3-tindak',
      mockup: '$m3/05-tindak-lanjut/Android - Tindak Lanjut@2x.png',
      screen: TindakScreen(preview: d, previewNearest: 'Kamu 1,2 km dari CKJ-021, site berikutnya'),
      precache: const ['assets/icon_circle.png'],
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('segs', Rect.fromLTWH(0, 96, frameW, 80)),
        Region('selected', Rect.fromLTWH(0, 176, frameW, 240)),
        Region('cards', Rect.fromLTWH(0, 416, frameW, 260)),
        Region('nav', Rect.fromLTWH(0, 800, frameW, 80)),
      ],
    );
  });
}
