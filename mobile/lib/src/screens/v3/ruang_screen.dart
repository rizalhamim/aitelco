// v3 04 Ruang Saya (design/mockup-v3/features/04-ruang-saya.html, Android):
// personal and team boards of pinned answers that refresh with every dump.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../api/api_client.dart';
import '../../ui/mock_icons.dart';
import '../../ui/v2.dart';
import '../../ui/v3.dart';
import 'v3_nav.dart';

const _srcLabel = {'chart': ('c', 'Grafik'), 'table': ('t', 'Tabel'), 'map': ('m', 'Peta'), 'kpi': ('k', 'KPI'), 'notes': ('n', 'Catatan'), 'answer': ('t', 'Jawaban')};
const _srcTone = {
  'c': (Color(0xFFE3F7FA), Color(0xFF0E6F7C)),
  't': (Color(0xFFFCEDD3), Color(0xFF8F5A10)),
  'm': (Color(0xFFF4FCE3), Color(0xFF5E8A12)),
  'k': (Color(0xFFE6F7F5), Color(0xFF0A6A5F)),
  'n': (Color(0xFFECE5FA), Color(0xFF6A4CB5)),
};

class RuangScreen extends StatefulWidget {
  const RuangScreen({super.key, this.previewBoards, this.previewBoard});
  final Map<String, dynamic>? previewBoards;
  final Map<String, dynamic>? previewBoard;

  @override
  State<RuangScreen> createState() => _RuangScreenState();
}

class _RuangScreenState extends State<RuangScreen> {
  List<Map<String, dynamic>> _boards = const [];
  Map<String, dynamic>? _board;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.previewBoards != null) {
      _boards = _list(widget.previewBoards!['boards']);
      _board = widget.previewBoard;
    } else {
      _load();
    }
  }

  List<Map<String, dynamic>> _list(Object? l) => [for (final x in (l as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

  Future<void> _load([int? id]) async {
    try {
      final b = await ApiClient.v3Get('/api/ruang/boards');
      final boards = _list(b['boards']);
      final pick = id ?? (_board?['id'] as int?) ?? (boards.isNotEmpty ? boards.first['id'] as int : null);
      final board = pick == null ? null : await ApiClient.v3Get('/api/ruang/boards/$pick');
      if (mounted) setState(() { _boards = boards; _board = board; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _board;
    final pins = _list(b?['pins'])..sort((x, y) => ((x['col'] as num) * 1000 + (x['position'] as num)).compareTo((y['col'] as num) * 1000 + (y['position'] as num)));
    return V3Page(
      title: 'Ruang Saya',
      subtitle: b == null ? 'Papan pantauan' : '${b['name']} · ${pins.length} pin',
      fab: _fab(),
      body: b == null
          ? (_error != null ? V3Message(text: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator(color: V2.teal600)))
          : RefreshIndicator(
              onRefresh: _load,
              color: V2.teal600,
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 90), children: [
                _boardChips(b),
                const SizedBox(height: 10),
                _fresh(b),
                for (final p in pins) ...[const SizedBox(height: 10), _pin(p)],
                if (pins.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 30),
                    child: Text('Papan ini masih kosong. Pin jawaban dari Tanya Agent, Diagnosa, atau Brief Pagi.',
                        textAlign: TextAlign.center, style: V2.b(13, FontWeight.w400, V2.mute, lh: 1.45)),
                  ),
              ]),
            ),
    );
  }

  Widget _fab() => Semantics(
        button: true,
        child: GestureDetector(
          onTap: () => V3Nav.tab(context, 0),
          child: LayoutBuilder(builder: (context, c) {
            return Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: cssLinear(135, const [V2.teal600, Color(0xFF1597A8)], const Size(164, 52)),
                boxShadow: [cssShadow(const Color(0x590E8579), 0, 14, 30)],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const MIcon('spark', size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text('Tanya dan pin', style: V2.d(14, FontWeight.w600, Colors.white, lh: 1)),
              ]),
            );
          }),
        ),
      );

  Widget _boardChips(Map<String, dynamic> b) {
    Widget chip(String label, bool on, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: on ? V2.teal600 : Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: on ? V2.teal600 : V2.rule)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: V2.d(12, FontWeight.w600, on ? Colors.white : V2.ink2, lh: 1)),
            ]),
          ),
        );
    return SizedBox(
      height: 32,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final x in _boards) ...[
          chip('${x['name']}', x['id'] == b['id'], () => widget.previewBoards == null ? _load(x['id'] as int) : null),
          const SizedBox(width: 6),
        ],
        chip('+ Papan', false, _newBoard),
      ]),
    );
  }

  Future<void> _newBoard() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Papan baru', style: V2.d(16, FontWeight.w700, V2.ink)),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Contoh: Rapat Senin')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Buat')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final r = await ApiClient.v3Send('POST', '/api/ruang/boards', {'name': name});
      await _load(((r['board'] ?? r) as Map)['id'] as int?);
    } catch (e) {
      if (mounted) v3Toast(context, 'Papan gagal dibuat');
    }
  }

  Widget _fresh(Map<String, dynamic> b) {
    final fresh = (b['fresh'] as Map?) ?? const {};
    final members = _list(b['members']).take(3).toList();
    return Row(children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(color: fresh['ok'] == false ? V3.amber : V3.green2, shape: BoxShape.circle)),
      const SizedBox(width: 7),
      Expanded(child: Text('${fresh['label'] ?? ''}', style: V2.d(11, FontWeight.w500, V2.ink2, lh: 1.3))),
      SizedBox(
        width: 24.0 + (members.length - 1) * 16,
        height: 24,
        child: Stack(children: [
          for (var i = 0; i < members.length; i++)
            Positioned(
              left: i * 16.0,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: V3.hex(members[i]['color']?.toString()), shape: BoxShape.circle, border: Border.all(color: V2.bg, width: 2)),
                child: Text('${members[i]['initial']}', style: V2.d(9.5, FontWeight.w700, Colors.white, lh: 1)),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _pin(Map<String, dynamic> p) {
    final data = Map<String, dynamic>.from(p['data'] as Map? ?? const {});
    final spec = Map<String, dynamic>.from(p['spec'] as Map? ?? const {});
    final type = spec['type']?.toString();
    final kids = <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['title']}', style: V2.d(14.5, FontWeight.w600, V2.ink, lh: 1.3)),
            if (p['subtitle'] != null) ...[
              const SizedBox(height: 2),
              Text(_subtitle(p['subtitle'].toString()), style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3)),
            ],
          ]),
        ),
        if (data['status'] != 'unavailable')
          GestureDetector(
            onTap: () => _menu(p),
            child: Container(width: 28, height: 28, alignment: Alignment.center, child: const MIcon('dots', size: 16, color: V2.mute)),
          ),
      ]),
      ..._body(type, data, p),
    ];
    final src = _srcLabel[p['kind']];
    if (src != null && type != 'notes' && data['status'] != 'unavailable' && type != 'kpi_watch') {
      final tone = _srcTone[src.$1]!;
      final origin = (p['origin_label'] ?? '').toString().replaceFirst('Dari ', '').split(',').first;
      kids.add(Container(
        padding: const EdgeInsets.only(top: 10),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: V2.rule2))),
        child: Row(children: [
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: tone.$1, borderRadius: BorderRadius.circular(99)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [Text(src.$2, style: V2.d(10.5, FontWeight.w600, tone.$2, lh: 1))]),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(origin, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(11.5, FontWeight.w500, V2.mute, lh: 1.3))),
          if (p['ask'] != null)
            GestureDetector(
              onTap: () => V3Nav.ask?.call('${p['title']}: jelaskan lebih lanjut'),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const MIcon('spark', size: 14, color: V2.coral),
                const SizedBox(width: 5),
                Text('Tanya lanjut', style: V2.d(11.5, FontWeight.w600, const Color(0xFFB5401F), lh: 1.3)),
              ]),
            ),
        ]),
      ));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: V3.card(radius: 20, shadow: [cssShadow(const Color(0x0A0F1F1D), 0, 4, 14)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < kids.length; i++) ...[if (i > 0) const SizedBox(height: 8), kids[i]],
      ]),
    );
  }

  /// The web subtitle uses commas; the phone uses the middle dot.
  String _subtitle(String s) => s.replaceAll(', ', ' · ');

  List<Widget> _body(String? type, Map<String, dynamic> d, Map<String, dynamic> p) {
    if (d['status'] == 'unavailable') {
      return [
        V3Dashed(
          radius: 16,
          width: 1,
          color: const Color(0xFFE9C27A),
          fill: const Color(0xFFFDF3E2),
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: double.infinity,
            child: Column(children: [
              Text('${d['message'] ?? 'Belum tersedia'}', textAlign: TextAlign.center, style: V2.d(13, FontWeight.w600, const Color(0xFF6B4A0E), lh: 1.3)),
              const SizedBox(height: 6),
              Text('${d['detail'] ?? ''}', textAlign: TextAlign.center, style: V2.b(12, FontWeight.w400, const Color(0xFF6B4A0E), lh: 1.45)),
            ]),
          ),
        ),
      ];
    }
    switch (type) {
      case 'daily_compare':
        final g = (d['growth_pct'] as num?)?.toDouble() ?? 0;
        return [
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('${d['value_label']}', style: V2.d(26, FontWeight.w700, V2.ink, lh: 1)),
            const SizedBox(width: 10),
            Text('${d['growth_label'] ?? ''}', style: V2.d(12.5, FontWeight.w600, g < 0 ? V2.red : V3.green, lh: 1)),
          ]),
          SizedBox(
            height: 70,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: 320,
              minWidth: 320,
              child: SizedBox(width: 320, height: 70, child: CustomPaint(painter: _DailyPainter(d))),
            ),
          ),
          Row(children: [
            _lg(V2.teal600, '${d['month'] ?? ''}'),
            const SizedBox(width: 12),
            _lg(V2.lagoon, '${d['prev_month'] ?? ''}, hari yang sama'),
          ]),
        ];
      case 'kpi_watch':
        final tiles = _list(d['tiles']).take(4).toList();
        return [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 152 / 60,
            padding: EdgeInsets.zero,
            children: [
              for (final t in tiles)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${t['label']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(11.5, FontWeight.w500, V2.mute, lh: 1.2)),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${t['value']}', style: V2.d(20, FontWeight.w700, V2.ink, lh: 1.3)),
                      TextSpan(text: ' ', style: V2.d(20, FontWeight.w700, V2.ink, lh: 1.3)),
                      v3Delta('${t['delta_label'] ?? ''}', V2.d(11.5, FontWeight.w600, t['good'] == true ? V3.green : V2.red, lh: 1)),
                    ])),
                  ]),
                ),
            ],
          ),
        ];
      case 'rank_table':
        return [
          for (final r in _list(d['rows']))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text('${r['name']}', style: V2.d(12.5, FontWeight.w500, V2.ink, lh: 1.2))),
                Text('${r['pct_label']}', style: V2.d(12.5, FontWeight.w700, '${r['pct_label']}'.startsWith('+') ? V3.green : V2.red, lh: 1.2)),
                SizedBox(width: 64, child: Text('${r['abs_label']}', textAlign: TextAlign.right, style: V2.d(11.5, FontWeight.w500, V2.mute, lh: 1.2))),
              ]),
            ),
        ];
      case 'map_change':
        final w = (d['w'] as num?)?.toDouble() ?? 370, h = (d['h'] as num?)?.toDouble() ?? 150;
        final shapes = _list(d['shapes']);
        final svg = StringBuffer('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h">');
        for (final s in shapes) {
          svg.write('<path d="${s['d']}" fill="${s['fill']}" stroke="#fff" stroke-width="1.5"/>');
        }
        svg.write('</svg>');
        return [
          AspectRatio(aspectRatio: w / h, child: SvgPicture.string(svg.toString())),
          Wrap(spacing: 12, runSpacing: 6, children: [for (final l in _list(d['legend'])) _lg(V3.hex(l['color']?.toString()), '${l['label']}')]),
        ];
      case 'notes':
        return [
          for (final n in _list(d['notes']))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: V3.hex(n['color']?.toString()), shape: BoxShape.circle),
                  child: Text('${n['initial']}', style: V2.d(10, FontWeight.w700, Colors.white, lh: 1)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${n['user']} ', style: V2.d(12, FontWeight.w600, V2.ink, lh: 1.4)),
                    TextSpan(text: '${n['text']}', style: V2.b(12, FontWeight.w400, V2.ink2, lh: 1.4)),
                  ])),
                ),
              ]),
            ),
        ];
      default:
        final s = d['summary'] ?? d['text'];
        return s == null ? const [] : [Text('$s', style: V2.b(12.5, FontWeight.w400, V2.ink2, lh: 1.45))];
    }
  }

  Widget _lg(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 14, height: 3, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label, style: V2.d(11.5, FontWeight.w500, V2.ink2, lh: 1)),
      ]);

  Future<void> _menu(Map<String, dynamic> p) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final b in _boards.where((b) => b['id'] != _board?['id']))
            ListTile(
              leading: const MIcon('layers', size: 18, color: V2.teal700),
              title: Text('Pindah ke ${b['name']}', style: V2.d(14, FontWeight.w500, V2.ink)),
              onTap: () => Navigator.pop(c, 'move:${b['id']}'),
            ),
          ListTile(
            leading: const MIcon('minus', size: 18, color: V2.red),
            title: Text('Hapus pin', style: V2.d(14, FontWeight.w500, V2.red)),
            onTap: () => Navigator.pop(c, 'delete'),
          ),
        ]),
      ),
    );
    if (v == null) return;
    try {
      if (v == 'delete') {
        await ApiClient.v3Send('DELETE', '/api/ruang/pins/${p['id']}');
      } else {
        await ApiClient.v3Send('PATCH', '/api/ruang/pins/${p['id']}', {'board_id': int.parse(v.split(':')[1])});
      }
      await _load();
    } catch (e) {
      if (mounted) v3Toast(context, 'Pin gagal diubah');
    }
  }
}

/// The phone version of the web DailyChart: 320 x 70, gridlines at 0 and the top.
class _DailyPainter extends CustomPainter {
  _DailyPainter(this.d);
  final Map<String, dynamic> d;

  @override
  void paint(Canvas canvas, Size size) {
    final s = (d['scale'] as num?)?.toDouble() ?? 1;
    List<double?> vals(Object? l) => [for (final v in (l as List? ?? const [])) v == null ? null : (v as num).toDouble() / s];
    final cur = vals(d['cur']), prev = vals(d['prev']);
    final n = [prev.length, cur.length, 2].reduce((a, b) => a > b ? a : b);
    final all = [...cur, ...prev].whereType<double>();
    final mx = all.isEmpty ? 1.0 : all.reduce((a, b) => a > b ? a : b).clamp(1, double.infinity).toDouble();
    final step = mx > 20 ? (mx / 20).ceil() * 10 : (mx / 2).ceil();
    final top = step * 2;
    const x0 = 26.0, x1 = 312.0, yb = 60.0, yt = 8.0;
    double x(int i) => x0 + (x1 - x0) * i / (n - 1);
    double y(double v) => yb - (yb - yt) * v / top;
    canvas.drawLine(const Offset(18, yb + .5), const Offset(318, yb + .5), Paint()..color = V3.axis);
    canvas.drawLine(const Offset(18, yt + .5), const Offset(318, yt + .5), Paint()..color = V2.rule2);
    void label(String t, double yy) {
      final tp = TextPainter(text: TextSpan(text: t, style: V2.d(9.5, FontWeight.w400, V2.mute, lh: 1)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(12 - tp.width, yy - tp.height * .78));
    }

    label('0', 63);
    label(V3.num(top.toDouble()), 11);
    Path path(List<double?> a) {
      final p = Path();
      for (var i = 0; i < a.length; i++) {
        if (a[i] == null) continue;
        if (i == 0 || a[i - 1] == null) {
          p.moveTo(x(i), y(a[i]!));
        } else {
          p.lineTo(x(i), y(a[i]!));
        }
      }
      return p;
    }

    final dashed = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = V2.lagoon;
    for (final m in path(prev).computeMetrics()) {
      for (var t = 0.0; t < m.length; t += 9) {
        canvas.drawPath(m.extractPath(t, (t + 5).clamp(0, m.length)), dashed);
      }
    }
    canvas.drawPath(
        path(cur),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = V2.teal600);
    final last = cur.lastIndexWhere((v) => v != null);
    if (last >= 0) {
      final c = Offset(x(last), y(cur[last]!));
      canvas.drawCircle(c, 3.5, Paint()..color = Colors.white);
      canvas.drawCircle(
          c,
          3.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = V2.teal600);
    }
  }

  @override
  bool shouldRepaint(_DailyPainter o) => o.d != d;
}
