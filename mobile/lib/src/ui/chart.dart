// Agent answer charts. Draws the render-ready spec from backend/app/chart_spec.py
// (the same spec the web SmartChart uses) with fl_chart, styled like the
// mockup: hairline grid, smooth teal line with a soft area, the previous
// period as a dashed grey line, a dashed crosshair and the dark tooltip.
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'ds.dart';
import 'icons.dart';
import 'kit.dart';

class ChartSpec {
  ChartSpec(this.raw);
  final Map<String, dynamic> raw;

  String get type => (raw['type'] ?? 'none').toString();
  String? get x => raw['x']?.toString();
  List<String> get y => _list(raw['y']);
  List<String> get y2 => _list(raw['y2']);
  String? get seriesBy => raw['series_by']?.toString();
  String? get label => raw['label']?.toString();
  String? get sort => raw['sort']?.toString();
  int? get topN => (raw['top_n'] as num?)?.toInt();
  String? get mapKey => raw['map_key']?.toString();
  String get title => (raw['title'] ?? '').toString();
  List<String> get alternatives => _list(raw['alternatives']);
  String? fmt(String col) => (raw['formats'] as Map?)?[col]?.toString();

  static List<String> _list(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];
}

// ── Formatting (mirrors the web helpers) ──────────────────────────────────

final _id = NumberFormat.decimalPattern('id');

String idNum(num v, [int digits = 2]) {
  final f = NumberFormat.decimalPattern('id')..maximumFractionDigits = digits;
  return f.format(v);
}

/// 1.234 rb, 12,3 jt, 4,5 M, 1,2 T.
String shortNum(num n) {
  final a = n.abs();
  if (a >= 1e12) return '${idNum(n / 1e12, 2)} T';
  if (a >= 1e9) return '${idNum(n / 1e9, 1)} M';
  if (a >= 1e6) return '${idNum(n / 1e6, 1)} jt';
  if (a >= 1e4) return '${idNum(n / 1e3, 1)} rb';
  return _id.format(n);
}

String formatValue(dynamic v, String? fmt, {bool short = true}) {
  final n = toNum(v);
  if (n == null) return v == null ? '–' : v.toString();
  if (fmt == 'percent') {
    final pct = n.abs() <= 1 && n != 0 ? n * 100 : n;
    return '${idNum(pct, 2)}%';
  }
  final body = short ? shortNum(n) : _id.format(n);
  return fmt == 'currency' ? 'Rp $body' : body;
}

double? toNum(dynamic v) {
  if (v is num) return v.isFinite ? v.toDouble() : null;
  if (v is String && v.trim().isNotEmpty) return double.tryParse(v.trim());
  return null;
}

const _acronyms = {
  'mom': 'MoM', 'yoy': 'YoY', 'wow': 'WoW', 'qoq': 'QoQ', 'pct': '%', 'arpu': 'ARPU', 'fwa': 'FWA',
  'ftth': 'FTTH', 'ga': 'GA', 'kpi': 'KPI', 'id': 'ID', 'pb': 'PB', 'gb': 'GB', 'tb': 'TB', 'bts': 'BTS',
  'im3': 'IM3', '5g': '5G', '4g': '4G',
};

/// "gross_add" → "Gross add", "mom_pct" → "MoM (%)".
String humanize(String col) {
  final words = col.replaceAll('_', ' ').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return col;
  final out = <String>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final acr = _acronyms[w.toLowerCase()];
    if (acr != null) {
      out.add(acr);
    } else if (w != w.toLowerCase()) {
      out.add(w);
    } else {
      out.add(i == 0 ? '${w[0].toUpperCase()}${w.substring(1)}' : w);
    }
  }
  return out.join(' ').replaceAll(' %', ' (%)');
}

const monthsId = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

/// (year, month, day?) from "2026-10-16", "20261016", "202610" or a DateTime-ish string.
(int, int, int?)? parseDate(dynamic v) {
  final s = (v ?? '').toString();
  var m = RegExp(r'^(\d{4})-?(\d{2})-?(\d{2})(?:[ T]|$)').firstMatch(s);
  if (m != null) return (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  m = RegExp(r'^(\d{4})-?(\d{2})$').firstMatch(s);
  if (m != null && int.parse(m[2]!) >= 1 && int.parse(m[2]!) <= 12) return (int.parse(m[1]!), int.parse(m[2]!), null);
  return null;
}

String timeLabel(dynamic v, {bool dayOnly = false}) {
  final d = parseDate(v);
  if (d == null) {
    final s = (v ?? '').toString();
    return s.length > 16 ? '${s.substring(0, 16)}…' : s;
  }
  final (y, mo, day) = d;
  if (day != null) return dayOnly ? '$day' : '$day ${monthsId[mo - 1]}';
  return '${monthsId[mo - 1]} ${y.toString().substring(2)}';
}

// ── Chart widget ──────────────────────────────────────────────────────────

class _Series {
  _Series(this.name, this.values, this.color, {this.dashed = false, this.area = false, this.fmt, this.axis2 = false, this.bar = false});
  final String name;
  final List<double?> values;
  final Color color;
  final bool dashed, area, axis2, bar;
  final String? fmt;
}

List<Color> chartPalette(Pal p) => [
      p.teal600, p.teal300, p.chartAmber, p.blue600, p.violet600, p.amber700, p.rose600, p.green600,
    ];

const _typeLabel = {
  'kpi': 'KPI', 'line': 'Garis', 'area': 'Area', 'bar': 'Batang', 'hbar': 'Batang horizontal',
  'stacked_bar': 'Bertumpuk', 'donut': 'Donat', 'scatter': 'Sebaran', 'combo': 'Kombinasi',
};

final _prevCol = RegExp(r'prev|lalu|sebelum|_ly$|last', caseSensitive: false);

/// Plots an agent result from its chart spec. [touchIndex] pins the
/// crosshair (golden tests); users get it by touching the chart.
class SmartChart extends StatefulWidget {
  const SmartChart({
    super.key,
    required this.spec,
    required this.rows,
    this.height = 130,
    this.touchIndex,
    this.onDrill,
    this.showHeader = false,
  });
  final ChartSpec spec;
  final List<Map<String, dynamic>> rows;
  final double height;
  final int? touchIndex;
  final void Function(String column, String value)? onDrill;
  final bool showHeader;

  @override
  State<SmartChart> createState() => _SmartChartState();
}

class _SmartChartState extends State<SmartChart> {
  late String _type = widget.spec.type;
  int? _touch;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _touch = widget.touchIndex;
  }

  @override
  void didUpdateWidget(covariant SmartChart old) {
    super.didUpdateWidget(old);
    if (old.spec.type != widget.spec.type) _type = widget.spec.type;
  }

  ChartSpec get spec => widget.spec;

  List<Map<String, dynamic>> get _rows {
    var out = widget.rows;
    final m = spec.y.isEmpty ? null : spec.y.first;
    if (spec.sort == 'desc' && spec.x != null && m != null && spec.seriesBy == null) {
      out = [...out]..sort((a, b) => (toNum(b[m]) ?? double.negativeInfinity).compareTo(toNum(a[m]) ?? double.negativeInfinity));
    }
    if (spec.topN != null && !_showAll && spec.seriesBy == null && out.length > spec.topN!) out = out.sublist(0, spec.topN!);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (spec.type == 'none' || widget.rows.isEmpty) return const SizedBox.shrink();
    final p = Pal.of(context);
    final rows = _rows;
    final options = [spec.type, ...spec.alternatives.where((a) => a != spec.type && a != 'none')];

    Widget body;
    switch (_type) {
      case 'kpi':
        body = KpiTiles(spec: spec, rows: rows);
      case 'donut':
        body = _donut(p, rows);
      case 'scatter':
        body = _scatter(p, rows);
      case 'hbar':
        body = _hbar(p, rows);
      default:
        body = _cartesian(p, rows);
    }

    final hidden = spec.topN != null && spec.seriesBy == null ? widget.rows.length - spec.topN! : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.showHeader || options.length > 1)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: Text(spec.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13, w600, p.ink))),
            if (options.length > 1) _typeMenu(p, options),
          ]),
        ),
      body,
      if (hidden > 0)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAll = !_showAll),
            child: Text(_showAll ? 'Tampilkan ${spec.topN} teratas' : 'Tampilkan semua (${widget.rows.length})',
                style: ts(12, w600, p.teal700)),
          ),
        ),
    ]);
  }

  Widget _typeMenu(Pal p, List<String> options) => PopupMenuButton<String>(
        tooltip: 'Jenis grafik',
        initialValue: _type,
        onSelected: (t) => setState(() { _type = t; _touch = null; }),
        itemBuilder: (_) => [
          for (final t in options) PopupMenuItem(value: t, child: Text(_typeLabel[t] ?? t, style: ts(13, w500, p.ink))),
        ],
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: p.rule)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_typeLabel[_type] ?? _type, style: ts(12, w500, p.text2)),
            const SizedBox(width: 4),
            Ic(Icx.chevronDown, size: 14, color: p.text2),
          ]),
        ),
      );

  // ── line / area / bar / stacked / combo ──

  List<String> _categories(List<Map<String, dynamic>> rows) {
    final x = spec.x ?? '';
    if (spec.seriesBy == null) return [for (final r in rows) (r[x] ?? '').toString()];
    final seen = <String>[];
    for (final r in rows) {
      final c = (r[x] ?? '').toString();
      if (!seen.contains(c)) seen.add(c);
    }
    return seen;
  }

  List<_Series> _series(Pal p, List<Map<String, dynamic>> rows, List<String> cats, bool isLine) {
    final colors = chartPalette(p);
    final x = spec.x ?? '';
    if (spec.seriesBy != null && spec.y.isNotEmpty) {
      final m = spec.y.first, by = spec.seriesBy!;
      final groups = <String>[];
      final cell = <String, double>{};
      for (final r in rows) {
        final g = (r[by] ?? '').toString();
        if (!groups.contains(g)) groups.add(g);
        cell['${r[x]}|$g'] = toNum(r[m]) ?? 0;
      }
      return [
        for (var i = 0; i < groups.length && i < 8; i++)
          _Series(groups[i], [for (final c in cats) cell['$c|${groups[i]}'] ?? 0], colors[i % colors.length],
              fmt: spec.fmt(m), area: _type == 'area', bar: !isLine),
      ];
    }
    if (_type == 'combo') {
      return [
        for (var i = 0; i < spec.y.length; i++)
          _Series(humanize(spec.y[i]), [for (final r in rows) toNum(r[spec.y[i]])], colors[i % colors.length], fmt: spec.fmt(spec.y[i]), bar: true),
        for (var i = 0; i < spec.y2.length; i++)
          _Series(humanize(spec.y2[i]), [for (final r in rows) toNum(r[spec.y2[i]])], colors[(i + 3) % colors.length],
              fmt: spec.fmt(spec.y2[i]), axis2: true),
      ];
    }
    return [
      for (var i = 0; i < spec.y.length; i++)
        () {
          final c = spec.y[i];
          final dashed = isLine && i > 0 && _prevCol.hasMatch(c);
          return _Series(
            _seriesName(c, rows),
            [for (final r in rows) toNum(r[c])],
            dashed ? p.chartGrey : colors[i % colors.length],
            dashed: dashed,
            area: isLine && (_type == 'area' || i == 0) && !dashed,
            fmt: spec.fmt(c),
            bar: !isLine,
          );
        }(),
    ];
  }

  /// Name a "this period vs previous period" pair by month when the x axis is
  /// daily dates in one month (Okt / Sep), else humanize the column.
  String _seriesName(String col, List<Map<String, dynamic>> rows) {
    if (spec.y.length == 2 && spec.x != null && rows.isNotEmpty) {
      final d = parseDate(rows.first[spec.x]);
      final last = parseDate(rows.last[spec.x]);
      if (d != null && last != null && d.$3 != null && d.$2 == last.$2 && _prevCol.hasMatch(spec.y[1])) {
        final cur = d.$2, prev = cur == 1 ? 12 : cur - 1;
        return monthsId[(col == spec.y[1] ? prev : cur) - 1];
      }
    }
    return humanize(col);
  }

  bool _sameMonthDays(List<String> cats) {
    if (cats.isEmpty) return false;
    final a = parseDate(cats.first), b = parseDate(cats.last);
    return a != null && b != null && a.$3 != null && a.$1 == b.$1 && a.$2 == b.$2;
  }

  /// Three "nice" ticks covering [lo, hi] and the divisor used for labels.
  (double, double, double, double) _axis(double lo, double hi, {bool zero = false}) {
    if (zero) lo = math.min(0, lo);
    if (hi == lo) hi = lo + 1;
    final raw = (hi - lo) / 2;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [1, 1.5, 2, 2.5, 3, 4, 5, 10].map((s) => s * mag).firstWhere((s) => s >= raw, orElse: () => 10 * mag);
    final min = zero ? 0.0 : (lo / step).floor() * step;
    final max = min + step * 2 < hi ? min + step * ((hi - min) / step).ceil() : min + step * 2;
    final top = math.max(hi, max);
    final a = top.abs() >= 1e12 ? 1e12 : top.abs() >= 1e9 ? 1e9 : top.abs() >= 1e6 ? 1e6 : top.abs() >= 1e4 ? 1e3 : 1.0;
    return (min, top, (top - min) / 2, a);
  }

  String _tick(double v, double div, String? fmt) {
    if (fmt == 'percent') return formatValue(v, fmt);
    return idNum(v / div, 1);
  }

  Widget _cartesian(Pal p, List<Map<String, dynamic>> rows) {
    final isLine = _type == 'line' || _type == 'area';
    final cats = _categories(rows);
    final series = _series(p, rows, cats, isLine);
    final main = series.where((s) => !s.axis2).toList();
    final vals = [for (final s in main) ...s.values.whereType<double>()];
    if (vals.isEmpty || cats.isEmpty) return const SizedBox.shrink();
    final stacked = _type == 'stacked_bar';
    double hi = vals.reduce(math.max), lo = vals.reduce(math.min);
    if (stacked) {
      hi = 0;
      for (var i = 0; i < cats.length; i++) {
        hi = math.max(hi, main.fold<double>(0, (s, e) => s + (e.values[i] ?? 0)));
      }
    }
    final (minY, maxY, interval, div) = _axis(lo, hi, zero: !isLine);
    final dayAxis = _sameMonthDays(cats);
    final fmt0 = main.first.fmt;

    String xLabel(int i) => timeLabel(cats[i], dayOnly: dayAxis);
    final touched = _touch != null && _touch! < cats.length ? _touch : null;

    Widget plot;
    if (!isLine) {
      plot = _bars(p, cats, main, minY, maxY, interval, div, fmt0, xLabel, stacked);
    } else {
      plot = LineChart(
        LineChartData(
          minX: 0,
          maxX: (cats.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(color: p.rule, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: _titles(p, cats.length, interval, div, fmt0, xLabel, minY, maxY),
          extraLinesData: touched == null
              ? const ExtraLinesData()
              : ExtraLinesData(verticalLines: [
                  VerticalLine(x: touched.toDouble(), color: p.mute, strokeWidth: 1.5, dashArray: const [4, 4]),
                ]),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: false,
            touchCallback: (e, r) {
              if (r?.lineBarSpots == null || r!.lineBarSpots!.isEmpty) return;
              final i = r.lineBarSpots!.first.spotIndex;
              if (e is FlTapUpEvent && widget.onDrill != null && spec.mapKey != null) {
                widget.onDrill!(spec.mapKey!, cats[i]);
              }
              if (i != _touch) setState(() => _touch = i);
            },
          ),
          lineBarsData: [
            for (final s in series.reversed)
              LineChartBarData(
                spots: [for (var i = 0; i < s.values.length; i++) s.values[i] == null ? FlSpot.nullSpot : FlSpot(i.toDouble(), s.values[i]!)],
                isCurved: true,
                curveSmoothness: .35,
                preventCurveOverShooting: true,
                color: s.color,
                barWidth: s.dashed ? 2 : 2.5,
                dashArray: s.dashed ? const [5, 5] : null,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: touched != null,
                  checkToShowDot: (spot, _) => spot.x.toInt() == touched,
                  getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: 4.5,
                    color: p.surface,
                    strokeWidth: 3,
                    strokeColor: s.color,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: s.area,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [s.color.withValues(alpha: .2), s.color.withValues(alpha: 0)],
                  ),
                ),
              ),
          ],
        ),
        duration: Duration.zero,
      );
    }

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, c) {
        // Plot area starts after 26 px of y labels; x labels take 22 px below.
        const left = 26.0, right = 8.0;
        final plotW = c.maxWidth - left - right;
        Widget? tip;
        if (touched != null) {
          final head = dayAxis || parseDate(cats[touched]) != null ? timeLabel(cats[touched]) : cats[touched];
          final x = left + (cats.length == 1 ? 0 : touched / (cats.length - 1) * plotW);
          final rowsTip = [
            for (final s in series)
              if (touched < s.values.length) (s.color, s.name, formatValue(s.values[touched], s.fmt)),
          ];
          const tipW = 176.0;
          final toLeft = x - tipW - 14 >= -36;
          tip = Positioned(
            left: toLeft ? x - tipW - 14 : x + 14,
            top: 6,
            width: tipW,
            child: ChartTip(title: head, rows: rowsTip, width: tipW),
          );
        }
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: isLine ? (d) => _touchAt(d.localPosition.dx, left, plotW, cats.length) : null,
          onTapDown: isLine ? (d) => _touchAt(d.localPosition.dx, left, plotW, cats.length) : null,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: Padding(padding: const EdgeInsets.only(right: right, top: 8), child: plot)),
            if (tip != null) tip,
          ]),
        );
      }),
    );
  }

  void _touchAt(double dx, double left, double w, int n) {
    if (n < 2) return;
    final i = (((dx - left) / w) * (n - 1)).round().clamp(0, n - 1);
    if (i != _touch) setState(() => _touch = i);
  }

  FlTitlesData _titles(Pal p, int n, double interval, double div, String? fmt, String Function(int) xLabel, double minY, double maxY,
      {bool categoryAxis = false}) {
    final style = ts(12, w400, p.mute);
    // Lines show first / middle / last; bars label every bar that fits.
    final every = categoryAxis ? math.max(1, (n / 6).ceil()) : 0;
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 26,
          interval: interval,
          getTitlesWidget: (v, meta) {
            if (v != minY && v != maxY && (v - minY - interval).abs() > interval * .01) return const SizedBox.shrink();
            return SideTitleWidget(axisSide: meta.axisSide, space: 0, child: Text(_tick(v, div, fmt), style: style));
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: 1,
          getTitlesWidget: (v, meta) {
            final i = v.round();
            if (i < 0 || i >= n || v != i.toDouble()) return const SizedBox.shrink();
            final show = categoryAxis ? i % every == 0 : (i == 0 || i == n - 1 || i == (n - 1) ~/ 2);
            if (!show) return const SizedBox.shrink();
            return SideTitleWidget(
              axisSide: meta.axisSide,
              space: 4,
              child: Text(xLabel(i), style: i == _touch && categoryAxis ? ts(12, w600, p.ink) : style),
            );
          },
        ),
      ),
    );
  }

  Widget _bars(Pal p, List<String> cats, List<_Series> series, double minY, double maxY, double interval, double div, String? fmt,
      String Function(int) xLabel, bool stacked) {
    final groups = cats.length;
    final width = series.length == 1 || stacked ? 14.0 : math.max(6.0, 28.0 / series.length);
    return BarChart(
      BarChartData(
        minY: minY,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(color: p.rule, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(p, groups, interval, div, fmt, xLabel, minY, maxY, categoryAxis: true),
        barTouchData: BarTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xF00F1F1D),
            tooltipRoundedRadius: 12,
            tooltipPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (g, gi, rod, ri) {
              if (stacked && ri != 0) return null;
              final title = '${xLabel(g.x)}\n';
              final lines = stacked || series.length > 1
                  ? [for (final s in series) '${s.name}  ${formatValue(s.values[g.x], s.fmt)}'].join('\n')
                  : formatValue(series.first.values[g.x], series.first.fmt);
              return BarTooltipItem(title, ts(12, w600, Colors.white), children: [
                TextSpan(text: lines, style: ts(12, w400, const Color(0xFFC9D6D3))),
              ]);
            },
          ),
          touchCallback: (e, r) {
            final i = r?.spot?.touchedBarGroupIndex;
            if (i == null) return;
            if (e is FlTapUpEvent && widget.onDrill != null && spec.x != null) {
              widget.onDrill!(spec.mapKey ?? spec.x!, cats[i]);
            }
          },
        ),
        barGroups: [
          for (var g = 0; g < groups; g++)
            BarChartGroupData(
              x: g,
              barsSpace: 3,
              groupVertically: stacked,
              barRods: stacked
                  ? [
                      BarChartRodData(
                        toY: series.fold<double>(0, (s, e) => s + (e.values[g] ?? 0)),
                        width: width,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        rodStackItems: () {
                          var acc = 0.0;
                          return [
                            for (final s in series)
                              () {
                                final from = acc;
                                acc += s.values[g] ?? 0;
                                return BarChartRodStackItem(from, acc, s.color);
                              }(),
                          ];
                        }(),
                      ),
                    ]
                  : [
                      for (final s in series)
                        BarChartRodData(
                          toY: s.values[g] ?? 0,
                          color: s.color,
                          width: width,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                    ],
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  /// Ranked horizontal bars: label, bar and value on one row (reads well on a phone).
  Widget _hbar(Pal p, List<Map<String, dynamic>> rows) {
    final x = spec.x ?? '';
    final m = spec.y.isEmpty ? '' : spec.y.first;
    final vals = [for (final r in rows) toNum(r[m]) ?? 0];
    final hi = vals.fold<double>(0, (a, b) => math.max(a, b.abs()));
    return Column(children: [
      for (var i = 0; i < rows.length; i++)
        InkWell(
          onTap: widget.onDrill == null ? null : () => widget.onDrill!(spec.mapKey ?? x, (rows[i][x] ?? '').toString()),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(
                width: 96,
                child: Text(timeLabel(rows[i][x]), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w500, p.text2)),
              ),
              Expanded(
                child: LayoutBuilder(builder: (_, c) {
                  final f = hi == 0 ? 0.0 : vals[i].abs() / hi;
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: math.max(3, c.maxWidth * f),
                      height: 14,
                      decoration: BoxDecoration(
                        color: vals[i] < 0 ? p.dangerSolid : (i == 0 ? p.teal600 : p.teal300),
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 72,
                child: Text(formatValue(vals[i], spec.fmt(m)), textAlign: TextAlign.right, style: ts(12, w600, p.ink, tabular: true)),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _donut(Pal p, List<Map<String, dynamic>> rows) {
    final colors = chartPalette(p);
    final x = spec.x ?? '';
    final m = spec.y.isEmpty ? '' : spec.y.first;
    final vals = [for (final r in rows) toNum(r[m]) ?? 0];
    final total = vals.fold<double>(0, (a, b) => a + b);
    return Row(children: [
      SizedBox(
        width: 140,
        height: 140,
        child: Stack(alignment: Alignment.center, children: [
          PieChart(PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 44,
            startDegreeOffset: -90,
            pieTouchData: PieTouchData(touchCallback: (e, r) {
              final i = r?.touchedSection?.touchedSectionIndex;
              if (i != null && i >= 0 && i != _touch) setState(() => _touch = i);
            }),
            sections: [
              for (var i = 0; i < vals.length; i++)
                PieChartSectionData(
                  value: vals[i] <= 0 ? 0.0001 : vals[i],
                  color: colors[i % colors.length],
                  radius: _touch == i ? 26 : 22,
                  showTitle: false,
                ),
            ],
          ), duration: Duration.zero),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_touch != null && _touch! < vals.length ? formatValue(vals[_touch!], spec.fmt(m)) : formatValue(total, spec.fmt(m)),
                style: ts(15, w700, p.ink, lh: 1.2)),
            Text(_touch != null && _touch! < vals.length && total > 0 ? '${idNum(vals[_touch!] / total * 100, 1)}%' : 'Total',
                style: ts(11, w400, p.mute)),
          ]),
        ]),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < rows.length && i < 8; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: colors[i % colors.length], shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text((rows[i][x] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w400, p.text2))),
                Text(total > 0 ? '${idNum(vals[i] / total * 100, 1)}%' : '–', style: ts(12, w600, p.ink, tabular: true)),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _scatter(Pal p, List<Map<String, dynamic>> rows) {
    if (spec.y.length < 2) return const SizedBox.shrink();
    final mx = spec.y[0], my = spec.y[1];
    final pts = [
      for (final r in rows)
        if (toNum(r[mx]) != null && toNum(r[my]) != null) (toNum(r[mx])!, toNum(r[my])!, (r[spec.label ?? ''] ?? '').toString()),
    ];
    if (pts.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: math.max(widget.height, 180),
      child: ScatterChart(
        ScatterChartData(
          scatterSpots: [
            for (final (x, y, _) in pts)
              ScatterSpot(x, y, dotPainter: FlDotCirclePainter(radius: 6, color: p.teal600.withValues(alpha: .75), strokeColor: p.surface, strokeWidth: 1)),
          ],
          gridData: FlGridData(
            show: true,
            getDrawingHorizontalLine: (_) => FlLine(color: p.rule, strokeWidth: 1),
            getDrawingVerticalLine: (_) => FlLine(color: p.rule, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              axisNameWidget: Text(humanize(mx), style: ts(11, w400, p.mute)),
              sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (v, m) =>
                  SideTitleWidget(axisSide: m.axisSide, child: Text(formatValue(v, spec.fmt(mx)), style: ts(11, w400, p.mute)))),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: Text(humanize(my), style: ts(11, w400, p.mute)),
              sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, m) =>
                  SideTitleWidget(axisSide: m.axisSide, child: Text(formatValue(v, spec.fmt(my)), style: ts(11, w400, p.mute)))),
            ),
          ),
          scatterTouchData: ScatterTouchData(
            touchTooltipData: ScatterTouchTooltipData(
              getTooltipColor: (_) => const Color(0xF00F1F1D),
              getTooltipItems: (s) {
                final hit = pts.firstWhere((e) => e.$1 == s.x && e.$2 == s.y, orElse: () => (s.x, s.y, ''));
                return ScatterTooltipItem(
                  '${hit.$3}\n${humanize(mx)} ${formatValue(s.x, spec.fmt(mx))}\n${humanize(my)} ${formatValue(s.y, spec.fmt(my))}',
                  textStyle: ts(12, w500, Colors.white),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── KPI tiles ─────────────────────────────────────────────────────────────

final _deltaCol = RegExp(r'(_|^)(mom|yoy|wow|qoq|growth|delta|change|pct_change|chg|gap)(_|$)', caseSensitive: false);

(I3, Tone) kpiIcon(String col) {
  final c = col.toLowerCase();
  if (RegExp(r'rev|rp|arpu|sales|amount|nilai').hasMatch(c)) return (Icx.wallet, Tone.amber);
  if (RegExp(r'payload|traffic|data|gb|tb|pb').hasMatch(c)) return (Icx.database, Tone.violet);
  if (RegExp(r'gross|add|\bga\b|acq|new').hasMatch(c)) return (Icx.userPlus, Tone.green);
  if (RegExp(r'sub|user|pelanggan|customer|rgb').hasMatch(c)) return (Icx.users, Tone.blue);
  if (RegExp(r'site|avail|bts|tower|cell').hasMatch(c)) return (Icx.radio, Tone.teal);
  return (Icx.barChart, Tone.teal);
}

class KpiItem {
  const KpiItem(this.column, this.label, this.value, {this.delta, this.caption});
  final String column, label, value;
  final double? delta;
  final String? caption;
}

/// Tiles for a one-row KPI result (spec type "kpi").
class KpiTiles extends StatelessWidget {
  const KpiTiles({super.key, required this.spec, required this.rows});
  final ChartSpec spec;
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final r = rows.isEmpty ? const <String, dynamic>{} : rows.first;
    final deltas = spec.y.where(_deltaCol.hasMatch).toList();
    final values = spec.y.where((c) => !_deltaCol.hasMatch(c)).toList();
    String? deltaFor(String c) {
      for (final d in deltas) {
        if (d.toLowerCase().startsWith(c.toLowerCase().split('_').first)) return d;
      }
      return values.length == 1 && deltas.isNotEmpty ? deltas.first : null;
    }

    final items = [
      for (final c in values.isEmpty ? spec.y : values)
        () {
          final d = deltaFor(c);
          var dv = d == null ? null : toNum(r[d]);
          if (dv != null && (spec.fmt(d!) ?? 'percent') == 'percent' && dv.abs() <= 1 && dv != 0) dv *= 100;
          return KpiItem(c, humanize(c), formatValue(r[c], spec.fmt(c)), delta: dv);
        }(),
    ];
    return KpiGrid(items: items);
  }
}

/// Two-column grid of muted KPI tiles.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.items});
  final List<KpiItem> items;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final k in items)
        () {
          final (icon, tone) = kpiIcon(k.column);
          return KpiTile(
            icon: icon,
            tone: tone,
            iconSize: icon == Icx.userPlus || icon == Icx.users ? 24 : 16,
            label: k.label,
            value: k.value,
            caption: k.caption,
            delta: k.delta == null ? null : '${idNum(k.delta!.abs(), 1)}%',
            deltaUp: (k.delta ?? 0) >= 0,
          );
        }(),
    ];
    return Column(children: [
      for (var i = 0; i < tiles.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 8),
        Row(children: [
          Expanded(child: tiles[i]),
          const SizedBox(width: 8),
          Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
        ]),
      ],
    ]);
  }
}

/// For a daily/monthly series that carries a previous-period twin for its
/// measures (revenue + revenue_bulan_lalu), the period totals with their
/// change: the "Revenue Rp 412,6 M ▼2,4% vs Sep" tiles above the chart.
List<KpiItem> periodTotals(ChartSpec spec, List<String> columns, List<Map<String, dynamic>> rows) {
  if (rows.length < 2 || spec.x == null || parseDate(rows.first[spec.x]) == null) return const [];
  final out = <KpiItem>[];
  final d = parseDate(rows.first[spec.x])!;
  final prevMonth = monthsId[(d.$2 == 1 ? 12 : d.$2 - 1) - 1];
  for (final c in columns) {
    if (c == spec.x || _prevCol.hasMatch(c) || toNum(rows.first[c]) == null) continue;
    final twin = columns.firstWhere(
      (o) => o != c && _prevCol.hasMatch(o) && o.toLowerCase().startsWith(c.toLowerCase()),
      orElse: () => '',
    );
    if (twin.isEmpty) continue;
    final cur = rows.fold<double>(0, (s, r) => s + (toNum(r[c]) ?? 0));
    final prev = rows.fold<double>(0, (s, r) => s + (toNum(r[twin]) ?? 0));
    final fmt = spec.fmt(c) ?? (RegExp(r'rev|arpu|rp', caseSensitive: false).hasMatch(c) ? 'currency' : null);
    if (fmt == 'percent') continue; // rates don't add up
    out.add(KpiItem(c, humanize(c), formatValue(cur, fmt),
        delta: prev == 0 ? null : (cur - prev) / prev.abs() * 100, caption: d.$3 != null ? 'vs $prevMonth' : 'vs periode lalu'));
    if (out.length == 2) break;
  }
  return out;
}
