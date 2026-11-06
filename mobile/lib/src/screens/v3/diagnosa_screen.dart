// v3 01 Diagnosa "Kenapa?" (design/mockup-v3/features/01-diagnosa.html, Android):
// one tap from a KPI to the decomposition of its change: contribution per area,
// volume, rate or mix, ranked hypotheses, then map or a follow-up task.
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/api_client.dart';
import '../../ui/mock_icons.dart';
import '../../ui/v2.dart';
import '../../ui/v3.dart';
import 'tindak_screen.dart';
import 'v3_nav.dart';

class DiagnosaScreen extends StatelessWidget {
  const DiagnosaScreen({super.key, this.metric = 'revenue', this.region = '', this.kabupaten = '', this.basis = 'month', this.preview});
  final String metric, region, kabupaten, basis;
  final Map<String, dynamic>? preview;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2.bg,
      body: SafeArea(
        bottom: false,
        child: V3Loader(
          path: '/api/diagnosa',
          query: {'metric': metric, 'region': region, 'kabupaten': kabupaten, 'basis': basis},
          preview: preview,
          builder: (context, d, reload) => _DiagnosaBody(d: d),
        ),
      ),
    );
  }
}

String _short(String? month) => (month ?? '').split(' ').first;

class _DiagnosaBody extends StatelessWidget {
  const _DiagnosaBody({required this.d});
  final Map<String, dynamic> d;

  @override
  Widget build(BuildContext context) {
    final total = Map<String, dynamic>.from(d['total'] as Map? ?? const {});
    final basis = Map<String, dynamic>.from(d['basis'] as Map? ?? const {});
    final scope = Map<String, dynamic>.from(d['scope'] as Map? ?? const {});
    final delta = (total['delta'] as num?)?.toDouble() ?? 0;
    final per = basis['kind'] == 'mtd' ? (basis['label'] ?? '').toString() : '${_short(basis['cur'])} vs ${_short(basis['prev'])}';
    return Column(children: [
      Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: V2.rule))),
        child: Row(children: [
          _sq(context, 'chevl', 'Kembali', () => Navigator.of(context).maybePop(), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(delta < 0 ? 'Kenapa turun?' : 'Kenapa naik?', style: V2.d(16, FontWeight.w700, V2.ink, lh: 1.2)),
              // an inline <small> in a 16 px Prompt line box (24.2 px), like the mockup
              Text('${d['metric_label']} ${scope['name']} · $per',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.2),
                  strutStyle: const StrutStyle(fontFamily: V2.body, fontSize: 16, height: 1.5125, forceStrutHeight: true, leadingDistribution: TextLeadingDistribution.even)),
            ]),
          ),
          _sq(context, 'share', 'Bagikan', () => SharePlus.instance.share(ShareParams(text: _shareText()))),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(14), children: [
          _answer(total),
          const SizedBox(height: 12),
          _basis(basis),
          const SizedBox(height: 12),
          _contrib(),
          const SizedBox(height: 12),
          _effects(),
          for (final h in (d['hypotheses'] as List? ?? const [])) ...[const SizedBox(height: 12), _hyp(Map<String, dynamic>.from(h as Map))],
          const SizedBox(height: 12),
          _actions(context),
        ]),
      ),
    ]);
  }

  String _shareText() {
    final segs = (d['summary'] as List? ?? const []).map((s) => (s as Map)['t']).join();
    return '${d['title']}\n$segs\n(Agent Java, ${(d['basis'] as Map?)?['label'] ?? ''})';
  }

  Widget _sq(BuildContext context, String icon, String label, VoidCallback onTap, {double size = 20, Color color = V2.ink2}) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: V2.rule)),
            child: MIcon(icon, size: size, color: color),
          ),
        ),
      );

  Widget _answer(Map<String, dynamic> total) {
    final detail = (total['detail'] ?? '').toString();
    final cut = detail.indexOf(' · ');
    final a = cut < 0 ? detail : detail.substring(0, cut), b = cut < 0 ? '' : detail.substring(cut + 3);
    return V3CssBg(
        deg: 135,
        colors: const [V2.teal700, V2.teal900, V2.teal900],
        stops: const [0, .72, 1],
        glows: const [V3Glow(.9, 0, 240, 180, Color(0xFF22B8C9), .45)],
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Chrome rounds ascent/descent to whole px: baseline 23.5 vs 12.3, row = 11.2 + 31.2.
          SizedBox(height: 42.4, child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('${total['delta_label']}', style: V2.d(28, FontWeight.w800, const Color(0xFFFFC2AF), lh: 1)),
            const SizedBox(width: 8),
            Flexible(child: V2Lines(TextSpan(text: b.isEmpty ? a : '$a\n$b', style: V2.d(12, FontWeight.w500, V2.teal100, lh: 1.3)), lineHeight: 15.6, dy: 0)),
          ])),
          const SizedBox(height: 8),
          V2Lines(
            v3Rich(d['summary_short'] as List? ?? d['summary'] as List?,
                base: V2.b(13.5, FontWeight.w400, Colors.white, lh: 1.5),
                b: V2.b(13.5, FontWeight.w600, V2.lime, lh: 1.5),
                e: V2.b(13.5, FontWeight.w600, const Color(0xFFFFC2AF), lh: 1.5)),
            lineHeight: 20.25,
            exactPitch: true,
          ),
        ]),
      );
  }

  Widget _basis(Map<String, dynamic> basis) {
    final chips = <String>[
      basis['kind'] == 'mtd' ? (basis['label'] ?? '').toString() : 'Bulan penuh ${_short(basis['cur'])} vs ${_short(basis['prev'])}',
      if ((d['source'] as Map?)?['short'] != null) '${(d['source'] as Map)['short']}',
      if (d['coverage_pct'] != null) 'Cakupan ${V3.num((d['coverage_pct'] as num).toDouble(), 1)}%',
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final c in chips)
        Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: V2.rule)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [Text(c, style: V2.d(11, FontWeight.w500, V2.ink2, lh: 1))]),
        ),
    ]);
  }

  Widget _card(String title, String sub, List<Widget> rows) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: V3.card(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: V2.d(14.5, FontWeight.w600, V2.ink, lh: 1.3)),
          const SizedBox(height: 2),
          Text(sub, style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3)),
          const SizedBox(height: 10),
          ...rows,
        ]),
      );

  /// One ".dv" row: label, negative half, positive half, value.
  Widget _dv(String label, double v, double frac, {bool lo = false, bool tot = false, String? text}) {
    final neg = v < 0;
    return SizedBox(
      // the total row has no bar cells, so it is only as tall as its 12/1.2 text
      height: tot ? 14.4 : 16,
      child: Row(children: [
        SizedBox(
          width: 92,
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(12, tot ? FontWeight.w700 : FontWeight.w500, lo ? V2.mute : V2.ink, lh: 1.2)),
        ),
        Expanded(
          child: tot
              ? const SizedBox()
              : LayoutBuilder(builder: (context, c) => Stack(children: [
                    Positioned(right: 0, top: 0, bottom: 0, width: 1.5, child: const ColoredBox(color: V3.line)),
                    if (neg)
                      Positioned(
                        right: 1.5,
                        top: 1,
                        bottom: 1,
                        width: (c.maxWidth - 1.5) * frac,
                        child: Opacity(
                          opacity: lo ? .5 : 1,
                          child: const DecoratedBox(decoration: BoxDecoration(color: V2.red, borderRadius: BorderRadius.horizontal(left: Radius.circular(4)))),
                        ),
                      ),
                  ])),
        ),
        Expanded(
          child: tot || neg
              ? const SizedBox()
              : LayoutBuilder(builder: (context, c) => Stack(children: [
                    Positioned(
                      left: 0,
                      top: 1,
                      bottom: 1,
                      width: c.maxWidth * frac,
                      child: Opacity(
                        opacity: lo ? .5 : 1,
                        child: const DecoratedBox(decoration: BoxDecoration(color: V3.green2, borderRadius: BorderRadius.horizontal(right: Radius.circular(4)))),
                      ),
                    ),
                  ])),
        ),
        SizedBox(
          width: 46,
          child: Text(text ?? '${V3.sign(v)}${V3.num(v.abs(), 1)}',
              textAlign: TextAlign.right, style: V2.d(12, FontWeight.w700, neg ? V2.red : V3.green, lh: 1)),
        ),
      ]),
    );
  }

  Widget _contrib() {
    final wf = Map<String, dynamic>.from(d['waterfall'] as Map? ?? const {});
    final bars = [for (final b in (wf['bars'] as List? ?? const [])) Map<String, dynamic>.from(b as Map)].where((b) => b['t'] == null).toList();
    if (bars.isEmpty) return const SizedBox();
    final mx = bars.map((b) => ((b['v'] as num?) ?? 0).abs().toDouble()).reduce((a, b) => a > b ? a : b);
    final sum = bars.fold<double>(0, (a, b) => a + ((b['v'] as num?) ?? 0).toDouble());
    final noun = (d['child_level'] ?? 'kabupaten').toString();
    String label(String l) {
      final p = l.split('|');
      if (p.length < 2) return p[0];
      final n = RegExp(r'\d+').firstMatch(p[1])?.group(0);
      return n == null ? p[0] : '${p[0]} ($n)';
    }

    final rows = <Widget>[];
    for (final b in bars) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      final v = ((b['v'] as num?) ?? 0).toDouble();
      rows.add(_dv(label('${b['l']}'), v, mx == 0 ? 0 : (v.abs() / mx * 100).round() / 100, lo: b['dim'] != null));
    }
    rows
      ..add(const SizedBox(height: 8))
      ..add(const SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: V2.rule)))
      ..add(const SizedBox(height: 8))
      ..add(_dv('Total', sum, 0, tot: true));
    return _card('Kontribusi per $noun', '${wf['unit'] ?? 'Rp miliar'}, jumlahnya ${V3.sign(sum)}${V3.num(sum.abs(), 1)}', rows);
  }

  Widget _effects() {
    final e = Map<String, dynamic>.from(d['effects'] as Map? ?? const {});
    final rows = [for (final r in (e['rows'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    if (rows.isEmpty) return const SizedBox();
    final unit = ((d['waterfall'] as Map?)?['unit'] ?? 'Rp miliar').toString();
    final out = <Widget>[];
    for (final r in rows) {
      if (out.isNotEmpty) out.add(const SizedBox(height: 8));
      final short = (r['short'] ?? '').toString();
      final v = double.tryParse(short.replaceAll(V3.minus, '-').replaceAll('.', '').replaceAll(',', '.')) ?? 0;
      final label = (r['label'] ?? '').toString().replaceFirst('Efek ', '');
      out.add(_dv(label[0].toUpperCase() + label.substring(1), v, ((r['width_pct'] as num?) ?? 0) / 100, text: short));
    }
    return _card('Volume, rate, atau mix?', unit, out);
  }

  Widget _hyp(Map<String, dynamic> h) {
    final conf = (h['confidence'] as num?)?.toInt() ?? 0;
    final ev = [for (final e in (h['evidence'] as List? ?? const [])) ((e as Map)['text'] ?? '').toString()].where((t) => t.isNotEmpty).toList();
    return Opacity(
      opacity: conf <= 1 ? .8 : 1,
      child: V3Dashed(
        radius: 16,
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(height: 18, child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFECE5FA), borderRadius: BorderRadius.circular(99)),
              child: Text('HIPOTESIS ${h['n']}', style: V2.d(10, FontWeight.w600, V3.purple, lh: 1, ls: .05)),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text('${h['title']}', style: V2.d(13, FontWeight.w600, V2.ink, lh: 1.3))),
            const SizedBox(width: 6),
            for (var i = 0; i < 3; i++) ...[
              Container(width: 7, height: 14, decoration: BoxDecoration(color: i < conf ? V2.teal600 : const Color(0xFFDCE6E3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 6),
            ],
            Text('${h['confidence_label']}', style: V2.d(11.5, FontWeight.w600, V2.ink2, lh: 1)),
          ])),
          const SizedBox(height: 6),
          V2Lines(TextSpan(text: '${ev.join('. ')}.', style: V2.b(12, FontWeight.w400, V2.ink2, lh: 1.45)), lineHeight: 17.4, dy: 0, exactPitch: true),
        ]),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    Widget btn(String icon, String label, bool pri, VoidCallback onTap) => Expanded(
          child: Semantics(
            button: true,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: pri ? V2.teal600 : Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: pri ? V2.teal600 : V2.rule),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  MIcon(icon, size: 16, color: pri ? Colors.white : V2.teal700),
                  const SizedBox(width: 7),
                  Text(label, style: V2.d(13, FontWeight.w600, pri ? Colors.white : V2.teal700, lh: 1)),
                ]),
              ),
            ),
          ),
        );
    return Row(children: [
      btn('map', 'Lihat di Peta', false, () {
        final s = d['scope'] as Map?;
        // the shell pops back to the tabs, switches to Peta and opens the kabupaten
        final open = V3Nav.openMap;
        if (open == null) return V3Nav.tab(context, 3);
        open((s?['kabupaten'] ?? '').toString(), (d['metric'] ?? 'revenue').toString());
      }),
      const SizedBox(width: 8),
      btn('check', 'Tindak lanjut', true, () async {
        final pre = Map<String, dynamic>.from(d['task_prefill'] as Map? ?? const {});
        try {
          final t = await ApiClient.v3Send('POST', '/api/tindak/tasks', {
            'title': pre['title'] ?? 'Tindak lanjut ${d['title']}',
            'origin': 'diagnosa',
            'region': pre['region'],
            'kabupaten': pre['kabupaten'],
            'impact': pre['impact'],
            'kpi': {'metric': pre['metric'] ?? d['metric'], 'mode': 'change', 'op': '>=', 'threshold': 0,
              'level': pre['kabupaten'] != null ? 'kabupaten' : 'region', 'name': pre['kabupaten'] ?? pre['region']},
          });
          if (context.mounted) V3Nav.push(context, TindakScreen(task: (t['id'] as num?)?.toInt()));
        } catch (e) {
          if (context.mounted) v3Toast(context, 'Tugas gagal dibuat');
        }
      }),
    ]);
  }
}
