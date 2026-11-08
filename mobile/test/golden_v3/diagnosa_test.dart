// 01 Diagnosa "Kenapa turun?": answer card, basis chips, contribution per
// kabupaten, volume / rate / mix, two hypotheses and the actions must match the
// Android mockup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/screens/v3/diagnosa_screen.dart';

import '../golden_v2/harness.dart';
import 'common.dart';

void main() {
  setUp(v3Setup);

  testWidgets('diagnosa', (t) async {
    final d = fixture('/api/diagnosa');
    (d['source'] as Map)['short'] = 'Dump 1 Nov';
    // the phone shows the short summary and the shorter hypothesis copy of the mockup
    d['summary_short'] = [
      {'t': '79% dari Garut dan Cianjur.', 's': 'b'},
      {'t': ' Penyebab utama jumlah pelanggan aktif turun (−Rp 6,8 M), bukan harga atau jaringan.'},
    ];
    final h = d['hypotheses'] as List;
    (h[0] as Map)
      ..['title'] = 'Pindah ke kompetitor'
      ..['evidence'] = [
        {'kind': 'p', 'text': 'RGU 90D turun 3,8% di 3 kecamatan selatan, payload per RGU tetap'},
        {'kind': 'n', 'text': 'Market share belum tersedia untuk konfirmasi'},
      ];
    await matchMockup(
      t,
      name: 'v3-diagnosa',
      mockup: '$m3/01-diagnosa/Android - Diagnosa Kenapa@2x.png',
      screen: DiagnosaScreen(preview: d),
      // the long Diagnosa frame has no gesture bar
      homeOpacity: 0,
      regions: const [
        Region('top', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('answer', Rect.fromLTWH(0, 96, frameW, 154)),
        // the mockup's "Data ilustrasi" chip
        Region('basis', Rect.fromLTWH(0, 250, frameW, 68), masks: [Rect.fromLTWH(124, 284, 98, 30)]),
        Region('contrib', Rect.fromLTWH(0, 318, frameW, 280)),
        Region('effects', Rect.fromLTWH(0, 598, frameW, 152)),
        Region('hypotheses', Rect.fromLTWH(0, 750, frameW, 210)),
        Region('actions', Rect.fromLTWH(0, 960, frameW, 60)),
      ],
    );
  });
}
