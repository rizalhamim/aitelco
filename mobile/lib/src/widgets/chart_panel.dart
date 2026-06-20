import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme.dart';

const _series = [
  IOH.teal500, Color(0xFFF5A623), Color(0xFF2A74D4), Color(0xFFFF6B35),
  IOH.teal700, Color(0xFF9A6CFF), IOH.green, Color(0xFF0EA5E9),
];

String _short(num n) {
  final a = n.abs();
  if (a >= 1e12) return '${(n / 1e12).toStringAsFixed(1)}T';
  if (a >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (a >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (a >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
  return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
}

bool _isTimeName(String c) => RegExp(r'^(dt_id|date|period|month_id|mth_id|mth|month|week|week_id|tanggal|day)$|_(dt|date|month|week)$', caseSensitive: false).hasMatch(c);

class ChartPanel extends StatefulWidget {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  const ChartPanel({super.key, required this.columns, required this.rows});

  @override
  State<ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends State<ChartPanel> {
  String _type = '';

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    // classify columns from a sample
    final sample = rows.take(30).toList();
    final numCols = <String>[];
    final catCols = <String>[];
    for (final c in widget.columns) {
      final vals = sample.map((r) => r[c]).where((v) => v != null).toList();
      final allNum = vals.isNotEmpty && vals.every((v) => v is num);
      if (allNum) { numCols.add(c); } else { catCols.add(c); }
    }
    if (numCols.isEmpty) return const SizedBox.shrink();
    String? timeCol;
    for (final c in widget.columns) {
      if (_isTimeName(c)) { timeCol = c; break; }
    }
    final cat = timeCol ?? (catCols.isNotEmpty ? catCols.first : null);
    if (cat == null) return const SizedBox.shrink();
    if (timeCol == null && rows.length > 60) return const SizedBox.shrink();

    final avail = <String>[];
    if (timeCol != null) avail.add('line');
    avail.add('bar');
    if (numCols.length == 1 && rows.length <= 12) avail.add('pie');
    final active = avail.contains(_type) ? _type : avail.first;

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
            Text('Visualisasi', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14, color: context.vInk)),
            const Spacer(),
            for (final t in avail) _switchBtn(t, active),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 240,
            child: active == 'line'
                ? _line(cat, numCols, rows, timeCol != null)
                : active == 'pie'
                    ? _pie(cat, numCols.first, rows)
                    : _bar(cat, numCols.first, rows),
          ),
          if (numCols.length > 1 && active == 'line') ...[
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 4, children: [
              for (int i = 0; i < numCols.take(6).length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: _series[i % 6], shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(numCols[i], style: TextStyle(fontSize: 11, color: context.vMute)),
                ]),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _switchBtn(String t, String active) {
    final on = t == active;
    final label = t == 'line' ? 'Line' : t == 'bar' ? 'Bar' : 'Pie';
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
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: on ? Colors.white : context.vMute, fontFamily: 'Poppins')),
        ),
      ),
    );
  }

  double _d(dynamic v) => v is num ? v.toDouble() : (double.tryParse(v?.toString() ?? '') ?? 0);

  Widget _bar(String cat, String numCol, List<Map<String, dynamic>> rows) {
    final data = rows.take(24).toList();
    final maxV = data.map((r) => _d(r[numCol])).fold<double>(0, (a, b) => b > a ? b : a);
    return BarChart(BarChartData(
      maxY: maxV * 1.15,
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(getTooltipItem: (g, gi, r, ri) =>
            BarTooltipItem('${data[g.x.toInt()][cat]}\n${_short(r.toY)}', const TextStyle(color: Colors.white, fontSize: 11))),
      ),
      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxV / 4, getDrawingHorizontalLine: (v) => FlLine(color: context.vRule, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, _) => Text(_short(v), style: TextStyle(fontSize: 10, color: context.vMute)))),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34, getTitlesWidget: (v, _) {
          final i = v.toInt();
          if (i < 0 || i >= data.length) return const SizedBox();
          final lbl = data[i][cat].toString();
          return Padding(padding: const EdgeInsets.only(top: 4), child: Text(lbl.length > 6 ? lbl.substring(0, 6) : lbl, style: TextStyle(fontSize: 9, color: context.vMute)));
        })),
      ),
      barGroups: [
        for (int i = 0; i < data.length; i++)
          BarChartGroupData(x: i, barRods: [BarChartRodData(toY: _d(data[i][numCol]), color: IOH.red, width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(2)))]),
      ],
    ));
  }

  Widget _line(String cat, List<String> numCols, List<Map<String, dynamic>> rows, bool isTime) {
    final sorted = [...rows]..sort((a, b) => a[cat].toString().compareTo(b[cat].toString()));
    final series = numCols.take(6).toList();
    double maxV = 0, minV = 0;
    for (final r in sorted) { for (final s in series) { final v = _d(r[s]); if (v > maxV) maxV = v; if (v < minV) minV = v; } }
    return LineChart(LineChartData(
      minY: minV, maxY: maxV * 1.1,
      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: (maxV - minV) / 4 == 0 ? 1 : (maxV - minV) / 4, getDrawingHorizontalLine: (v) => FlLine(color: context.vRule, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
        getTooltipItems: (items) => items.map((it) => LineTooltipItem(_short(it.y), TextStyle(color: _series[it.barIndex % 6], fontWeight: FontWeight.w700, fontSize: 11))).toList())),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 42, getTitlesWidget: (v, _) => Text(_short(v), style: TextStyle(fontSize: 10, color: context.vMute)))),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: (sorted.length / 6).ceilToDouble().clamp(1, 999), getTitlesWidget: (v, _) {
          final i = v.toInt();
          if (i < 0 || i >= sorted.length) return const SizedBox();
          var lbl = sorted[i][cat].toString();
          if (lbl.length > 6) lbl = lbl.substring(lbl.length - 5);
          return Padding(padding: const EdgeInsets.only(top: 4), child: Text(lbl, style: TextStyle(fontSize: 9, color: context.vMute)));
        })),
      ),
      lineBarsData: [
        for (int si = 0; si < series.length; si++)
          LineChartBarData(
            isCurved: false, color: _series[si % 6], barWidth: 2.5,
            dotData: FlDotData(show: sorted.length <= 31, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 2.5, color: Colors.white, strokeColor: _series[si % 6], strokeWidth: 2)),
            spots: [for (int i = 0; i < sorted.length; i++) FlSpot(i.toDouble(), _d(sorted[i][series[si]]))],
          ),
      ],
    ));
  }

  Widget _pie(String cat, String numCol, List<Map<String, dynamic>> rows) {
    final data = rows.where((r) => _d(r[numCol]) > 0).take(8).toList();
    final total = data.fold<double>(0, (a, r) => a + _d(r[numCol]));
    return Row(children: [
      Expanded(
        flex: 2,
        child: PieChart(PieChartData(
          centerSpaceRadius: 50, sectionsSpace: 2,
          sections: [
            for (int i = 0; i < data.length; i++)
              PieChartSectionData(value: _d(data[i][numCol]), color: _series[i % 6], radius: 50,
                  title: '${(_d(data[i][numCol]) / total * 100).toStringAsFixed(0)}%',
                  titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ],
        )),
      ),
      Expanded(
        flex: 2,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (int i = 0; i < data.length; i++)
            Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: _series[i % 6], shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(data[i][cat].toString(), style: TextStyle(fontSize: 11, color: context.vInk), overflow: TextOverflow.ellipsis)),
            ])),
        ]),
      ),
    ]);
  }
}
