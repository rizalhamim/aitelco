import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme.dart';

const _series = [
  IOH.teal500, Color(0xFFF5A623), Color(0xFF2A74D4), Color(0xFFFF6B35),
  IOH.teal700, Color(0xFF9A6CFF), IOH.green, Color(0xFF0EA5E9),
];

/// Indonesian locale: comma is the decimal separator, dot separates thousands.
String _num(num n, [int digits = 1]) {
  final fixed = n.toStringAsFixed(digits);
  final parts = fixed.split('.');
  final whole = parts[0];
  final neg = whole.startsWith('-');
  final digitsOnly = neg ? whole.substring(1) : whole;
  final buf = StringBuffer();
  for (int i = 0; i < digitsOnly.length; i++) {
    if (i > 0 && (digitsOnly.length - i) % 3 == 0) buf.write('.');
    buf.write(digitsOnly[i]);
  }
  final head = '${neg ? '-' : ''}$buf';
  return parts.length > 1 && digits > 0 ? '$head,${parts[1]}' : head;
}

/// A number without its unit is not an answer: "2.4B" reads as a count, "Rp 2,4 M"
/// reads as money. The unit comes from the backend spec, not from a client guess.
String _fmt(num n, String unit) {
  if (unit == '%') return '${_num(n)}%';
  final a = n.abs();
  final prefix = unit == 'Rp' ? 'Rp ' : '';
  if (a >= 1e12) return '$prefix${_num(n / 1e12)} T';
  if (a >= 1e9) return '$prefix${_num(n / 1e9)} M';
  if (a >= 1e6) return '$prefix${_num(n / 1e6)} Jt';
  if (a >= 1e3) return '$prefix${_num(n / 1e3)} Rb';
  return '$prefix${_num(n, n == n.roundToDouble() ? 0 : 1)}';
}

/// Axis ticks stay terse: the unit is already stated in the legend.
String _tick(num n, String unit) {
  if (unit == '%') return '${_num(n, 0)}%';
  final a = n.abs();
  if (a >= 1e12) return '${_num(n / 1e12)}T';
  if (a >= 1e9) return '${_num(n / 1e9)}M';
  if (a >= 1e6) return '${_num(n / 1e6)}Jt';
  if (a >= 1e3) return '${_num(n / 1e3)}Rb';
  return _num(n, 0);
}

bool _isTimeName(String c) => RegExp(
    r'^(dt_id|date|period|month_id|mth_id|mth|month|week|week_id|tanggal|day)$|_(dt|date|month|week)$',
    caseSensitive: false).hasMatch(c);
bool _isIdName(String c) => RegExp(r'^(rank|ranking|no|nomor|urutan|rn)$|_id$|^id$',
    caseSensitive: false).hasMatch(c);

class _Series {
  final String column;
  final String label;
  final String unit;
  final String side;
  final bool canBeNegative;
  const _Series(this.column, this.label, this.unit, this.side, this.canBeNegative);
}

class ChartPanel extends StatefulWidget {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;

  /// Render decision from the backend (backend/app/chart_spec.py). When absent (old
  /// chat history) the widget falls back to a local heuristic.
  final Map<String, dynamic>? spec;

  const ChartPanel({super.key, required this.columns, required this.rows, this.spec});

  @override
  State<ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends State<ChartPanel> {
  String _type = '';

  double _d(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final usable = spec != null &&
        (spec['mode'] ?? 'none').toString() != 'none' &&
        (spec['series'] as List?)?.isNotEmpty == true;

    final String? category;
    final List<_Series> series;
    final String mode;
    String? title;
    String? caption;
    List<Map<String, dynamic>> rows = widget.rows;

    if (usable) {
      category = spec['category']?.toString();
      mode = spec['mode'].toString();
      title = spec['title']?.toString();
      caption = spec['caption']?.toString();
      series = [
        for (final s in (spec['series'] as List))
          _Series(
            (s as Map)['column'].toString(),
            (s['label'] ?? s['column']).toString(),
            (s['unit'] ?? '').toString(),
            (s['axis_side'] ?? 'left').toString(),
            s['can_be_negative'] == true,
          ),
      ];
      // When the result had more categories than fit as bars, the backend sends the
      // ranked subset it wants plotted, so the chart matches its own caption.
      final specRows = spec['rows'] as List?;
      if (specRows != null && specRows.isNotEmpty) {
        rows = specRows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } else {
      final local = _fallback();
      if (local == null) return const SizedBox.shrink();
      category = local.$1;
      series = local.$2;
      mode = local.$3;
    }

    if (rows.isEmpty || category == null || series.isEmpty) {
      return const SizedBox.shrink();
    }

    final avail = <String>{
      if (mode == 'line') 'line',
      if (mode == 'funnel') 'funnel',
      if (mode == 'pie') 'pie',
      'bar',
    }.toList();
    final active = avail.contains(_type) ? _type : avail.first;

    final left = series.where((s) => s.side != 'right').toList();
    final right = series.where((s) => s.side == 'right').toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.vWhite,
        border: Border.all(color: context.vRule),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title ?? 'Visualisasi',
                    style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                        fontSize: 14, color: context.vInk)),
                if (caption != null && caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(caption,
                        style: TextStyle(fontSize: 11, color: context.vMute)),
                  ),
              ]),
            ),
            for (final t in avail) _switchBtn(t, active),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 240,
            child: active == 'line'
                ? _line(category, left, right, rows)
                : active == 'pie'
                    ? _pie(category, series.first, rows)
                    : active == 'funnel'
                        ? _funnel(series, rows)
                        : _bar(category, left, right, rows),
          ),
          if (series.length > 1 && active != 'pie') ...[
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 4, children: [
              for (int i = 0; i < series.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: _series[i % _series.length], shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(
                    series[i].unit.isEmpty
                        ? series[i].label
                        : '${series[i].label} (${series[i].unit})',
                    style: TextStyle(fontSize: 11, color: context.vMute),
                  ),
                ]),
            ]),
          ],
        ],
      ),
    );
  }

  /// Local classification for results rendered before the backend sent specs.
  (String?, List<_Series>, String)? _fallback() {
    final rows = widget.rows;
    if (rows.isEmpty) return null;
    final sample = rows.take(30).toList();
    final numCols = <String>[];
    final catCols = <String>[];
    for (final c in widget.columns) {
      final vals = sample.map((r) => r[c]).where((v) => v != null).toList();
      final allNum = vals.isNotEmpty && vals.every((v) => v is num);
      // Never plot an identifier or a period: numeric does not mean quantity.
      if (allNum && !_isIdName(c) && !_isTimeName(c)) {
        numCols.add(c);
      } else {
        catCols.add(c);
      }
    }
    if (numCols.isEmpty) return null;
    final timeCol = widget.columns.where(_isTimeName).cast<String?>().firstWhere(
        (c) => rows.map((r) => r[c]).toSet().length > 1, orElse: () => null);
    final cat = timeCol ??
        (catCols.where((c) => !_isTimeName(c)).isNotEmpty
            ? catCols.firstWhere((c) => !_isTimeName(c))
            : (catCols.isNotEmpty ? catCols.first : null));
    if (cat == null) return null;
    if (timeCol == null && rows.length > 60) return null;
    final series = [
      for (final c in numCols.take(6)) _Series(c, c, '', 'left', false),
    ];
    return (cat, series, timeCol != null ? 'line' : 'bar');
  }

  Widget _switchBtn(String t, String active) {
    final on = t == active;
    final label = t == 'line'
        ? 'Line'
        : t == 'bar'
            ? 'Bar'
            : t == 'funnel'
                ? 'Funnel'
                : 'Pie';
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: () => setState(() => _type = t),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: on ? IOH.red : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: on ? IOH.red : context.vRule),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: on ? Colors.white : context.vMute, fontFamily: 'Poppins')),
        ),
      ),
    );
  }

  /// Independent scale per axis: a percentage plotted on a rupiah scale disappears
  /// into the baseline, which is the most common way these charts misled.
  (double, double) _scale(List<_Series> group, List<Map<String, dynamic>> rows) {
    double maxV = 0, minV = 0;
    for (final r in rows) {
      for (final s in group) {
        final v = _d(r[s.column]);
        if (v > maxV) maxV = v;
        if (v < minV) minV = v;
      }
    }
    final needsZero = group.any((s) => s.canBeNegative) || minV < 0;
    return (needsZero ? minV * 1.1 : 0, maxV <= 0 ? 1 : maxV * 1.15);
  }

  Widget _bar(String cat, List<_Series> left, List<_Series> right,
      List<Map<String, dynamic>> rows) {
    final data = rows.take(24).toList();
    final all = [...left, ...right];
    final (lMin, lMax) = _scale(left.isEmpty ? all : left, data);
    final (rMin, rMax) = right.isEmpty ? (0.0, 1.0) : _scale(right, data);
    final leftUnit = left.isNotEmpty ? left.first.unit : (all.isNotEmpty ? all.first.unit : '');
    final rightUnit = right.isNotEmpty ? right.first.unit : '';

    // fl_chart draws one shared axis, so right-axis series are normalised onto the
    // left scale and their real values shown in the tooltip and the labels.
    double project(double v, bool isRight) {
      if (!isRight || right.isEmpty) return v;
      final t = (rMax - rMin) == 0 ? 0.0 : (v - rMin) / (rMax - rMin);
      return lMin + t * (lMax - lMin);
    }

    return BarChart(BarChartData(
      minY: lMin,
      maxY: lMax,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(getTooltipItem: (g, gi, r, ri) {
          final s = all[ri.clamp(0, all.length - 1)];
          final real = _d(data[g.x.toInt()][s.column]);
          return BarTooltipItem(
              '${data[g.x.toInt()][cat]}\n${s.label}: ${_fmt(real, s.unit)}',
              const TextStyle(color: Colors.white, fontSize: 11));
        }),
      ),
      gridData: FlGridData(
          show: true, drawVerticalLine: false,
          horizontalInterval: (lMax - lMin) / 4 == 0 ? 1 : (lMax - lMin) / 4,
          getDrawingHorizontalLine: (v) => FlLine(color: context.vRule, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 44,
                getTitlesWidget: (v, _) => Text(_tick(v, leftUnit),
                    style: TextStyle(fontSize: 10, color: context.vMute)))),
        rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: right.isNotEmpty, reservedSize: 44,
                getTitlesWidget: (v, _) {
          if (right.isEmpty || (lMax - lMin) == 0) return const SizedBox();
          final t = (v - lMin) / (lMax - lMin);
          return Text(_tick(rMin + t * (rMax - rMin), rightUnit),
              style: TextStyle(fontSize: 10, color: context.vMute));
        })),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 34,
                getTitlesWidget: (v, _) {
          final i = v.toInt();
          if (i < 0 || i >= data.length) return const SizedBox();
          final lbl = data[i][cat].toString();
          return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(lbl.length > 6 ? lbl.substring(0, 6) : lbl,
                  style: TextStyle(fontSize: 9, color: context.vMute)));
        })),
      ),
      barGroups: [
        for (int i = 0; i < data.length; i++)
          BarChartGroupData(x: i, barRods: [
            for (int si = 0; si < all.length; si++)
              BarChartRodData(
                toY: project(_d(data[i][all[si].column]), all[si].side == 'right'),
                color: all.length == 1 ? IOH.red : _series[si % _series.length],
                width: all.length == 1 ? 14 : (14 / all.length).clamp(4, 14).toDouble(),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
          ]),
      ],
    ));
  }

  Widget _line(String cat, List<_Series> left, List<_Series> right,
      List<Map<String, dynamic>> rows) {
    final sorted = [...rows]
      ..sort((a, b) => a[cat].toString().compareTo(b[cat].toString()));
    final all = [...left, ...right];
    final (minV, maxV) = _scale(all, sorted);
    final unit = all.isNotEmpty ? all.first.unit : '';
    return LineChart(LineChartData(
      minY: minV,
      maxY: maxV,
      gridData: FlGridData(
          show: true, drawVerticalLine: false,
          horizontalInterval: (maxV - minV) / 4 == 0 ? 1 : (maxV - minV) / 4,
          getDrawingHorizontalLine: (v) => FlLine(color: context.vRule, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(getTooltipItems: (items) => items
              .map((it) => LineTooltipItem(
                  _fmt(it.y, all[it.barIndex % all.length].unit),
                  TextStyle(
                      color: _series[it.barIndex % _series.length],
                      fontWeight: FontWeight.w700, fontSize: 11)))
              .toList())),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 46,
                getTitlesWidget: (v, _) => Text(_tick(v, unit),
                    style: TextStyle(fontSize: 10, color: context.vMute)))),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 30,
                interval: (sorted.length / 6).ceilToDouble().clamp(1, 999),
                getTitlesWidget: (v, _) {
          final i = v.toInt();
          if (i < 0 || i >= sorted.length) return const SizedBox();
          var lbl = sorted[i][cat].toString();
          if (lbl.length > 6) lbl = lbl.substring(lbl.length - 5);
          return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(lbl, style: TextStyle(fontSize: 9, color: context.vMute)));
        })),
      ),
      lineBarsData: [
        for (int si = 0; si < all.length; si++)
          LineChartBarData(
            isCurved: false,
            color: _series[si % _series.length],
            barWidth: 2.5,
            dotData: FlDotData(
                show: sorted.length <= 31,
                getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                    radius: 2.5, color: Colors.white,
                    strokeColor: _series[si % _series.length], strokeWidth: 2)),
            spots: [
              for (int i = 0; i < sorted.length; i++)
                FlSpot(i.toDouble(), _d(sorted[i][all[si].column])),
            ],
          ),
      ],
    ));
  }

  /// Conversion stages with the drop-off between them, which is the whole point of
  /// a funnel: plotting only the first stage hid the conversion entirely.
  Widget _funnel(List<_Series> series, List<Map<String, dynamic>> rows) {
    final stages = [
      for (final s in series)
        (s.label, s.unit, rows.fold<double>(0, (a, r) => a + _d(r[s.column]))),
    ];
    final top = stages.isEmpty || stages.first.$3 == 0 ? 1.0 : stages.first.$3;
    return ListView(
      children: [
        for (int i = 0; i < stages.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(
                  width: 96,
                  child: Text(stages[i].$1,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: context.vInk),
                      overflow: TextOverflow.ellipsis)),
              Expanded(
                child: Stack(alignment: Alignment.centerLeft, children: [
                  Container(height: 30,
                      decoration: BoxDecoration(
                          color: context.vRule.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(4))),
                  FractionallySizedBox(
                    widthFactor: (stages[i].$3 / top).clamp(0.02, 1.0),
                    child: Container(height: 30,
                        decoration: BoxDecoration(
                            color: _series[i % _series.length],
                            borderRadius: BorderRadius.circular(4))),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(_fmt(stages[i].$3, stages[i].$2),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ]),
              ),
              SizedBox(
                width: 58,
                child: Text(
                  i == 0
                      ? '100%'
                      : '${_num(stages[i].$3 / (stages[i - 1].$3 == 0 ? 1 : stages[i - 1].$3) * 100, 1)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: context.vMute),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _pie(String cat, _Series s, List<Map<String, dynamic>> rows) {
    final data = rows.where((r) => _d(r[s.column]) > 0).take(8).toList();
    final total = data.fold<double>(0, (a, r) => a + _d(r[s.column]));
    return Row(children: [
      Expanded(
        flex: 2,
        child: PieChart(PieChartData(
          centerSpaceRadius: 50,
          sectionsSpace: 2,
          sections: [
            for (int i = 0; i < data.length; i++)
              PieChartSectionData(
                  value: _d(data[i][s.column]),
                  color: _series[i % _series.length],
                  radius: 50,
                  title: total == 0
                      ? ''
                      : '${(_d(data[i][s.column]) / total * 100).toStringAsFixed(0)}%',
                  titleStyle: const TextStyle(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ],
        )),
      ),
      Expanded(
        flex: 2,
        child: ListView(
          children: [
            for (int i = 0; i < data.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Container(width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: _series[i % _series.length], shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(data[i][cat].toString(),
                          style: TextStyle(fontSize: 11, color: context.vInk),
                          overflow: TextOverflow.ellipsis)),
                  Text(_fmt(_d(data[i][s.column]), s.unit),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: context.vMute)),
                ]),
              ),
          ],
        ),
      ),
    ]);
  }
}
