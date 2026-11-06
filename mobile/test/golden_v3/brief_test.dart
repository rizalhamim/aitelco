// 02 Brief Pagi on the phone: story 1 of 3 (page 2 of 5) with the peeks of the
// next stories and the audio mini player must match the Android mockup.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/screens/v3/brief_screen.dart';

import '../golden_v2/harness.dart';
import 'common.dart';

void main() {
  setUp(v3Setup);

  testWidgets('brief', (t) async {
    final d = fixture('/api/brief');
    // the phone card carries the shorter story copy of the mockup
    ((d['stories'] as List)[0] as Map)['text'] =
        '14 site di 3 kecamatan selatan menyumbang 71% penurunan. Availability normal, kemungkinan bukan gangguan jaringan.';
    await matchMockup(
      t,
      name: 'v3-brief',
      mockup: '$m3/02-brief-pagi/Android - Brief Pagi@2x.png',
      screen: BriefScreen(preview: d, initialPage: 1, previewSeg: .55, previewAudio: 22),
      homeColor: Colors.white,
      precache: const ['assets/icon_circle.png'],
      regions: const [
        Region('head', Rect.fromLTWH(0, 0, frameW, 106)),
        Region('card', Rect.fromLTWH(0, 106, frameW, 404)),
        Region('peeks', Rect.fromLTWH(0, 510, frameW, 170)),
        Region('player', Rect.fromLTWH(0, 680, frameW, 144)),
      ],
    );
  });
}
