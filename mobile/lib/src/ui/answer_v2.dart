// Tanya Agent v2 answer pieces for Android, ported from the approved mockup
// (design/mockup-v2/02-tanya-agent) and the web components
// (frontend/src/app/components/v2/Answer.tsx, AnswerChart.tsx): headline KPI
// cards, the Grafik / Tabel / Peta card, and the interactive line chart with
// a dashed hover rule, ringed points, dark tooltip and legend chips.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chart.dart' show ChartSpec, formatValue, humanize, idNum, monthsId, timeLabel, toNum;
import 'mock_icons.dart';
import 'v2.dart';

const v2SeriesColors = [V2.teal600, V2.lagoon, Color(0xFFFF7A59), Color(0xFF6A4CB5), Color(0xFFB7791F), Color(0xFFC23A5B)];
const _green = Color(0xFF1F7A3A);
const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
final _lowerIsBetter = RegExp(r'bawah|below|under|gagal|fail|churn|drop|down|outage|keluhan|complaint|cost|biaya', caseSensitive: false);
const _unitSuffix = {'pb': 'PB', 'tb': 'TB', 'gb': 'GB', 'mb': 'MB'};

// ── Headline KPIs (backend/app/headline_kpis.py) ─────────────────────────────

class HeadlineKpi {
  HeadlineKpi({required this.column, required this.value, this.format = 'number', this.prev, this.delta, this.deltaUnit = '%', this.vs, this.spark = const []});
  final String column;
  final double value;
  final String format;
  final double? prev, delta;
  final String deltaUnit;
  final String? vs;
  final List<double> spark;

  static HeadlineKpi? fromJson(dynamic j) {
    if (j is! Map) return null;
    final v = toNum(j['value']);
    if (v == null) return null;
    return HeadlineKpi(
      column: (j['column'] ?? '').toString(),
      value: v,
      format: (j['format'] ?? 'number').toString(),
      prev: toNum(j['prev']),
      delta: toNum(j['delta']),
      deltaUnit: (j['delta_unit'] ?? '%').toString(),
      vs: j['vs']?.toString(),
      spark: (j['spark'] as List? ?? const []).map(toNum).whereType<double>().toList(),
    );
  }

  bool get _int => value == value.roundToDouble();

  /// "Site di bawah target"; [compact] shortens it for the two-column phone cards ("Site < target").
  String label({bool compact = false}) {
    final m = RegExp(r'_(pb|tb|gb|mb)$', caseSensitive: false).firstMatch(column);
    final words = humanize(m == null ? column : column.substring(0, m.start)).split(' ');
    var s = [for (var i = 0; i < words.length; i++) i == 0 || RegExp(r'[A-Z]{2,}|\d').hasMatch(words[i]) ? words[i] : words[i].toLowerCase()].join(' ');
    if (compact) s = s.replaceAll(' di bawah ', ' < ').replaceAll(' di atas ', ' > ');
    return s;
  }

  String get valueText {
    final m = RegExp(r'_(pb|tb|gb|mb)$', caseSensitive: false).firstMatch(column);
    final unit = m != null ? _unitSuffix[m[1]!.toLowerCase()]! : RegExp(r'^(jumlah_)?sites?(_|$)', caseSensitive: false).hasMatch(column) && _int ? 'site' : '';
    final body = format == 'number' && !_int ? idNum(value, 1) : formatValue(value, format);
    return unit.isEmpty ? body : '$body $unit';
  }

  /// Arrow, amount and color of the change, or null without a previous value.
  (bool? up, String text, Color color)? get change {
    if (delta == null || prev == null) return null;
    final diff = value - prev!;
    final up = diff > 0;
    final good = _lowerIsBetter.hasMatch(column) ? !up : up;
    final counts = format == 'number' && _int && prev == prev!.roundToDouble();
    final amount = counts ? idNum(diff.abs(), 0) : '${idNum(delta!.abs(), 1)}${deltaUnit == 'pp' ? ' pp' : '%'}';
    return (diff == 0 ? null : up, amount, diff == 0 ? V2.ink2 : good ? _green : V2.red);
  }
}

/// Up to three headline cards, two per row on a phone.
class KpiGridV2 extends StatelessWidget {
  const KpiGridV2({super.key, required this.kpis});
  final List<HeadlineKpi> kpis;

  @override
  Widget build(BuildContext context) {
    final items = kpis.take(3).toList();
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [for (final k in items) SizedBox(width: w, child: _KpiCard(k))]);
    });
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.k);
  final HeadlineKpi k;

  @override
  Widget build(BuildContext context) {
    final ch = k.change;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: V2.rule2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.label(compact: true), maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(12.5, FontWeight.w500, V2.ink2, lh: 15 / 12.5)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(k.valueText, maxLines: 1, style: V2.d(19, FontWeight.w700, V2.ink, lh: 1.15, ls: -.01)),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 12,
          child: ch == null
              ? null
              : Row(children: [
                  if (ch.$1 == null)
                    Text('= ', style: V2.d(12, FontWeight.w600, ch.$3, lh: 1))
                  else ...[
                    Triangle(up: ch.$1!, color: ch.$3),
                    const SizedBox(width: 4),
                  ],
                  Text(ch.$2, style: V2.d(12, FontWeight.w600, ch.$3, lh: 1)),
                ]),
        ),
      ]),
    );
  }
}

/// The ▲ / ▼ glyph of the mockup (the bundled fonts have none), 11 x 10 px.
class Triangle extends StatelessWidget {
  const Triangle({super.key, required this.up, required this.color, this.width = 11, this.height = 10});
  final bool up;
  final Color color;
  final double width, height;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(width, height), painter: _TrianglePainter(up, color));
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.up, this.color);
  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Path();
    if (up) {
      p..moveTo(s.width / 2, 0)..lineTo(s.width, s.height)..lineTo(0, s.height);
    } else {
      p..moveTo(0, 0)..lineTo(s.width, 0)..lineTo(s.width / 2, s.height);
    }
    canvas.drawPath(p..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter o) => o.up != up || o.color != color;
}

// ── Plot data (same rules as the web toPlot) ──────────────────────────────────

class PlotSeries {
  PlotSeries(this.name, this.values, this.color, {this.tips});
  final String name;
  final List<double?> values;
  final Color color;

  /// Tooltip row label per point when it differs from the legend name ("16 Sep").
  final List<String>? tips;
}

class AnswerPlot {
  AnswerPlot(this.labels, this.titles, this.series, this.fmt);
  final List<String> labels, titles;
  final List<PlotSeries> series;
  final String fmt;
}

(int, int)? _ym(dynamic v) {
  final m = RegExp(r'^(\d{4})-?(\d{2})$').firstMatch((v ?? '').toString());
  if (m == null) return null;
  final mo = int.parse(m[2]!);
  return mo >= 1 && mo <= 12 ? (int.parse(m[1]!), mo) : null;
}

int? _dayNum(dynamic v) {
  final n = toNum(v);
  return n != null && n == n.roundToDouble() && n >= 1 && n <= 31 ? n.toInt() : null;
}

/// Line, area and vertical bar results draw with the mockup chart; other shapes keep SmartChart.
AnswerPlot? toAnswerPlot(ChartSpec? spec, List<Map<String, dynamic>> rows) {
  if (spec == null || spec.x == null || !['line', 'area', 'bar'].contains(spec.type) || spec.y.isEmpty || rows.isEmpty) return null;
  final x = spec.x!;
  final y0 = spec.y.first;
  final fmt = spec.fmt(y0) ?? 'number';
  final sb = spec.seriesBy;
  if (sb != null) {
    var groups = <String>[];
    var keys = <String>[];
    for (final r in rows) {
      final g = (r[sb] ?? '').toString(), k = (r[x] ?? '').toString();
      if (!groups.contains(g)) groups.add(g);
      if (!keys.contains(k)) keys.add(k);
    }
    if (groups.length > v2SeriesColors.length || keys.length > 62) return null;
    final index = <String, double?>{for (final r in rows) '${r[x]}\u0000${r[sb]}': toNum(r[y0])};
    double? value(String k, String g) => index['$k\u0000$g'];
    // Month against month by day of month: newest month first, axis "1 .. 31",
    // tooltip "Jum, 16 Okt 2026" with rows "Okt" and "16 Sep".
    if (groups.every((g) => _ym(g) != null) && keys.every((k) => _dayNum(k) != null)) {
      groups = [...groups]..sort((a, b) => b.compareTo(a));
      keys = [...keys]..sort((a, b) => _dayNum(a)!.compareTo(_dayNum(b)!));
      final (y, m) = _ym(groups.first)!;
      return AnswerPlot(
        [for (final k in keys) '${_dayNum(k)}'],
        [
          for (final k in keys)
            '${_days[DateTime(y, m, _dayNum(k)!).weekday - 1]}, ${_dayNum(k)} ${monthsId[m - 1]} $y',
        ],
        [
          for (var gi = 0; gi < groups.length; gi++)
            PlotSeries(
              monthsId[_ym(groups[gi])!.$2 - 1],
              [for (final k in keys) value(k, groups[gi])],
              v2SeriesColors[gi],
              tips: [for (final k in keys) gi == 0 ? monthsId[_ym(groups[gi])!.$2 - 1] : '${_dayNum(k)} ${monthsId[_ym(groups[gi])!.$2 - 1]}'],
            ),
        ],
        fmt,
      );
    }
    return AnswerPlot(
      [for (final k in keys) timeLabel(k, dayOnly: true)],
      [for (final k in keys) timeLabel(k)],
      [for (var gi = 0; gi < groups.length; gi++) PlotSeries(timeLabel(groups[gi]), [for (final k in keys) value(k, groups[gi])], v2SeriesColors[gi])],
      fmt,
    );
  }
  if (rows.length > 62 || spec.y.length > v2SeriesColors.length) return null;
  return AnswerPlot(
    [for (final r in rows) timeLabel(r[x], dayOnly: true)],
    [for (final r in rows) timeLabel(r[x])],
    [for (var i = 0; i < spec.y.length; i++) PlotSeries(humanize(spec.y[i]), [for (final r in rows) toNum(r[spec.y[i]])], v2SeriesColors[i])],
    fmt,
  );
}

/// One decimal in the tooltip: "Rp 12,2 M".
String fmt1(double v, String fmt) {
  final a = v.abs();
  String? body;
  if (a >= 1e12) {
    body = '${idNum(v / 1e12, 1)} T';
  } else if (a >= 1e9) {
    body = '${idNum(v / 1e9, 1)} M';
  } else if (a >= 1e6) {
    body = '${idNum(v / 1e6, 1)} jt';
  }
  if (body == null) return formatValue(v, fmt);
  return fmt == 'currency' ? 'Rp $body' : body;
}

double _niceStep(double span, int target) {
  final raw = span / math.max(1, target);
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / mag;
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * mag;
}

List<double> niceTicks(double min, double max, [int target = 3]) {
  if (min == max) {
    min -= 1;
    max += 1;
  }
  final step = _niceStep(max - min, target);
  final lo = (min / step).floor() * step, hi = (max / step).ceil() * step;
  return [for (var v = lo; v <= hi + step / 2; v += step) double.parse(v.toStringAsFixed(10))];
}

// ── Chart ─────────────────────────────────────────────────────────────────────

/// Mockup chart, phone size: 150 px high, padding 30 / 8 / 8 / 22, Poppins 10 axis
/// text, legend chips under the plot. Touch or drag moves the hover point.
class AnswerChartV2 extends StatefulWidget {
  const AnswerChartV2({super.key, required this.plot, this.height = 150, this.initialHover});
  final AnswerPlot plot;
  final double height;
  final int? initialHover;

  @override
  State<AnswerChartV2> createState() => _AnswerChartV2State();
}

class _AnswerChartV2State extends State<AnswerChartV2> {
  static const _pad = (30.0, 8.0, 8.0, 22.0);
  late int _hover = widget.initialHover ?? (widget.plot.labels.length - 1) ~/ 2;
  late List<bool> _on = [for (final _ in widget.plot.series) true];

  @override
  void didUpdateWidget(AnswerChartV2 old) {
    super.didUpdateWidget(old);
    if (old.plot.series.length != widget.plot.series.length) _on = [for (final _ in widget.plot.series) true];
    if (_hover >= widget.plot.labels.length) _hover = widget.plot.labels.length - 1;
  }

  void _touch(double dx, double w) {
    final n = widget.plot.labels.length;
    final iw = math.max(1.0, w - _pad.$1 - _pad.$2);
    final i = (((dx - _pad.$1) / iw) * (n - 1)).round().clamp(0, n - 1);
    if (i != _hover) setState(() => _hover = i);
  }

  @override
  Widget build(BuildContext context) {
    final plot = widget.plot;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final geo = _Geo(plot, _on, w, widget.height, _pad);
        final rows = [
          for (var i = 0; i < plot.series.length; i++)
            if (_on[i] && _hover < plot.series[i].values.length && plot.series[i].values[_hover] != null) i,
        ];
        final hx = geo.x(_hover);
        final flip = hx + 14 + 170 > w;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _touch(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _touch(d.localPosition.dx, w),
          child: SizedBox(
            height: widget.height + 7,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: widget.height,
                child: Semantics(
                  label: 'Grafik ${plot.series.map((s) => s.name).join(', ')}',
                  child: CustomPaint(painter: _ChartPainter(geo, _hover)),
                ),
              ),
              if (rows.isNotEmpty && plot.labels.isNotEmpty)
                Positioned(
                  left: flip ? hx - 14 - 150 : hx + 14,
                  top: 4,
                  child: _Tip(
                    title: plot.titles[_hover],
                    rows: [
                      for (final i in rows)
                        (plot.series[i].color, plot.series[i].tips?[_hover] ?? plot.series[i].name, fmt1(plot.series[i].values[_hover]!, plot.fmt)),
                    ],
                  ),
                ),
            ]),
          ),
        );
      }),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < plot.series.length; i++)
          Semantics(
            button: true,
            toggled: _on[i],
            label: plot.series[i].name,
            child: GestureDetector(
              onTap: () => setState(() {
                if (_on.where((b) => b).length > 1 || !_on[i]) _on[i] = !_on[i];
              }),
              child: Opacity(
                opacity: _on[i] ? 1 : .45,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: V2.rule)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: plot.series[i].color, shape: BoxShape.circle)),
                    const SizedBox(width: 7),
                    Text(plot.series[i].name, style: V2.d(12, FontWeight.w500, V2.ink2, lh: 1)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    ]);
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.title, required this.rows});
  final String title;
  final List<(Color, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final t = V2.d(12, FontWeight.w500, Colors.white, lh: 1.5);
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: V2.ink, borderRadius: BorderRadius.circular(12), boxShadow: [cssShadow(const Color(0x40000000), 0, 10, 24)]),
        child: IntrinsicWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: t.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            for (final (c, name, v) in rows)
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Text(name, style: t),
                const Spacer(),
                const SizedBox(width: 12),
                Text(v, style: t.copyWith(fontWeight: FontWeight.w700)),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _Geo {
  _Geo(this.plot, this.on, this.w, this.h, (double, double, double, double) pad)
      : pl = pad.$1,
        pr = pad.$2,
        pt = pad.$3,
        pb = pad.$4 {
    final vals = <double>[
      for (var i = 0; i < plot.series.length; i++)
        if (on[i]) ...plot.series[i].values.whereType<double>(),
    ];
    ticks = niceTicks(vals.isEmpty ? 0 : vals.reduce(math.min), vals.isEmpty ? 1 : vals.reduce(math.max));
    lo = ticks.first;
    hi = ticks.last;
    iw = math.max(1, w - pl - pr);
    ih = h - pt - pb;
  }
  final AnswerPlot plot;
  final List<bool> on;
  final double w, h, pl, pr, pt, pb;
  late final List<double> ticks;
  late final double lo, hi, iw, ih;

  int get n => plot.labels.length;
  double x(int i) => pl + (n > 1 ? iw * i / (n - 1) : iw / 2);
  double y(double v) => pt + ih * (1 - (v - lo) / ((hi - lo) == 0 ? 1 : hi - lo));

  /// Axis text without the unit (the unit sits in the answer text): "12" for Rp 12 M.
  String axis(double v) {
    if (plot.fmt == 'percent') return '${idNum(v, 1)}%';
    final mx = math.max(hi.abs(), lo.abs());
    final d = mx >= 1e12 ? 1e12 : mx >= 1e9 ? 1e9 : mx >= 1e6 ? 1e6 : 1.0;
    return idNum(v / d, 1);
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.g, this.hover);
  final _Geo g;
  final int hover;

  void _text(Canvas c, String s, double x, double baseline, TextAlign align) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: V2.d(10, FontWeight.w400, V2.mute)),
      textDirection: TextDirection.ltr,
    )..layout();
    final b = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final dx = align == TextAlign.right ? x - tp.width : x - tp.width / 2;
    tp.paint(c, Offset(dx, baseline - b));
  }

  Path _line(List<double?> vs) {
    final p = Path();
    var pen = false;
    for (var i = 0; i < vs.length; i++) {
      final v = vs[i];
      if (v == null) {
        pen = false;
        continue;
      }
      pen ? p.lineTo(g.x(i), g.y(v)) : p.moveTo(g.x(i), g.y(v));
      pen = true;
    }
    return p;
  }

  /// SVG stroke-dasharray with round caps on every dash.
  void _dashed(Canvas c, Path path, Paint paint, double on, double off) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        c.drawPath(m.extractPath(d, math.min(d + on, m.length)), paint);
        d += on + off;
      }
    }
  }

  @override
  void paint(Canvas c, Size size) {
    final grid = Paint()
      ..color = V2.rule2
      ..strokeWidth = 1;
    for (final v in g.ticks) {
      c.drawLine(Offset(g.pl, g.y(v)), Offset(g.w - g.pr, g.y(v)), grid);
      _text(c, g.axis(v), g.pl - 8, g.y(v) + 4, TextAlign.right);
    }
    final every = math.max(1, (g.n / 5).ceil());
    for (var i = 0; i < g.n; i += every) {
      _text(c, g.plot.labels[i], g.x(i), g.h - 6, TextAlign.center);
    }
    final s = g.plot.series;
    if (s.isNotEmpty && g.on[0]) {
      final vs = s[0].values;
      final first = vs.indexWhere((v) => v != null);
      final last = vs.lastIndexWhere((v) => v != null);
      if (first >= 0) {
        final area = _line(vs)
          ..lineTo(g.x(last), g.y(g.lo))
          ..lineTo(g.x(first), g.y(g.lo))
          ..close();
        final b = area.getBounds();
        c.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [s[0].color.withValues(alpha: .22), s[0].color.withValues(alpha: 0)],
            ).createShader(b),
        );
      }
    }
    for (var si = s.length - 1; si >= 0; si--) {
      if (!g.on[si]) continue;
      final p = Paint()
        ..color = s[si].color
        ..style = PaintingStyle.stroke
        ..strokeWidth = si == 0 ? 2.6 : 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      final path = _line(s[si].values);
      si == 0 ? c.drawPath(path, p) : _dashed(c, path, p, 5, 4);
    }
    if (g.n > 0) {
      final rule = Paint()
        ..color = V2.ink.withValues(alpha: .5)
        ..strokeWidth = 1;
      final hx = g.x(hover);
      for (var y = g.pt; y < g.pt + g.ih; y += 6) {
        c.drawLine(Offset(hx, y), Offset(hx, math.min(y + 3, g.pt + g.ih)), rule);
      }
      for (var si = s.length - 1; si >= 0; si--) {
        final v = hover < s[si].values.length ? s[si].values[hover] : null;
        if (!g.on[si] || v == null) continue;
        final o = Offset(hx, g.y(v));
        c.drawCircle(o, 5, Paint()..color = Colors.white);
        c.drawCircle(
          o,
          5,
          Paint()
            ..color = s[si].color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ChartPainter o) => true;
}

// ── Grafik / Tabel / Peta card ────────────────────────────────────────────────

class AnswerVizV2 extends StatefulWidget {
  const AnswerVizV2({
    super.key,
    required this.columns,
    required this.rows,
    this.spec,
    this.chartFallback,
    this.initialHover,
    this.onOpenMap,
  });
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final ChartSpec? spec;

  /// Chart for shapes the mockup chart does not draw (hbar, pie, scatter...).
  final Widget? chartFallback;
  final int? initialHover;
  final VoidCallback? onOpenMap;

  @override
  State<AnswerVizV2> createState() => _AnswerVizV2State();
}

class _AnswerVizV2State extends State<AnswerVizV2> {
  late final AnswerPlot? _plot = toAnswerPlot(widget.spec, widget.rows);
  late String _tab = _plot != null || widget.chartFallback != null ? 'chart' : 'table';
  bool _all = false;

  bool get _hasMap =>
      widget.spec?.mapKey != null ||
      (widget.columns.any((c) => RegExp(r'(^|_)lat(itude)?$', caseSensitive: false).hasMatch(c)) &&
          widget.columns.any((c) => RegExp(r'(^|_)lon(g|gitude)?$', caseSensitive: false).hasMatch(c)));

  @override
  Widget build(BuildContext context) {
    final hasChart = _plot != null || widget.chartFallback != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: V2.rule)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            if (hasChart) _segBtn('chart', 'line', 'Grafik'),
            _segBtn('table', 'table', 'Tabel'),
            if (_hasMap) _segBtn('map', 'map', 'Peta'),
          ]),
        ),
        const SizedBox(height: 10),
        if (_tab == 'chart' && _plot != null) AnswerChartV2(plot: _plot, initialHover: widget.initialHover),
        if (_tab == 'chart' && _plot == null && widget.chartFallback != null) widget.chartFallback!,
        if (_tab == 'table') _table(),
        if (_tab == 'map') _map(),
      ]),
    );
  }

  Widget _segBtn(String id, String icon, String label) {
    final on = _tab == id;
    final c = on ? V2.teal700 : V2.ink2;
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Semantics(
        selected: on,
        button: true,
        label: label,
        child: GestureDetector(
          onTap: () => setState(() => _tab = id),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: on ? Colors.white : null,
              borderRadius: BorderRadius.circular(8),
              boxShadow: on ? [cssShadow(const Color(0x1F0F1F1D), 0, 1, 3)] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MIcon(icon, size: 14, color: c),
              const SizedBox(width: 6),
              Text(label, style: V2.d(12, FontWeight.w600, c, lh: 1)),
            ]),
          ),
        ),
      ),
    );
  }

  bool _numeric(String c) => widget.rows.any((r) => toNum(r[c]) != null);

  Widget _table() {
    final rows = _all ? widget.rows : widget.rows.take(8).toList();
    final head = V2.d(11.5, FontWeight.w600, V2.mute, lh: 1.2);
    final body = V2.b(13, FontWeight.w400, V2.ink, lh: 1.3);
    String cell(dynamic v, String c) {
      final n = toNum(v);
      if (n == null) return v?.toString() ?? '–';
      return formatValue(n, widget.spec?.fmt(c));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: V2.rule))),
              children: [
                for (final c in widget.columns)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text(humanize(c), textAlign: _numeric(c) ? TextAlign.right : TextAlign.left, style: head),
                  ),
              ],
            ),
            for (final r in rows)
              TableRow(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: V2.rule2))),
                children: [
                  for (final c in widget.columns)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Text(cell(r[c], c), textAlign: _numeric(c) ? TextAlign.right : TextAlign.left, style: body),
                    ),
                ],
              ),
          ],
        ),
      ),
      if (widget.rows.length > 8)
        TextButton(
          onPressed: () => setState(() => _all = !_all),
          child: Text(_all ? 'Ringkas' : 'Tampilkan semua ${widget.rows.length} baris', style: V2.d(12.5, FontWeight.w600, V2.teal700)),
        ),
    ]);
  }

  Widget _map() {
    final key = widget.spec?.mapKey;
    final tiles = <Widget>[];
    if (key != null && widget.columns.contains(key)) {
      final delta = widget.columns.where((c) => RegExp(r'(mom|yoy|wow|growth|delta|change|vs_)', caseSensitive: false).hasMatch(c) && _numeric(c)).firstOrNull;
      final metric = delta ?? widget.spec!.y.firstOrNull;
      final vals = [for (final r in widget.rows) toNum(r[metric]) ?? 0.0];
      final mx = vals.isEmpty ? 1.0 : math.max(1.0, vals.map((v) => v.abs()).reduce(math.max));
      for (var i = 0; i < math.min(24, widget.rows.length); i++) {
        final v = vals[i];
        final (bg, fg) = _shade(delta != null ? v : v / mx * 10 - 5);
        tiles.add(Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${widget.rows[i][key] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(11, FontWeight.w600, fg, lh: 1.2)),
            Text(
              delta != null ? '${v > 0 ? '+' : v < 0 ? '−' : ''}${idNum(v.abs(), 1)}%' : formatValue(v, widget.spec?.fmt(metric ?? '')),
              maxLines: 1,
              style: V2.d(12, FontWeight.w700, fg, lh: 1.2),
            ),
          ]),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (tiles.isNotEmpty)
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 12) / 3;
          return Wrap(spacing: 6, runSpacing: 6, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
        }),
      const SizedBox(height: 8),
      Text('Peta ringkas per wilayah. Buka di Peta Agent untuk batas wilayah asli dan titik koordinat.', style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3)),
      if (widget.onOpenMap != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: widget.onOpenMap,
            icon: const MIcon('map', size: 16, color: V2.teal700),
            label: Text('Buka di Peta Agent', style: V2.d(12.5, FontWeight.w600, V2.teal700)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: V2.rule), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ],
    ]);
  }

  (Color, Color) _shade(double v) => v <= -5
      ? (V2.red, Colors.white)
      : v <= -2
          ? (const Color(0xFFF7B4A7), const Color(0xFF6E2410))
          : v < 0
              ? (const Color(0xFFFDECEC), const Color(0xFF8A2020))
              : v <= 2
                  ? (const Color(0xFFDDF1E4), const Color(0xFF1F5E30))
                  : (const Color(0xFF2E9E57), Colors.white);
}

/// Answer prose: **bold** and a red / green "turun 2,4%" / "naik 3,1%", like the mockup.
/// Returns null when the text needs full Markdown (headings, lists, tables).
TextSpan? answerSpans(String text, {double size = 14, double lh = 1.55}) {
  if (RegExp(r'^\s*(#|[-*] |\d+\. |\|)', multiLine: true).hasMatch(text)) return null;
  final base = V2.b(size, FontWeight.w400, V2.ink, lh: lh);
  final bold = base.copyWith(fontWeight: FontWeight.w600);
  final spans = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|\b(turun|naik|down|up)\s+(\d+(?:[.,]\d+)?\s?(?:%|pp))', caseSensitive: false);
  var at = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    if (m[1] != null) {
      spans.add(TextSpan(text: m[1], style: bold));
    } else {
      final down = RegExp(r'turun|down', caseSensitive: false).hasMatch(m[2]!);
      spans.add(TextSpan(text: m[0], style: bold.copyWith(color: down ? V2.red : _green)));
    }
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: base, children: spans);
}
