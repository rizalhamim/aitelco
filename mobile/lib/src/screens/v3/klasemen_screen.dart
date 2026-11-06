// v3 03 Klasemen (design/mockup-v3/features/03-klasemen.html, Android): fair
// ranking by achievement or growth, podium, my position highlighted, and the
// middle of the table folded into one "Lihat semua" row.
import 'package:flutter/material.dart';

import '../../ui/mock_icons.dart';
import '../../ui/v2.dart';
import '../../ui/v3.dart';
import 'diagnosa_screen.dart';
import 'v3_nav.dart';

const _levels = [('region', 'Region'), ('kabupaten', 'Kab/kota'), ('kecamatan', 'Kec.')];
const _levelTitle = {'region': 'Region', 'kabupaten': 'Kabupaten', 'kecamatan': 'Kecamatan'};
const _metrics = [('revenue', 'Revenue', 'wallet'), ('payload', 'Payload', 'db'), ('subs', 'RGU 90D', 'users'), ('rev_site', 'Revenue per site', 'tower'), ('availability', 'Availability', 'pulse')];

class KlasemenScreen extends StatefulWidget {
  const KlasemenScreen({super.key, this.preview, this.level = 'kabupaten', this.metric = 'revenue'});
  final Map<String, dynamic>? preview;
  final String level, metric;

  @override
  State<KlasemenScreen> createState() => _KlasemenScreenState();
}

class _KlasemenScreenState extends State<KlasemenScreen> {
  late String _level = widget.level, _metric = widget.metric;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final basis = p == null ? 'MTD' : ((p['basis'] as Map?)?['kind'] == 'mtd' ? 'MTD' : 'Bulan penuh');
    final mLabel = _metrics.firstWhere((m) => m.$1 == _metric, orElse: () => _metrics.first);
    return V3Page(
      title: 'Klasemen',
      subtitle: '${_levelTitle[_level]} · ${mLabel.$2} · $basis',
      body: V3Loader(
        path: '/api/klasemen',
        query: {'level': _level, 'metric': _metric, 'sort': 'achievement'},
        preview: p,
        builder: (context, d, reload) => RefreshIndicator(onRefresh: reload, color: V2.teal600, child: _body(d, mLabel)),
      ),
    );
  }

  Widget _body(Map<String, dynamic> d, (String, String, String) m) {
    final rows = [for (final r in (d['rows'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    final best = [for (final r in (d['best'] as List? ?? const [])) Map<String, dynamic>.from(r as Map)];
    final src = (d['source'] as Map?)?['short']?.toString();
    final basis = ((d['basis'] as Map?)?['label'] ?? '').toString();
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      children: [
        Row(children: [
          V3Seg(options: _levels, selected: _level, white: true, padX: 9, onTap: (v) => setState(() { _level = v; _all = false; })),
          const Spacer(),
          V3Chip(label: m.$2, icon: m.$3, teal: true, height: 32, onTap: _pickMetric),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const MIcon('cal', size: 13, color: V2.teal600),
          const SizedBox(width: 6),
          Expanded(child: Text(src == null ? basis : '$basis · $src', style: V2.d(11, FontWeight.w500, V2.mute, lh: 1.3))),
        ]),
        if (best.length >= 3) ...[const SizedBox(height: 10), _podium(best)],
        if (rows.isNotEmpty) ...[const SizedBox(height: 10), _table(rows, d)],
      ],
    );
  }

  Future<void> _pickMetric() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final m in _metrics)
            ListTile(
              leading: MIcon(m.$3, size: 18, color: V2.teal700),
              title: Text(m.$2, style: V2.d(14, m.$1 == _metric ? FontWeight.w700 : FontWeight.w500, V2.ink)),
              trailing: m.$1 == _metric ? const MIcon('check', size: 18, color: V2.teal600) : null,
              onTap: () => Navigator.pop(c, m.$1),
            ),
        ]),
      ),
    );
    if (v != null && v != _metric) setState(() { _metric = v; _all = false; });
  }

  Widget _podium(List<Map<String, dynamic>> best) {
    Widget pd(Map<String, dynamic> r, int place) {
      final first = place == 1;
      return GestureDetector(
        onTap: () => _open(r),
        child: Container(
          padding: EdgeInsets.fromLTRB(8, first ? 16 : 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: first ? const Color(0xFFE2F9A8) : V2.rule),
            gradient: first ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF4FCE3), Colors.white]) : null,
            color: first ? null : Colors.white,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: first ? V2.lime : const Color(0xFFE6F4EA)),
              child: Text('$place', style: V2.d(14, FontWeight.w800, first ? const Color(0xFF2F4A08) : V3.green, lh: 1)),
            ),
            const SizedBox(height: 4),
            Text('${r['name']}', textAlign: TextAlign.center, style: V2.d(12.5, FontWeight.w600, V2.ink, lh: 1.2)),
            const SizedBox(height: 4),
            Text('${r['ach_label']}', style: V2.d(16, FontWeight.w800, V2.ink, lh: 1)),
            const SizedBox(height: 4),
            Text('${r['growth_label']} · ${r['abs_label']}', textAlign: TextAlign.center, style: V2.d(10.5, FontWeight.w500, V2.mute, lh: 1.2)),
          ]),
        ),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(flex: 100, child: pd(best[1], 2)),
      const SizedBox(width: 8),
      Expanded(flex: 115, child: pd(best[0], 1)),
      const SizedBox(width: 8),
      Expanded(flex: 100, child: pd(best[2], 3)),
    ]);
  }

  Widget _table(List<Map<String, dynamic>> rows, Map<String, dynamic> d) {
    final rest = rows.where((r) => (r['rank'] as num) > 3).toList();
    final total = (d['total'] as num?)?.toInt() ?? rows.length;
    final shown = <Map<String, dynamic>?>[];
    if (_all || rest.length <= 6) {
      shown.addAll(rest);
    } else {
      final top = rest.take(3).toList(), bottom = rest.sublist(rest.length - 2);
      final mine = rest.where((r) => r['mine'] == true && !top.contains(r) && !bottom.contains(r)).toList();
      shown
        ..addAll(top)
        ..add(null)
        ..addAll(mine)
        ..addAll(bottom);
    }
    String gapLabel(int i) {
      final a = (shown[i - 1]!['rank'] as num).toInt() + 1;
      final b = i + 1 < shown.length ? (shown[i + 1]!['rank'] as num).toInt() - 1 : total;
      return 'Peringkat $a sampai $b · Lihat semua';
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: V3.card(radius: 18),
      child: Column(children: [
        for (var i = 0; i < shown.length; i++)
          if (shown[i] == null)
            GestureDetector(
              onTap: () => setState(() => _all = true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: const BoxDecoration(color: Color(0xFFFBFDFC), border: Border(bottom: BorderSide(color: V2.rule2))),
                child: Text(gapLabel(i),
                    textAlign: TextAlign.center, style: V2.d(11.5, FontWeight.w500, V2.mute, lh: 1)),
              ),
            )
          else
            _row(shown[i]!, last: i == shown.length - 1),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> r, {bool last = false}) {
    final ach = (r['achievement_pct'] as num?)?.toDouble();
    final move = (r['move'] as num?)?.toInt() ?? 0;
    final color = ach == null ? V2.rule : ach >= 100 ? V3.green2 : ach >= 94 ? V3.amber : V2.red;
    final mine = r['mine'] == true;
    final nameStyle = V2.d(13, FontWeight.w600, V2.ink, lh: 1.2);
    final row = GestureDetector(
      onTap: () => _open(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFFFF8F5) : Colors.white,
          border: Border(bottom: last ? BorderSide.none : const BorderSide(color: V2.rule2)),
        ),
        child: Row(children: [
          SizedBox(
              width: 30,
              child: Column(children: [
                Text('${r['rank']}', style: V2.d(13, FontWeight.w700, V2.ink, lh: 1)),
                const SizedBox(height: 3),
                V3Move(move, size: 9.5),
              ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: '${r['name']}', style: nameStyle),
                  if (r['small_base'] == true) ...[
                    TextSpan(text: ' ', style: nameStyle),
                    ...v3InlinePill('Basis kecil', style: V2.d(10, FontWeight.w600, const Color(0xFFB7791F), lh: 1), bg: const Color(0xFFFDF3E2)),
                  ],
                ]),
                // the name sits in a 16 px Prompt line box, 24.2 px tall in Chrome (hhea ascent + descent)
                strutStyle: const StrutStyle(fontFamily: V2.body, fontSize: 16, height: 1.5125, forceStrutHeight: true, leadingDistribution: TextLeadingDistribution.even),
              ),
              const SizedBox(height: 6),
              V3Bullet(fraction: (ach ?? 0) * .8 / 100, color: color),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${r['ach_label'] ?? '–'}', style: V2.d(12.5, FontWeight.w700, V2.ink, lh: 1.2)),
              Text('${r['growth_label']} · ${r['abs_label']}', textAlign: TextAlign.right, style: V2.d(10.5, FontWeight.w500, V2.mute, lh: 1.25)),
            ]),
          ),
        ]),
      ),
    );
    if (!mine) return row;
    // CSS inset box-shadow: a 4 px coral bar over the row, content does not move
    return Stack(children: [row, const Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: V2.coral))]);
  }

  void _open(Map<String, dynamic> r) {
    final metric = const ['revenue', 'payload', 'subs'].contains(_metric) ? _metric : 'revenue';
    final key = r['key']?.toString() ?? '';
    V3Nav.push(
      context,
      DiagnosaScreen(
        metric: metric,
        region: _level == 'region' ? key : (r['region']?.toString() ?? ''),
        kabupaten: _level == 'kabupaten' ? key : '',
      ),
    );
  }
}
