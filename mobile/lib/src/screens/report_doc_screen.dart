import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../ui/ds.dart';
import '../ui/kit.dart';
import '../ui/mock_icons.dart';
import '../ui/v2.dart';
import 'report_list_screen.dart';

/// Full-screen preview of a report document from /api/report-docs: the same
/// typed sections the web preview renders (summary, tables, notes, lists),
/// with a contents strip to jump between sections.
class ReportDocScreen extends StatefulWidget {
  const ReportDocScreen({super.key, required this.item, this.preview});
  final ReportItem item;
  final Map<String, dynamic>? preview;

  @override
  State<ReportDocScreen> createState() => _ReportDocScreenState();
}

class _ReportDocScreenState extends State<ReportDocScreen> {
  Map<String, dynamic>? _doc;
  String? _error;
  final _keys = <int, GlobalKey>{};
  int _active = 1;

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _doc = widget.preview;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final d = widget.item.doc ?? const {};
    try {
      final doc = await ApiClient.reportDoc(d['kind'].toString(),
          region: (d['region'] ?? '').toString(), kabupaten: (d['kabupaten'] ?? '').toString());
      if (mounted) setState(() => _doc = doc);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _share() async {
    try {
      final title = (_doc?['title'] ?? widget.item.title).toString();
      final url = await ApiClient.createReportLink(title, region: (widget.item.doc?['region'] ?? '').toString());
      await Clipboard.setData(ClipboardData(text: url));
      await SharePlus.instance.share(ShareParams(text: '$title\n$url', subject: title));
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  Future<void> _export() async {
    final p = Pal.of(context);
    final it = widget.item;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => ReportExportSheet(
        item: ReportItem(id: it.id, kind: it.kind, title: (_doc?['title'] ?? it.title).toString(), format: 'PDF',
            region: (it.doc?['region'] ?? '').toString()),
      ),
    );
  }

  void _jump(int n) {
    setState(() => _active = n);
    final ctx = _keys[n]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final d = _doc;
    final pages = ((d?['pages'] as List?) ?? const []).map((p) => (p as List).cast<Map>()).toList();
    final toc = ((d?['toc'] as List?) ?? const []).cast<Map>();
    return Scaffold(
      backgroundColor: V2.bg,
      body: Column(children: [
        SizedBox(height: top),
        V2AppBar(
          back: true,
          title: (d?['title'] ?? widget.item.title).toString(),
          subtitle: d == null ? (_error ?? 'Menyusun pratinjau…') : d['meta'].toString(),
          showBell: false,
        ),
        if (toc.isNotEmpty)
          Container(
            height: 46,
            color: Colors.white,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              children: [
                for (final t in toc) ...[
                  GestureDetector(
                    onTap: () => _jump((t['n'] as num).toInt()),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _active == t['n'] ? V2.teal50 : const Color(0xFFF8FBFA),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('${t['n']}. ${t['title']}',
                          style: V2.d(12, _active == t['n'] ? FontWeight.w600 : FontWeight.w500, _active == t['n'] ? V2.teal700 : V2.ink2, lh: 1)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        Expanded(
          child: d == null
              ? Center(
                  child: _error != null
                      ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: V2.b(13, FontWeight.w400, V2.mute, lh: 1.5)))
                      : const CircularProgressIndicator(color: V2.teal600),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                  children: [
                    for (var i = 0; i < pages.length; i++) ...[
                      _page(d, pages[i], i),
                      const SizedBox(height: 14),
                    ],
                    Center(child: Text('${pages.length} halaman', style: V2.b(11.5, FontWeight.w400, V2.mute))),
                  ],
                ),
        ),
        if (d != null)
          Container(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 10 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: V2.rule))),
            child: Row(children: [
              Expanded(child: _btn('Ekspor PDF / XLSX', 'dl', true, _export)),
              const SizedBox(width: 8),
              Expanded(child: _btn('Bagikan', 'share', false, _share)),
            ]),
          ),
      ]),
    );
  }

  Widget _btn(String label, String icon, bool primary, VoidCallback onTap) {
    final fg = primary ? Colors.white : V2.teal700;
    return Material(
      color: primary ? V2.teal600 : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11), side: primary ? BorderSide.none : const BorderSide(color: Color(0xFFDCEFEC))),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            MIcon(icon, size: 16, color: fg),
            const SizedBox(width: 7),
            Text(label, style: V2.d(13, FontWeight.w600, fg, lh: 1)),
          ]),
        ),
      ),
    );
  }

  Widget _page(Map<String, dynamic> d, List<Map> secs, int i) {
    return Container(
      padding: EdgeInsets.only(top: i == 0 ? 0 : 16, bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), boxShadow: [cssShadow(const Color(0x1F0F1F1D), 0, 6, 22)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (i == 0) _header(d),
        for (final s in secs) ...[
          if (i == 0 || s != secs.first) const SizedBox(height: 14),
          _section(s.cast<String, dynamic>()),
        ],
      ]),
    );
  }

  Widget _header(Map<String, dynamic> d) {
    return LayoutBuilder(
      builder: (context, c) => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 60, 16),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          gradient: cssLinear(135, const [V2.teal700, V2.teal900], Size(c.maxWidth, 96)),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d['eyebrow'].toString().toUpperCase(), style: V2.d(9.5, FontWeight.w600, V2.lime, lh: 1.2, ls: .1)),
            const SizedBox(height: 4),
            Text(d['heading'].toString(), style: V2.d(18, FontWeight.w700, Colors.white, lh: 1.2)),
            const SizedBox(height: 4),
            Text(d['byline'].toString(), style: V2.b(10.5, FontWeight.w400, V2.teal100, lh: 1.3)),
          ]),
          Positioned(
            right: -46,
            top: 0,
            child: Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Image.asset('assets/icon_circle.png', fit: BoxFit.contain),
            ),
          ),
        ]),
      ),
    );
  }

  static const _up = Color(0xFF1F7A3A), _down = V2.red;

  Color? _tone(Object? t) => t == 'up' ? _up : t == 'down' ? _down : null;

  Widget _section(Map<String, dynamic> s) {
    final n = (s['n'] as num).toInt();
    final key = _keys.putIfAbsent(n, GlobalKey.new);
    final type = s['type'];
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: V2.teal600, borderRadius: BorderRadius.circular(5)),
            child: Text('$n', style: V2.d(10, FontWeight.w700, Colors.white, lh: 1)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(s['title'].toString(), style: V2.d(12.5, FontWeight.w600, V2.ink, lh: 1.2))),
        ]),
        if (s['sub'] != null) ...[
          const SizedBox(height: 4),
          Text(s['sub'].toString(), style: V2.d(9.5, FontWeight.w500, V2.mute, lh: 1.2)),
        ],
        const SizedBox(height: 8),
        if (type == 'summary') ..._summary(s),
        if (type == 'table') _table(s),
        if (type == 'note')
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFCBD6D3))),
            child: Text(s['text'].toString(), style: V2.b(11.5, FontWeight.w400, V2.ink2, lh: 1.5)),
          ),
        if (type == 'list')
          for (final t in (s['items'] as List? ?? const []))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('•  $t', style: V2.b(11.5, FontWeight.w400, V2.ink2, lh: 1.5)),
            ),
        if (s['note'] != null && type != 'note') ...[
          const SizedBox(height: 6),
          Text(s['note'].toString(), style: V2.b(10, FontWeight.w400, V2.mute, lh: 1.4)),
        ],
      ]),
    );
  }

  List<Widget> _summary(Map<String, dynamic> s) {
    final text = (s['text'] ?? '').toString();
    final parts = text.split(RegExp(r'(\*\*[^*]+\*\*)'));
    final bold = RegExp(r'\*\*([^*]+)\*\*').allMatches(text).map((m) => m[1]!).toList();
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      spans.add(TextSpan(text: parts[i]));
      if (i < bold.length) spans.add(TextSpan(text: bold[i], style: const TextStyle(fontWeight: FontWeight.w600, color: V2.ink)));
    }
    final kpis = (s['kpis'] as List? ?? const []).cast<Map>();
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFFF4FCE3), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDF3A6))),
        child: Text.rich(TextSpan(children: spans), style: V2.b(11.5, FontWeight.w400, V2.ink2, lh: 1.55)),
      ),
      const SizedBox(height: 8),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 2.6,
        children: [
          for (final k in kpis)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), border: Border.all(color: V2.rule)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(k['label'].toString(), style: V2.d(10, FontWeight.w500, V2.mute, lh: 1.2)),
                Text((k['value'] ?? '-').toString(), style: V2.d(14, FontWeight.w700, V2.ink, lh: 1.25)),
                if (k['delta'] != null) Text(k['delta'].toString(), style: V2.d(10, FontWeight.w600, _tone(k['tone']) ?? V2.mute, lh: 1.2)),
              ]),
            ),
        ],
      ),
    ];
  }

  Widget _table(Map<String, dynamic> s) {
    final cols = (s['cols'] as List? ?? const []).map((e) => e.toString()).toList();
    final rows = (s['rows'] as List? ?? const []).cast<List>();
    Widget cell(Object? c, int j, {bool head = false}) {
      final m = c is Map ? c : null;
      final v = m == null ? c : m['v'];
      final bar = m?['bar'] as Map?;
      final style = head
          ? V2.d(9, FontWeight.w600, V2.mute, lh: 1.2, ls: .04)
          : j == 0
              ? V2.d(11, FontWeight.w600, V2.ink, lh: 1.3)
              : V2.b(11, FontWeight.w400, v == null ? const Color(0xFF8A9A97) : _tone(m?['tone']) ?? V2.ink, lh: 1.3);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        alignment: j == 0 ? Alignment.centerLeft : Alignment.centerRight,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (bar != null) ...[
            Container(
              width: (bar['w'] as num).toDouble(),
              height: 6,
              decoration: BoxDecoration(color: _hex(bar['c'].toString()), borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 5),
          ],
          Text(head ? v.toString().toUpperCase() : (v ?? '-').toString(), style: style),
        ]),
      );
    }

    if (rows.isEmpty) return Text('Belum ada baris untuk bagian ini.', style: V2.b(10.5, FontWeight.w400, V2.mute));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: const BoxDecoration(color: V2.bg, border: Border(bottom: BorderSide(color: V2.rule))),
            children: [for (var j = 0; j < cols.length; j++) cell(cols[j], j, head: true)],
          ),
          for (final r in rows)
            TableRow(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: V2.rule2))),
              children: [for (var j = 0; j < cols.length; j++) cell(j < r.length ? r[j] : null, j)],
            ),
        ],
      ),
    );
  }

  static Color _hex(String h) => Color(int.parse('FF${h.replaceFirst('#', '')}', radix: 16));
}
