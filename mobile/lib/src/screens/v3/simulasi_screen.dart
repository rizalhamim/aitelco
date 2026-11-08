// v3 06 Simulasi Target (design/mockup-v3/features/06-simulasi-target.html, Android):
// month-end estimate with its range, the gap and the daily run-rate needed, and
// levers applied on the phone so the result answers instantly.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/v2.dart';
import '../../ui/v3.dart';
import 'v3_nav.dart';

const _shownLevers = 2;

class SimulasiScreen extends StatefulWidget {
  const SimulasiScreen({super.key, this.metric = 'revenue', this.region = '', this.preview, this.scenario = const {}});
  final String metric, region;
  final Map<String, dynamic>? preview;
  final Map<String, double> scenario;

  @override
  State<SimulasiScreen> createState() => _SimulasiScreenState();
}

class _SimulasiScreenState extends State<SimulasiScreen> {
  late final Map<String, double> _vals = {...widget.scenario};
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    return V3Loader(
      path: '/api/simulasi',
      query: {'metric': widget.metric, 'region': widget.region},
      preview: p,
      builder: (context, d, reload) {
        final month = (d['month_label'] ?? '').toString().split(' ').first;
        return V3Page(
          title: 'Simulasi Target',
          subtitle: '${d['metric_label']} · ${d['scope_label']} · $month',
          body: RefreshIndicator(onRefresh: reload, color: V2.teal600, child: _body(d)),
        );
      },
    );
  }

  double _effect(Map<String, dynamic> l, double v) {
    final e = (l['effect'] as Map?) ?? const {};
    return switch (e['type']) {
      'pct_of' => ((e['base'] as num?) ?? 0) * v / 100,
      'fixed' => v != 0 ? ((e['amount'] as num?) ?? 0).toDouble() : 0,
      'per_unit' => ((e['amount'] as num?) ?? 0) * v,
      _ => 0,
    };
  }

  Widget _body(Map<String, dynamic> d) {
    final idr = d['unit'] == 'IDR';
    String big(double v) => idr ? V3.rp(v) : V3.num(v);
    String eff(double v) => idr ? V3.rpm(v, signed: true) : '${V3.sign(v)}${V3.num(v.abs())}';
    final est = Map<String, dynamic>.from(d['estimate'] as Map? ?? const {});
    final target = (d['target'] as num?)?.toDouble();
    final gap = (d['gap'] as num?)?.toDouble();
    final levers = [for (final l in (d['levers'] as List? ?? const [])) Map<String, dynamic>.from(l as Map)].where((l) => l['kind'] != 'locked').toList();
    double val(Map<String, dynamic> l) => _vals[l['key']] ?? ((l['value'] as num?) ?? 0).toDouble();
    final total = levers.fold<double>(0, (a, l) => a + _effect(l, val(l)));
    final scEst = ((est['mid'] as num?) ?? 0).toDouble() + total;
    final div = idr ? 1e9 : 1.0;
    final basis = (d['basis'] as Map?) ?? const {};
    final kids = <Widget>[
      V3Dashed(
        radius: 20,
        color: const Color(0xFFB9A6E6),
        padding: const EdgeInsets.all(14),
        fill: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Estimasi akhir bulan', style: V2.d(12, FontWeight.w500, V2.ink2, lh: 1)),
            const SizedBox(width: 8),
            _est(hero: true),
          ]),
          const SizedBox(height: 4),
          Text(big(((est['mid'] as num?) ?? 0).toDouble()), style: V2.d(30, FontWeight.w800, V2.ink, lh: 1.15)),
          const SizedBox(height: 4),
          V2Lines(
            TextSpan(
              text: [
                if (est['pct'] != null && target != null) '${V3.num((est['pct'] as num).toDouble(), 1)}% dari target ${big(target)}',
                'rentang ${big(((est['lo'] as num?) ?? 0).toDouble())} sd ${big(((est['hi'] as num?) ?? 0).toDouble())}',
                'data sampai ${basis['data_until'] ?? ''}',
              ].join(' · '),
              style: V2.b(12, FontWeight.w400, V2.mute, lh: 1.4),
            ),
            lineHeight: 16.8,
            dy: 0,
            exactPitch: true,
          ),
        ]),
      ),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: _dk('Gap estimasi', gap == null ? '–' : (idr ? V3.rpm(gap, signed: gap > 0) : '${V3.sign(gap)}${V3.num(gap.abs())}'),
                color: gap == null ? V2.ink : gap < 0 ? V2.red : V3.green),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dk('Per hari: kini vs perlu',
                '${V3.num(((d['per_day'] as num?) ?? 0) / div, 1)} vs ${d['need_per_day'] == null ? '–' : V3.num((d['need_per_day'] as num) / div, 1)}',
                sub: idr ? 'Rp miliar per hari' : 'per hari'),
          ),
        ]),
      ),
      if (d['target_note'] != null)
        Text('${d['target_note']}', style: V2.b(12, FontWeight.w400, const Color(0xFF6B4A0E), lh: 1.45)),
      if (d['path'] != null) _fanCard(d, total, div, idr),
      _scenario(levers, val, eff, total, big, scEst, target),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 14), children: [
      for (var i = 0; i < kids.length; i++) ...[if (i > 0) const SizedBox(height: 10), kids[i]],
    ]);
  }

  // In the hero the mockup's ".dhero span" rule wins over ".est": the pill text is
  // 12 px Prompt in the muted ink, still uppercase and letter-spaced.
  Widget _est({bool light = false, bool hero = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(color: light ? Colors.white.withValues(alpha: .18) : const Color(0xFFECE5FA), borderRadius: BorderRadius.circular(99)),
        child: Text('ESTIMASI',
            style: hero
                ? V2.b(12, FontWeight.w400, V2.mute, lh: 1.4, ls: .06)
                : V2.d(10, FontWeight.w600, light ? Colors.white : V3.purple, lh: 1, ls: .06)),
      );

  Widget _dk(String label, String value, {Color color = V2.ink, String? sub}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: V3.card(radius: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: V2.d(11, FontWeight.w500, V2.mute, lh: 1.25)),
          // inline in the card's 16 px Prompt line box: 18.2 above the baseline, 7 below
          SizedBox(
            height: 25.2,
            child: Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.only(top: .2), child: Text(value, style: V2.d(18, FontWeight.w700, color, lh: 1.3)))),
          ),
          if (sub != null) Text(sub, style: V2.b(11, FontWeight.w400, V2.mute, lh: 1.3)),
        ]),
      );

  Widget _fanCard(Map<String, dynamic> d, double total, double div, bool idr) {
    final p = Map<String, dynamic>.from(d['path'] as Map);
    List<double> l(String k) => [for (final v in (p[k] as List? ?? const [])) (v as num).toDouble() / div];
    final act = l('act'), mid = l('mid'), lo = l('lo'), hi = l('hi');
    final n = math.max(mid.length - 1, 1);
    final alt = total == 0 ? null : [for (var i = 0; i < mid.length; i++) mid[i] + total / div * i / n];
    final all = [0.0, ...act, ...lo, ...hi, ...?alt];
    final mn0 = all.reduce(math.min), mx0 = all.reduce(math.max);
    // same range as the web chart (step = span / 4), labelled at the bottom, half way and zero
    final step = _niceStep((mx0 - mn0) / 4);
    final mn = (mn0 / step).floor() * step;
    var mx = (mx0 / step).ceil() * step;
    if (mx == mx0) mx += step;
    final ticks = mn < 0 ? <double>[mn, mn / 2, 0, if (mx >= -mn / 2) mx] : <double>[0, mx / 2, mx];
    String lab(double v) => '${V3.sign(v.roundToDouble())}${V3.num(v.abs().roundToDouble())}';
    final f = V3FanData(
      days: (p['days'] as num).toInt(),
      today: (p['today'] as num).toInt(),
      min: mn,
      max: mx,
      ticks: ticks,
      act: act,
      mid: mid,
      lo: lo,
      hi: hi,
      alt: alt,
      targetLabel: 'Target',
      midLabel: mid.isEmpty ? '' : lab(mid.last),
      altLabel: alt == null ? '' : lab(alt.last),
      month: (p['month_short'] ?? '').toString(),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: V3.card(radius: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Selisih terhadap jalur target', style: V2.d(14, FontWeight.w600, V2.ink, lh: 1.3)),
        // the subtitle sits after a <br> inside the 14 px heading, so its line box is 18.2
        Text('${idr ? 'Rp miliar' : 'Jumlah'}, kumulatif. Di bawah nol = tertinggal',
            style: V2.b(11, FontWeight.w400, V2.mute, lh: 1.3),
            strutStyle: const StrutStyle(fontFamily: V2.display, fontSize: 14, height: 1.3, forceStrutHeight: true, leadingDistribution: TextLeadingDistribution.even)),
        const SizedBox(height: 10),
        // the svg is 334 wide and runs into the card's right padding, as in the mockup
        SizedBox(
          height: 180,
          child: OverflowBox(alignment: Alignment.topLeft, minWidth: 334, maxWidth: 334, child: V3Fan(f: f, width: 334, height: 180)),
        ),
      ]),
    );
  }

  static double _niceStep(double raw) {
    final p = math.pow(10, (math.log(raw <= 0 ? 1 : raw) / math.ln10).floor()).toDouble();
    for (final k in [1, 2, 5, 10]) {
      if (k * p >= raw) return k * p;
    }
    return 10 * p;
  }

  Widget _scenario(List<Map<String, dynamic>> levers, double Function(Map<String, dynamic>) val, String Function(double) eff, double total,
      String Function(double) big, double scEst, double? target) {
    final shown = _more ? levers : levers.take(_shownLevers).toList();
    final hidden = levers.length - _shownLevers;
    final kids = <Widget>[Text('Coba skenario', style: V2.d(14, FontWeight.w600, V2.ink, lh: 1.3))];
    for (final l in shown) {
      kids.add(_lever(l, val(l), eff(_effect(l, val(l)))));
    }
    kids.add(Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: cssLinear(135, const [Color(0xFF2D1F5E), V3.purple], const Size(314, 72)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hasil skenario · estimasi', style: V2.d(12, FontWeight.w500, const Color(0xFFDCD0F5), lh: 1.2)),
        const SizedBox(height: 6),
        Text('${big(scEst)}${target == null ? '' : ' · ${V3.num(scEst / target * 100, 1)}%'}', style: V2.d(22, FontWeight.w800, Colors.white, lh: 1.15)),
      ]),
    ));
    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: V3.card(radius: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < kids.length; i++) ...[if (i > 0) const SizedBox(height: 10), kids[i]],
      ]),
    );
    if (hidden <= 0) return card;
    // the other levers open below the card, which keeps the card itself as in the mockup
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      card,
      Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _more = !_more),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(_more ? 'Sembunyikan tuas lain' : 'Tuas lain ($hidden) · total dampak ${eff(total)}',
                style: V2.d(12, FontWeight.w600, V2.teal700, lh: 1.3)),
          ),
        ),
      ),
    ]);
  }

  String _valueLabel(Map<String, dynamic> l, double v) {
    if (l['kind'] == 'toggle') return v != 0 ? (l['value_label'] ?? 'Aktif').toString() : 'Tidak';
    if (l['unit'] == '%') return '${v > 0 ? '+' : ''}${V3.num(v, ((l['step'] as num?) ?? 1) < 1 ? 1 : 0)}%';
    return '${V3.num(v)} ${l['unit'] ?? ''}'.trim();
  }

  Widget _lever(Map<String, dynamic> l, double v, String effect) {
    final toggle = l['kind'] == 'toggle';
    final lo = toggle ? 0.0 : ((l['min'] as num?) ?? 0).toDouble(), hi = toggle ? 1.0 : ((l['max'] as num?) ?? 1).toDouble();
    final step = toggle ? 1.0 : ((l['step'] as num?) ?? 1).toDouble();
    final frac = hi == lo ? 0.0 : ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    void set(double x, double w) {
      final raw = lo + (x / w).clamp(0.0, 1.0) * (hi - lo);
      setState(() => _vals[l['key'] as String] = ((raw / step).round() * step * 100).round() / 100);
    }

    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: V2.rule2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${l['label']}', style: V2.d(13, FontWeight.w600, V2.ink, lh: 1.3))),
          Text(_valueLabel(l, v), style: V2.d(14, FontWeight.w700, V3.purple, lh: 1)),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return Semantics(
            slider: true,
            label: '${l['label']}',
            value: _valueLabel(l, v),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (e) => toggle ? setState(() => _vals[l['key'] as String] = v != 0 ? 0 : 1) : set(e.localPosition.dx, w),
              onHorizontalDragUpdate: toggle ? null : (e) => set(e.localPosition.dx, w),
              child: SizedBox(
                height: 24,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(left: 0, right: 0, top: 10, height: 4, child: DecoratedBox(decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(4)))),
                  Positioned(left: 0, width: w * frac, top: 10, height: 4, child: DecoratedBox(decoration: BoxDecoration(color: V3.purple, borderRadius: BorderRadius.circular(4)))),
                  Positioned(
                    left: w * frac - 10,
                    top: 2,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: V3.purple, width: 3),
                        boxShadow: [cssShadow(const Color(0x4D6A4CB5), 0, 2, 6)],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        Row(children: [
          Text('Dampak', style: V2.d(12, FontWeight.w500, V2.ink2, lh: 1.3)),
          const Spacer(),
          Text(effect, style: V2.d(12, FontWeight.w500, V3.green, lh: 1.3).copyWith(fontWeight: FontWeight.w700)),
        ]),
      ]),
    );
  }
}
