// Dashboard entry to the six v3 features. It sits at the end of the Dashboard
// list, so the approved v2 Dashboard above it is unchanged.
import 'package:flutter/material.dart';

import '../../ui/mock_icons.dart';
import '../../ui/v2.dart';
import 'brief_screen.dart';
import 'diagnosa_screen.dart';
import 'klasemen_screen.dart';
import 'ruang_screen.dart';
import 'simulasi_screen.dart';
import 'tindak_screen.dart';
import 'v3_nav.dart';

class V3EntryCard extends StatelessWidget {
  const V3EntryCard({super.key});

  static final _items = <(String, String, String, Color, Widget Function())>[
    ('sun', 'Brief Pagi', 'Ringkasan 06.00', const Color(0xFFE85D3C), () => const BriefScreen()),
    ('spark', 'Diagnosa', 'Kenapa naik atau turun', const Color(0xFF0E8579), () => const DiagnosaScreen()),
    ('bars', 'Klasemen', 'Peringkat wilayah', const Color(0xFF22B8C9), () => const KlasemenScreen()),
    ('layers', 'Ruang Saya', 'Papan pin pribadi', const Color(0xFF5E8A12), () => const RuangScreen()),
    ('check', 'Tindak Lanjut', 'Tugas dan bukti', const Color(0xFF0A6A5F), () => const TindakScreen()),
    ('up', 'Simulasi Target', 'Estimasi akhir bulan', const Color(0xFF6A4CB5), () => const SimulasiScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: V2.rule),
        boxShadow: [cssShadow(const Color(0x0A0F1F1D), 0, 4, 14)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Alat analisa', style: V2.d(15, FontWeight.w600, V2.ink, lh: 1.3)),
        const SizedBox(height: 2),
        Text('Brief, diagnosa, peringkat, papan, tugas dan simulasi', style: V2.b(12, FontWeight.w400, V2.mute, lh: 1.35)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 8) / 2;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final it in _items)
              SizedBox(
                width: w,
                child: Semantics(
                  button: true,
                  label: it.$2,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => V3Nav.push(context, it.$5()),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: it.$4.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
                          child: MIcon(it.$1, size: 17, color: it.$4),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(12.5, FontWeight.w600, V2.ink, lh: 1.25)),
                            Text(it.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.b(10.5, FontWeight.w400, V2.mute, lh: 1.3)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]);
        }),
      ]),
    );
  }
}
