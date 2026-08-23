import 'package:flutter/material.dart';
import '../format/report_format.dart';
import '../theme.dart';

String fmtCell(dynamic v) {
  if (v == null) return kReportNotAvailable;
  if (v is int) return reportNumber(v);
  if (v is double) {
    if (v == v.roundToDouble()) return reportNumber(v.round());
    return reportNumber(v, decimals: 2);
  }
  return v.toString();
}

bool _isNumCol(String c, List<Map<String, dynamic>> rows) {
  final vals = rows.take(20).map((r) => r[c]).where((v) => v != null);
  return vals.isNotEmpty && vals.every((v) => v is num);
}

/// Polished, horizontally-scrollable table with fixed column widths (no ugly wrap).
class DataTableView extends StatelessWidget {
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final int maxRows;
  const DataTableView({super.key, required this.columns, required this.rows, this.maxRows = 100});

  @override
  Widget build(BuildContext context) {
    final show = rows.take(maxRows).toList();
    final numCols = {for (final c in columns) c: _isNumCol(c, rows)};
    final headStyle = TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: context.vMute, letterSpacing: 0.4);
    final cellStyle = TextStyle(fontSize: 12.5, color: context.vInk, fontFeatures: const [FontFeature.tabularFigures()]);

    Widget cellBox(Widget child, bool num) => Container(
          width: 132,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          alignment: num ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        );

    return Container(
      decoration: BoxDecoration(
        color: context.vWhite,
        border: Border.all(color: context.vRule),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // header row, 2px ink bottom border per design rule
                Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.vInk, width: 2))),
                  child: Row(children: [
                    for (final c in columns)
                      cellBox(Text(c.toUpperCase(), style: headStyle, maxLines: 1, overflow: TextOverflow.ellipsis), numCols[c]!),
                  ]),
                ),
                for (int i = 0; i < show.length; i++)
                  Container(
                    decoration: BoxDecoration(
                      color: i.isOdd ? context.vPanel : Colors.transparent,
                      border: Border(bottom: BorderSide(color: context.vRule, width: 0.6)),
                    ),
                    child: Row(children: [
                      for (final c in columns)
                        cellBox(Text(fmtCell(show[i][c]), style: cellStyle, maxLines: 1, overflow: TextOverflow.ellipsis), numCols[c]!),
                    ]),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Text('${rows.length} baris${rows.length > maxRows ? " · tampil $maxRows" : ""} · geser untuk lihat kolom lain',
                style: TextStyle(fontSize: 10.5, color: context.vMute)),
          ),
        ],
      ),
    );
  }
}
