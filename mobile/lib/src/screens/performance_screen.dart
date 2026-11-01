import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../ui/answer_v2.dart' show Triangle;
import '../ui/chart.dart' show toNum;
import '../ui/mock_icons.dart';
import '../ui/v2.dart';

/// Android · Performa tab (Redesign v2, design/mockup-v2/04-performance): search,
/// drill-down path Circle Java > region > kabupaten > kecamatan, the dump label,
/// four KPI cards with MoM and YoY, the 12-month trend against the year before,
/// the areas behind the revenue change (tap to go one level down) and the site
/// list with an expandable card per site.
/// Numbers come from GET /api/performance (daily Parquet dump). The last answer
/// per scope is kept on the device so the tab still opens offline.
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key, this.preview, this.previewOffline = false, this.onAsk, this.onOpenMap, this.initialScope});

  /// Payload to render instead of fetching (golden tests).
  final Map<String, dynamic>? preview;
  final bool previewOffline;

  /// Sends a question to the Agent tab.
  final void Function(String question)? onAsk;

  /// Opens Peta Agent on a site.
  final void Function(String siteId)? onOpenMap;

  /// region / kabupaten / kecamatan to open with.
  final Map<String, String>? initialScope;

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

const _green = Color(0xFF1F7A3A);
const _amberInk = Color(0xFFB7791F);
const _okBg = Color(0xFFE6F4EA);
const _badBg = Color(0xFFFDECEC);
final _f0 = NumberFormat('#,##0', 'id');
final _f1 = NumberFormat('#,##0.0', 'id');
final _f2 = NumberFormat('#,##0.00', 'id');

String _rp(num? v) {
  if (v == null) return '–';
  final a = v.abs();
  if (a >= 1e12) return 'Rp ${_f2.format(v / 1e12)} T';
  if (a >= 1e9) return 'Rp ${_f1.format(v / 1e9)} M';
  if (a >= 1e6) return 'Rp ${_f0.format(v / 1e6)} jt';
  return 'Rp ${_f0.format(v)}';
}

String _vol(num? v) {
  if (v == null) return '–';
  final a = v.abs();
  if (a >= 1e6) return '${_f2.format(v / 1e6)} PB';
  if (a >= 1e3) return '${_f1.format(v / 1e3)} TB';
  return '${_f1.format(v)} GB';
}

String _people(num? v) {
  if (v == null) return '–';
  final a = v.abs();
  if (a >= 1e6) return '${_f1.format(v / 1e6)} jt';
  if (a >= 1e3) return '${_f0.format(v / 1e3)} rb';
  return _f0.format(v);
}

String _chg(num v, {bool pp = false}) => '${(pp ? _f2 : _f1).format(v.abs())}${pp ? ' pp' : '%'}';

class _PerformanceScreenState extends State<PerformanceScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  bool _offlineReady = false;
  bool _offline = false;
  late Map<String, String> _scope = {'region': '', 'kabupaten': '', 'kecamatan': '', ...?widget.initialScope};
  String _status = '';
  String _metric = 'revenue';
  int? _hover;
  String? _open;
  bool _showAll = false;
  int _page = 1;
  final List<Map<String, dynamic>> _extra = [];
  final _q = TextEditingController();
  List<Map<String, dynamic>> _hits = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _apply(widget.preview!);
      _offlineReady = widget.previewOffline;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _q.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  String get _cacheKey => 'perf_cache::${_scope['region']}|${_scope['kabupaten']}|${_scope['kecamatan']}|$_status';

  void _apply(Map<String, dynamic> d) {
    _data = d;
    _hover = null;
    _extra.clear();
    _page = 1;
    final rows = ((d['sites'] as Map?)?['rows'] as List? ?? const []);
    final ids = rows.whereType<Map>().map((r) => r['site_id'].toString()).toList();
    if (_open == null || !ids.contains(_open)) _open = ids.isEmpty ? null : ids.first;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiClient.performance(
          region: _scope['region']!, kabupaten: _scope['kabupaten']!, kecamatan: _scope['kecamatan']!, status: _status);
      if (!mounted) return;
      setState(() {
        _apply(d);
        _offline = false;
      });
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(_cacheKey, jsonEncode(d));
        if (mounted) setState(() => _offlineReady = true);
      } catch (_) {/* cache is best-effort */}
    } catch (e) {
      Map<String, dynamic>? cached;
      try {
        final s = (await SharedPreferences.getInstance()).getString(_cacheKey);
        if (s != null) cached = jsonDecode(s) as Map<String, dynamic>;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        if (cached != null) {
          _apply(cached);
          _offline = true;
        } else {
          _error = e.toString().replaceFirst('Exception: ', '');
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    final s = _data?['sites'] as Map?;
    final pages = toNum(s?['pages'])?.toInt() ?? 1;
    if (widget.preview != null || _page >= pages) return;
    try {
      final d = await ApiClient.performance(
          region: _scope['region']!, kabupaten: _scope['kabupaten']!, kecamatan: _scope['kecamatan']!, status: _status, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _page++;
        _extra.addAll(((d['sites'] as Map?)?['rows'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()));
      });
    } catch (_) {}
  }

  void _go(Map<String, String> next) {
    setState(() {
      _scope = next;
      _status = '';
      _showAll = false;
      _open = null;
    });
    if (widget.preview == null) _load();
  }

  void _drill(String key) {
    final child = (_data?['child_level'] ?? '').toString();
    if (child == 'site') {
      setState(() => _open = key);
      return;
    }
    _go({..._scope, child: key});
  }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final r = await ApiClient.performanceSearch(q.trim());
        if (mounted) setState(() => _hits = r.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList());
      } catch (_) {}
    });
  }

  void _pick(Map<String, dynamic> h) {
    _q.clear();
    FocusScope.of(context).unfocus();
    setState(() => _hits = const []);
    if (h['type'] == 'site') {
      widget.onOpenMap?.call(h['name'].toString());
      return;
    }
    _go({
      'region': (h['region'] ?? '').toString(),
      'kabupaten': (h['kabupaten'] ?? '').toString(),
      'kecamatan': h['type'] == 'kecamatan' ? (h['kecamatan'] ?? '').toString() : '',
    });
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final scope = V2Scope.maybeOf(context);
    final d = _data;
    final sub = d == null ? 'Memuat…' : '${d['name']} · ${d['month_label']}';
    return ColoredBox(
      color: V2.bg,
      child: Column(children: [
        SizedBox(height: top),
        V2AppBar(
          title: 'Performance',
          subtitle: sub,
          subtitleDot: _offline || _loading ? const Color(0xFFE0A100) : const Color(0xFF2E9E57),
          alertCount: scope?.alerts ?? 0,
          onBell: scope == null ? null : () => scope.openAlerts(),
        ),
        Expanded(
          child: RefreshIndicator(
            color: V2.teal600,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _searchBox(),
                if (_hits.isNotEmpty) ...[const SizedBox(height: 8), _results()],
                const SizedBox(height: 12),
                _path(d),
                const SizedBox(height: 12),
                if (d == null && _error != null)
                  _card(children: [Text(_error!, style: V2.b(13, FontWeight.w400, V2.ink2, lh: 1.4))])
                else if (d == null)
                  Container(height: 600, decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(18)))
                else ...[
                  _source(d),
                  const SizedBox(height: 12),
                  _kpis(d),
                  const SizedBox(height: 12),
                  _trend(d),
                  const SizedBox(height: 12),
                  _contrib(d),
                  const SizedBox(height: 12),
                  _sites(d),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Search, path, source ──

  Widget _searchBox() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: V2.rule)),
      child: Row(children: [
        const MIcon('search', size: 18, color: V2.mute),
        const SizedBox(width: 10),
        Expanded(
          child: Stack(alignment: Alignment.centerLeft, children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _q,
              builder: (context, v, _) => v.text.isEmpty
                  ? IgnorePointer(child: Text('Cari site atau wilayah', style: V2.b(13.5, FontWeight.w400, V2.mute, lh: 1)))
                  : const SizedBox(),
            ),
            TextField(
              controller: _q,
              onChanged: _search,
              onSubmitted: (_) => _hits.isNotEmpty ? _pick(_hits.first) : null,
              textInputAction: TextInputAction.search,
              style: V2.b(13.5, FontWeight.w400, V2.ink, lh: 1.2),
              cursorColor: V2.teal600,
              decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _results() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: V2.rule),
        boxShadow: [cssShadow(const Color(0x2404332E), 0, 10, 26)],
      ),
      child: Column(children: [
        for (final h in _hits)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _pick(h),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                Expanded(
                  child: Text(h['type'] == 'site' ? '${h['name']} · ${h['site_name'] ?? ''}' : h['name'].toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(13, FontWeight.w500, V2.ink, lh: 1.3)),
                ),
                const SizedBox(width: 8),
                Text(
                  switch (h['type']) {
                    'site' => 'Site',
                    'kecamatan' => 'Kecamatan',
                    _ => 'Kabupaten',
                  },
                  style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _path(Map<String, dynamic>? d) {
    final path = (d?['path'] as List? ?? const [
      {'level': 'circle', 'name': 'Circle Java'}
    ])
        .whereType<Map>()
        .toList();
    return SizedBox(
      height: 30,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < path.length; i++) ...[
            if (i > 0) ...[const SizedBox(width: 6), const MIcon('chevr', size: 14, color: Color(0xFF8A9A97)), const SizedBox(width: 6)],
            Semantics(
              button: i < path.length - 1,
              label: path[i]['name'].toString(),
              child: GestureDetector(
                onTap: i == path.length - 1
                    ? null
                    : () {
                        const order = ['circle', 'region', 'kabupaten', 'kecamatan'];
                        final k = order.indexOf(path[i]['level'].toString());
                        _go({
                          'region': k >= 1 ? _scope['region']! : '',
                          'kabupaten': k >= 2 ? _scope['kabupaten']! : '',
                          'kecamatan': k >= 3 ? _scope['kecamatan']! : '',
                        });
                      },
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: i == path.length - 1 ? V2.ink : V2.teal50, borderRadius: BorderRadius.circular(99)),
                  child: Text(path[i]['name'].toString(), style: V2.d(12, FontWeight.w600, i == path.length - 1 ? Colors.white : V2.teal700, lh: 1)),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  String _wibShort(String? iso) {
    final t = DateTime.tryParse(iso ?? '');
    if (t == null) return '-';
    final w = t.toUtc().add(const Duration(hours: 7));
    const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${w.day} ${mon[w.month - 1]} ${w.hour.toString().padLeft(2, '0')}.${w.minute.toString().padLeft(2, '0')} WIB';
  }

  Widget _source(Map<String, dynamic> d) {
    final src = d['source'] as Map? ?? const {};
    final kind = (src['kind'] ?? '').toString();
    final green = kind == 'dump' && !_offline;
    final ink = green ? const Color(0xFF3D5A0E) : const Color(0xFF7A4E0E);
    final dot = green ? const Color(0xFF5E8A12) : const Color(0xFFE0A100);
    final base = V2.d(11.5, FontWeight.w500, ink, lh: 1);
    final spans = <InlineSpan>[
      if (kind == 'bigquery') const TextSpan(text: 'BigQuery langsung · dump belum tersedia')
      else ...[
        const TextSpan(text: 'Dump Parquet '),
        TextSpan(text: _wibShort(src['created_at']?.toString()), style: base.copyWith(fontWeight: FontWeight.w700)),
        TextSpan(text: _offline ? ' · tampilan offline' : kind == 'stale' ? ' · dump terlambat' : _offlineReady ? ' · offline siap' : ''),
      ],
    ];
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: green ? const Color(0xFFF4FCE3) : const Color(0xFFFDF3E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: green ? const Color(0xFFDDF3A6) : const Color(0xFFF5D9A8)),
      ),
      child: Row(children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle, boxShadow: [BoxShadow(color: dot.withValues(alpha: .15), spreadRadius: 4)]),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text.rich(TextSpan(style: base, children: spans), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ── KPI cards ──

  Widget _kpis(Map<String, dynamic> d) {
    final ks = {for (final k in (d['kpis'] as List? ?? const []).whereType<Map>()) k['key'].toString(): k};
    const looks = {
      'revenue': ('wallet', Color(0xFFFCEDD3), _amberInk),
      'payload': ('db', Color(0xFFE3F7FA), Color(0xFF0E6F7C)),
      'subs': ('users', Color(0xFFE1ECFA), Color(0xFF2C6CB0)),
      'availability': ('tower', Color(0xFFECE5FA), Color(0xFF6A4CB5)),
    };
    Widget card(String key) {
      final k = ks[key];
      final look = looks[key]!;
      if (k == null) return const SizedBox();
      final av = key == 'availability';
      final value = toNum(k['value']);
      final mom = toNum(av ? k['mom_pp'] : k['mom_pct']);
      final yoy = toNum(av ? k['yoy_pp'] : k['yoy_pct']);
      final text = switch (key) {
        'revenue' => _rp(value),
        'payload' => _vol(value),
        'subs' => _people(value),
        _ => value == null ? '–' : '${_f2.format(value)}%',
      };
      final yy = V2.b(11, FontWeight.w400, V2.mute, lh: 1.3);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: V2.rule),
          boxShadow: [cssShadow(const Color(0x0A0F1F1D), 0, 4, 14)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 28,
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: look.$2, borderRadius: BorderRadius.circular(10)),
                child: MIcon(look.$1, size: 15, color: look.$3),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text((k['label'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(13, FontWeight.w500, V2.ink2, lh: 1.2))),
            ]),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 21 * 1.15,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(text, maxLines: 1, style: V2.d(21, FontWeight.w700, V2.ink, lh: 1.15, ls: -.01)),
            ),
          ),
          const SizedBox(height: 4),
          if (mom != null)
            _pill(mom, pp: av, suffix: av ? '' : ' MoM')
          else
            const SizedBox(height: 19),
          const SizedBox(height: 4),
          SizedBox(
            height: 15.3,
            child: av
                ? Text('Target ${_f1.format(toNum(k['target']) ?? 99.5)}%', style: yy)
                : Text.rich(TextSpan(style: yy, children: [
                    const TextSpan(text: 'YoY '),
                    if (yoy == null)
                      const TextSpan(text: '–')
                    else ...[
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Triangle(up: yoy >= 0, color: yoy >= 0 ? _green : V2.red, width: 9, height: 8),
                        ),
                      ),
                      TextSpan(text: _chg(yoy), style: V2.d(11, FontWeight.w600, yoy >= 0 ? _green : V2.red, lh: 1.3)),
                    ],
                  ])),
          ),
        ]),
      );
    }

    Widget row(String a, String b) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: card(a)), const SizedBox(width: 10), Expanded(child: card(b))]),
        );
    return Column(children: [row('revenue', 'payload'), const SizedBox(height: 10), row('subs', 'availability')]);
  }

  Widget _pill(num v, {bool pp = false, String suffix = ''}) {
    final down = v < 0;
    return Container(
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(color: down ? _badBg : _okBg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Triangle(up: !down, color: down ? V2.red : _green, width: 10, height: 8.5),
        const SizedBox(width: 3),
        Text('${_chg(v, pp: pp)}$suffix', style: V2.d(11, FontWeight.w600, down ? V2.red : _green, lh: 1)),
      ]),
    );
  }

  // ── Cards ──

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: V2.rule),
        boxShadow: [cssShadow(const Color(0x0A0F1F1D), 0, 4, 14)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
      ]),
    );
  }

  Widget _tx(String s, TextStyle st) => V2Lines(TextSpan(text: s, style: st), lineHeight: st.fontSize! * st.height!, dy: 0);

  Widget _head(String h, String p) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _tx(h, V2.d(16, FontWeight.w600, V2.ink, lh: 1.3)),
        const SizedBox(height: 2),
        _tx(p, V2.b(12, FontWeight.w400, V2.mute, lh: 1.3)),
      ]);

  Widget _seg(List<(String, String)> items, String value, void Function(String) onTap) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Semantics(
            button: true,
            selected: value == items[i].$1,
            child: GestureDetector(
              onTap: () => onTap(items[i].$1),
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: value == items[i].$1
                    ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [cssShadow(const Color(0x1F0F1F1D), 0, 1, 3)])
                    : null,
                child: Text(items[i].$2, style: V2.d(12, FontWeight.w600, value == items[i].$1 ? V2.teal700 : V2.ink2, lh: 1)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Trend ──

  Widget _trend(Map<String, dynamic> d) {
    final t = d['trend'] as Map? ?? const {};
    List<double?> vals(String part) => ((t[part] as Map?)?[_metric] as List? ?? const []).map(toNum).toList();
    final div = switch (_metric) { 'payload' => 1e6, 'subs' => 1e3, _ => 1e9 };
    final cur = [for (final v in vals('current')) v == null ? null : v / div];
    final prev = [for (final v in vals('previous')) v == null ? null : v / div];
    final labels = (t['labels'] as List? ?? const []).map((e) => e.toString()).toList();
    final titles = (t['titles'] as List? ?? const []).map((e) => e.toString()).toList();
    final n = labels.length;
    final h = n == 0 ? 0 : (_hover ?? n - 1).clamp(0, n - 1);
    String f(double v) => switch (_metric) { 'payload' => '${_f2.format(v)} PB', 'subs' => '${_f0.format(v)} rb', _ => 'Rp ${_f1.format(v)} M' };
    final c = h < cur.length ? cur[h] : null, p = h < prev.length ? prev[h] : null;
    final yoy = c != null && p != null && p != 0 ? (c / p - 1) * 100 : null;
    final mom = h > 0 && c != null && cur[h - 1] != null && cur[h - 1] != 0 ? (c / cur[h - 1]! - 1) * 100 : null;
    final row = V2.d(12, FontWeight.w500, Colors.white, lh: 1.55);
    Widget tipRow(Color? dot, String name, String value, {Color color = Colors.white}) => Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Expanded(child: _tx(name, row)),
          const SizedBox(width: 12),
          Text(value, style: V2.d(12, FontWeight.w700, color, lh: 1)),
        ]);
    String sg(double v) => '${v >= 0 ? '▲' : '▼'} ${_chg(v)}';
    return _card(children: [
      _head('Tren 12 bulan', 'Putus-putus: setahun sebelumnya'),
      _seg(const [('revenue', 'Revenue'), ('payload', 'Payload'), ('subs', 'Pelanggan')], _metric, (m) => setState(() => _metric = m)),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, cs) {
          // the mockup plot is 18 px wider than the card content (grid runs into the padding)
          final w = cs.maxWidth + 18;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) => setState(() => _hover = n < 2 ? 0 : (((e.localPosition.dx - 34) / (w - 42)) * (n - 1)).round().clamp(0, n - 1)),
            onHorizontalDragUpdate: (e) => setState(() => _hover = n < 2 ? 0 : (((e.localPosition.dx - 34) / (w - 42)) * (n - 1)).round().clamp(0, n - 1)),
            child: SizedBox(height: 190, child: CustomPaint(painter: _TrendPainter(cur, prev, labels, h, w, _metric))),
          );
        }),
        const SizedBox(height: 11.2),
        if (n > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: V2.ink, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _tx(h < titles.length ? titles[h] : labels[h], V2.d(12, FontWeight.w700, Colors.white, lh: 1.55)),
              tipRow(V2.teal600, 'Nilai', c == null ? '–' : f(c)),
              tipRow(const Color(0xFF9AA8A5), 'Setahun lalu', p == null ? '–' : f(p)),
              if (yoy != null) tipRow(null, 'YoY', sg(yoy), color: yoy >= 0 ? const Color(0xFF8EE0A6) : const Color(0xFFFF9C9C)),
              if (mom != null) tipRow(null, 'MoM', sg(mom), color: mom >= 0 ? const Color(0xFF8EE0A6) : const Color(0xFFFF9C9C)),
            ]),
          ),
      ]),
    ]);
  }

  // ── Contribution ──

  Widget _contrib(Map<String, dynamic> d) {
    final items = (d['contrib'] as List? ?? const []).whereType<Map>().toList();
    final neg = items.where((c) => (toNum(c['delta']) ?? 0) < 0).take(4).toList();
    final posAll = items.where((c) => (toNum(c['delta']) ?? 0) > 0).toList();
    final pos = posAll.length > 2 ? posAll.sublist(posAll.length - 2) : posAll;
    final named = {...neg, ...pos}.map((c) => c['key']).toSet();
    final rest = items.where((c) => !named.contains(c['key'])).toList();
    final mx = [...neg, ...pos].map((c) => (toNum(c['delta']) ?? 0).abs()).fold<double>(1, math.max);
    final child = (d['child_level'] ?? 'kecamatan').toString();
    final short = const {'region': 'region', 'kabupaten': 'kab.', 'kecamatan': 'kec.', 'site': 'site'}[child] ?? '';
    String juta(double v) => '${v > 0 ? '+' : v < 0 ? '−' : ''}${_f0.format((v.abs() / 1e6).round())}';
    Widget bar(String name, double delta, {String? key, bool other = false}) {
      final pos = delta > 0;
      final w = (delta.abs() / mx * .48).clamp(0.0, .48);
      return Semantics(
        button: !other,
        label: '$name: ${juta(delta)} juta',
        child: GestureDetector(
          onTap: other || key == null ? null : () => _drill(key),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            color: Colors.transparent,
            child: Row(children: [
              SizedBox(width: 96, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(12, FontWeight.w500, other ? V2.mute : V2.ink2, lh: 1))),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final tw = c.maxWidth;
                  return SizedBox(
                    height: 30,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Positioned(left: tw / 2, top: 0, bottom: 0, width: 1, child: const ColoredBox(color: Color(0xFFCBD6D3))),
                      Positioned(
                        left: pos ? tw / 2 : tw / 2 - tw * w,
                        top: 8,
                        width: tw * w,
                        height: 14,
                        child: Opacity(
                          opacity: other ? .55 : 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: pos ? const Color(0xFF2E9E57) : const Color(0xFFE5484D), borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                      ),
                    ]),
                  );
                }),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 52,
                child: Text(juta(delta), textAlign: TextAlign.right, style: V2.d(12.5, FontWeight.w600, pos ? _green : V2.red, lh: 1)),
              ),
            ]),
          ),
        ),
      );
    }

    final total = toNum(d['contrib_total']) ?? 0;
    final shortName = d['name'].toString();
    return _card(children: [
      _head('Penyebab perubahan revenue', 'Selisih MoM, Rp juta · ${child == 'site' ? 'ketuk untuk lihat site' : 'ketuk untuk turun level'}'),
      Column(children: [
        for (final (i, c) in [...neg, ...pos].indexed) ...[
          if (i > 0) const SizedBox(height: 2),
          bar(c['name'].toString(), toNum(c['delta']) ?? 0, key: c['key'].toString()),
        ],
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 2),
          bar('${rest.length} $short lain', rest.fold<double>(0, (a, c) => a + (toNum(c['delta']) ?? 0)), other: true),
        ],
      ]),
      Container(
        padding: const EdgeInsets.only(top: 10),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: V2.rule2))),
        child: Row(children: [
          Expanded(child: _tx('Total $shortName', V2.b(12, FontWeight.w400, V2.mute, lh: 1.3))),
          Text('${total < 0 ? '−' : '+'}Rp ${_f0.format((total.abs() / 1e6).round())} jt', style: V2.d(13, FontWeight.w700, total < 0 ? V2.red : _green, lh: 1.3)),
        ]),
      ),
    ]);
  }

  // ── Sites ──

  Widget _sites(Map<String, dynamic> d) {
    final s = d['sites'] as Map? ?? const {};
    final counts = s['counts'] as Map? ?? const {};
    final rows = [...(s['rows'] as List? ?? const []).whereType<Map>(), ..._extra];
    final total = toNum(s['total'])?.toInt() ?? rows.length;
    final shown = _showAll ? rows : rows.take(2).toList();
    final more = !_showAll ? total > shown.length : rows.length < total;
    return _card(children: [
      _head('Site di ${d['name']}', '${_f0.format(toNum(d['site_count']) ?? total)} site · payload MoM terendah dulu'),
      _seg([('', 'Semua'), ('kritis', 'Kritis ${counts['kritis'] ?? ''}'.trim()), ('waspada', 'Waspada ${counts['waspada'] ?? ''}'.trim())], _status, (v) {
        setState(() {
          _status = v;
          _open = null;
        });
        if (widget.preview == null) _load();
      }),
      Column(children: [
        for (final (i, r) in shown.indexed) ...[if (i > 0) const SizedBox(height: 10), _siteCard(r)],
      ]),
      if (more)
        Semantics(
          button: true,
          child: GestureDetector(
            onTap: () {
              if (!_showAll) {
                setState(() => _showAll = true);
              } else {
                _more();
              }
            },
            child: Container(
              height: 42,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: V2.rule)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(!_showAll ? 'Lihat semua ${_f0.format(total)} site' : 'Muat site berikutnya', style: V2.d(13, FontWeight.w600, V2.teal700, lh: 1)),
                const SizedBox(width: 8),
                const MIcon('arrowr', size: 16, color: V2.teal700),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _siteCard(Map r) {
    final id = r['site_id'].toString();
    final sel = _open == id;
    final status = (r['status'] ?? 'normal').toString();
    final (sevBg, sevFg, sevText) = switch (status) {
      'kritis' => (_badBg, V2.red, 'Kritis'),
      'waspada' => (const Color(0xFFFDF3E2), _amberInk, 'Waspada'),
      _ => (_okBg, _green, 'Normal'),
    };
    Widget m(String label, String value, num? delta, {bool pp = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(color: sel ? Colors.white : V2.bg, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(height: 12.6, child: Text(label, style: V2.d(10.5, FontWeight.w500, V2.mute, lh: 1.2))),
              const SizedBox(height: 2),
              SizedBox(height: 16.8, child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(14, FontWeight.w700, V2.ink, lh: 1.2))),
              const SizedBox(height: 2),
              SizedBox(
                height: 12.6,
                child: delta == null
                    ? Text('–', style: V2.d(10.5, FontWeight.w600, V2.mute, lh: 1.2))
                    : Row(children: [
                        Triangle(up: delta >= 0, color: delta >= 0 ? _green : V2.red, width: 8.5, height: 7.5),
                        const SizedBox(width: 3),
                        Text(pp ? '${_f1.format(delta.abs())} pp' : _chg(delta), style: V2.d(10.5, FontWeight.w600, delta >= 0 ? _green : V2.red, lh: 1.2)),
                      ]),
              ),
            ]),
          ),
        );
    final av = toNum(r['availability']);
    final avPp = toNum(r['availability_mom_pp']);
    return GestureDetector(
      onTap: () => setState(() => _open = sel ? null : id),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFF2FBFA) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? V2.teal200 : V2.rule),
        ),
        child: Stack(children: [
          if (sel) const Positioned(left: 0, top: 0, bottom: 0, width: 3, child: ColoredBox(color: V2.teal600)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(height: 17.5, child: Text(id, style: V2.d(14, FontWeight.w600, V2.ink, lh: 1.25))),
                    SizedBox(
                      height: 14.95,
                      child: Text('${r['site_name'] ?? '-'} · ${r['kecamatan'] ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3)),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 19,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: sevBg, borderRadius: BorderRadius.circular(99)),
                  child: Text(sevText, style: V2.d(11, FontWeight.w600, sevFg, lh: 1)),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                m('Payload', _vol(toNum(r['payload_gb'])), toNum(r['payload_mom'])),
                const SizedBox(width: 6),
                m('Revenue', _rp(toNum(r['revenue'])), toNum(r['revenue_mom'])),
                const SizedBox(width: 6),
                m('Avail.', av == null ? '–' : '${_f2.format(av)}%', avPp, pp: true),
              ]),
              if (sel && (r['note'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                V2Lines(
                  TextSpan(style: V2.b(12.5, FontWeight.w400, V2.ink2, lh: 1.45), children: [
                    TextSpan(text: 'Catatan agent: ', style: V2.b(12.5, FontWeight.w600, V2.ink2, lh: 1.45)),
                    TextSpan(text: r['note'].toString()),
                  ]),
                  lineHeight: 12.5 * 1.45,
                  dy: 0,
                ),
              ],
              if (sel) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _act('spark', 'Tanya Agent', solid: true, onTap: () {
                      widget.onAsk?.call('Kenapa site $id (${r['site_name'] ?? r['kecamatan']}) berubah di ${_data?['month_label']}? Bandingkan payload, revenue dan availability dengan bulan lalu.');
                    }),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _act('map', 'Lihat di peta', onTap: () => widget.onOpenMap?.call(id))),
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _act(String icon, String label, {bool solid = false, VoidCallback? onTap}) {
    final fg = solid ? Colors.white : V2.teal700;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            color: solid ? V2.teal600 : Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: solid ? null : Border.all(color: const Color(0xFFDCEFEC)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            MIcon(icon, size: 15, color: fg),
            const SizedBox(width: 7),
            Text(label, style: V2.d(12.5, FontWeight.w600, fg, lh: 1)),
          ]),
        ),
      ),
    );
  }
}

/// 12-month line (solid, soft area) against the year before (dashed), with a
/// dashed rule and points on the selected month (mockup svg.tchart, small).
class _TrendPainter extends CustomPainter {
  _TrendPainter(this.cur, this.prev, this.labels, this.hover, this.width, this.metric);
  final List<double?> cur, prev;
  final List<String> labels;
  final int hover;
  final double width;
  final String metric;

  static const pl = 34.0, pr = 8.0, pt = 12.0, pb = 26.0;

  void _text(Canvas c, String t, double x, double baseline, {bool right = false, bool bold = false, Color color = V2.mute}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontFamily: V2.display, fontSize: 10, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    final asc = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    tp.paint(c, Offset(right ? x - tp.width : x - tp.width / 2, baseline - asc));
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    final w = width, h = size.height, iw = w - pl - pr, ih = h - pt - pb;
    final all = [...cur, ...prev].whereType<double>().toList();
    if (all.isEmpty) return;
    final mn0 = all.reduce(math.min), mx0 = all.reduce(math.max);
    final pad = (mx0 - mn0) * .15 == 0 ? 1.0 : (mx0 - mn0) * .15;
    final mn = mn0 - pad, mx = mx0 + pad;
    double x(int i) => pl + iw * i / math.max(1, n - 1);
    double y(double v) => pt + ih * (1 - (v - mn) / (mx - mn));
    final ax = NumberFormat(metric == 'payload' ? '#,##0.0' : '#,##0', 'id');
    for (var g = 0; g <= 3; g++) {
      final v = mn + (mx - mn) * g / 3;
      canvas.drawLine(Offset(pl, y(v)), Offset(w - pr, y(v)), Paint()
        ..color = g == 0 ? const Color(0xFFB9C6C3) : V2.rule2
        ..strokeWidth = 1);
      _text(canvas, ax.format(v), pl - 8, y(v) + 4, right: true);
    }
    // dashed hover rule
    final dash = Paint()
      ..color = V2.teal200
      ..strokeWidth = 1.5;
    for (var yy = pt; yy < pt + ih; yy += 6) {
      canvas.drawLine(Offset(x(hover), yy), Offset(x(hover), math.min(yy + 3, pt + ih)), dash);
    }
    Path line(List<double?> vs) {
      final p = Path();
      var pen = false;
      for (var i = 0; i < vs.length; i++) {
        final v = vs[i];
        if (v == null) {
          pen = false;
          continue;
        }
        pen ? p.lineTo(x(i), y(v)) : p.moveTo(x(i), y(v));
        pen = true;
      }
      return p;
    }

    var last = -1;
    for (var i = 0; i < cur.length; i++) {
      if (cur[i] != null) last = i;
    }
    if (last > 0) {
      final area = line(cur)
        ..lineTo(x(last), pt + ih)
        ..lineTo(x(0), pt + ih)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [V2.teal600.withValues(alpha: .18), V2.teal600.withValues(alpha: 0)],
          ).createShader(area.getBounds()),
      );
    }
    // previous year, dashed 5 4
    final pp = line(prev);
    final dashed = Path();
    for (final m in pp.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        dashed.addPath(m.extractPath(d, math.min(d + 5, m.length)), Offset.zero);
      }
    }
    canvas.drawPath(dashed, Paint()
      ..color = const Color(0xFF9AA8A5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    canvas.drawPath(line(cur), Paint()
      ..color = V2.teal600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round);
    if (hover < prev.length && prev[hover] != null) {
      final o = Offset(x(hover), y(prev[hover]!));
      canvas.drawCircle(o, 4, Paint()..color = Colors.white);
      canvas.drawCircle(o, 4, Paint()
        ..color = const Color(0xFF9AA8A5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    if (hover < cur.length && cur[hover] != null) {
      final o = Offset(x(hover), y(cur[hover]!));
      canvas.drawCircle(o, 5, Paint()..color = V2.teal600);
      canvas.drawCircle(o, 5, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    for (var i = 0; i < n; i++) {
      if (i.isOdd && i != hover) continue;
      _text(canvas, labels[i], x(i), h - 7, bold: i == hover, color: i == hover ? V2.ink : V2.mute);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter o) =>
      o.cur != cur || o.prev != prev || o.hover != hover || o.width != width || o.metric != metric || o.labels != labels;
}
