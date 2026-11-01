// Redesign v2 page 09 (Android): Statistik aplikasi for admins, opened from Profil.
// Period switch, KPI tiles, daily active users, access requests to approve,
// feature sessions and question topics, login heatmap, version adoption,
// downloads vs update installs, the access list and login security.
// Backed by GET /api/admin/app-stats (the "v2" block plus users and heatmap).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../ui/mock_icons.dart';
import '../ui/v2.dart';

const _t = Color(0xFF0E8579), _l = Color(0xFF22B8C9), _li = Color(0xFF8FD6CB), _am = Color(0xFFD98E0B), _gr = Color(0xFF9AAAA6);
const _hc = [Color(0xFFECF3F1), Color(0xFFC0EDE8), Color(0xFF8FDFD7), Color(0xFF3FBFB1), Color(0xFF0E8579)];
const _rowCol = [Color(0xFF0E8579), Color(0xFF2C6CB0), Color(0xFF5E8A12), Color(0xFFB33A5B), Color(0xFF0E6F7C)];
const _pendCol = [Color(0xFF2C6CB0), Color(0xFFB7791F), Color(0xFF6A4CB5)];
const _topicBg = {'performance': Color(0xFFE6F7F5), 'site': Color(0xFFF4FCE3), 'profile': Color(0xFFE1ECFA)};
const _shortFeature = {'watchlist': 'Watchlist'};
const _days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _weekday = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const _nice = [1, 2, 4, 5, 8, 10, 20, 25, 40, 50, 100, 200, 250, 400, 500, 1000, 2000, 2500, 5000, 10000];
const _shown = 5;

String _nf(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
}

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.preview, this.previewNow});
  final Map<String, dynamic>? preview;
  final DateTime? previewNow;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _period = 7;
  Map<String, dynamic>? _data;
  String? _error;
  int? _busy;
  bool _reminding = false;

  DateTime get _now => widget.previewNow ?? DateTime.now();
  Map get _v2 => (_data?['v2'] as Map?) ?? const {};

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _data = widget.preview;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.appStats(days: _period);
      if (mounted) setState(() { _data = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _toast(String s, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), backgroundColor: error ? V2.red : V2.teal700));
  }

  // WIB wall clock, whatever the phone's zone.
  DateTime _wib(String iso) => DateTime.parse(iso).toUtc().add(const Duration(hours: 7));
  int _wibDay(DateTime t) => t.toUtc().add(const Duration(hours: 7)).millisecondsSinceEpoch ~/ 86400000;

  String _ago(String? iso) {
    if (iso == null) return '-';
    final t = DateTime.parse(iso);
    final m = _now.difference(t).inMinutes;
    if (m < 1) return 'baru saja';
    if (m < 60) return '$m menit lalu';
    final days = _wibDay(_now) - _wibDay(t);
    if (days <= 0) return '${m ~/ 60} jam lalu';
    return days == 1 ? 'kemarin' : '$days hari lalu';
  }

  String _when(String iso) {
    final d = _wib(iso);
    final hm = '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
    final days = _wibDay(_now) - _wibDay(DateTime.parse(iso));
    if (days <= 0) return 'Hari ini $hm';
    if (days == 1) return 'Kemarin $hm';
    if (days < 7) return '${_weekday[d.weekday - 1]} $hm';
    return '${d.day}/${d.month} $hm';
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: V2.bg,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: top, color: Colors.white),
        V2AppBar(
          title: 'Statistik aplikasi',
          subtitle: _period == 1 ? 'Admin · hari ini' : 'Admin · $_period hari terakhir',
          back: true,
          showBell: false,
        ),
        Expanded(
          child: RefreshIndicator(
            color: V2.teal600,
            onRefresh: widget.preview != null ? () async {} : _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              children: _gap([
                _seg(),
                if (_error != null && _data == null) _message('Statistik belum bisa dimuat: $_error'),
                if (_data == null && _error == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                if (_data != null) ...[
                  _kpis(),
                  _dauCard(),
                  _pending(),
                  _features(),
                  _heat(),
                  _adoption(),
                  _downloads(),
                  _access(),
                  _security(),
                ],
              ]),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: V2BottomNav(index: -1, onTap: (i) => Navigator.of(context).pop(i)),
    );
  }

  List<Widget> _gap(List<Widget> xs) => [
        for (var i = 0; i < xs.length; i++) ...[if (i > 0) const SizedBox(height: 12), xs[i]],
      ];

  Widget _message(String s) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(14)),
        child: Text(s, style: V2.b(13, FontWeight.w400, V2.red, lh: 1.4)),
      );

  Widget _seg() {
    const items = [(1, 'Hari ini'), (7, '7 hari'), (30, '30 hari'), (90, '90 hari')];
    return Container(
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: Semantics(
              button: true,
              selected: _period == items[i].$1,
              child: GestureDetector(
                onTap: () {
                  if (_period == items[i].$1) return;
                  setState(() => _period = items[i].$1);
                  if (widget.preview == null) _load();
                },
                child: Container(
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _period == items[i].$1 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _period == items[i].$1 ? [cssShadow(const Color(0x1F0F1F1D), 0, 1, 3)] : null,
                  ),
                  child: Text(items[i].$2, style: V2.d(12, FontWeight.w600, _period == items[i].$1 ? V2.teal700 : V2.ink2, lh: 1)),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Cards ──

  Widget _card(List<Widget> children, {double gap = 12}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: V2.rule),
          boxShadow: [cssShadow(const Color(0x0A0F1F1D), 0, 4, 14)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
        ]),
      );

  Widget _ch(String title, String? sub, {Widget? trailing, VoidCallback? onTap}) {
    final head = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 20.8, child: Text(title, style: V2.d(16, FontWeight.w600, V2.ink, lh: 1.3))),
      if (sub != null) ...[
        const SizedBox(height: 2),
        SizedBox(height: 15.6, child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.b(12, FontWeight.w400, V2.mute, lh: 1.3))),
      ],
    ]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: head), if (trailing != null) trailing]),
    );
  }

  Widget _legend(List<(Color, String, bool)> items) => SizedBox(
        height: 11.5,
        child: Row(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Container(
              width: 10,
              height: items[i].$3 ? 3 : 10,
              decoration: BoxDecoration(color: items[i].$1, borderRadius: BorderRadius.circular(items[i].$3 ? 2 : 3)),
            ),
            const SizedBox(width: 6),
            Text(items[i].$2, style: V2.d(11.5, FontWeight.w500, V2.ink2, lh: 1)),
          ],
        ]),
      );

  Widget _pill(String s, Color bg, Color fg) => Container(
        height: 19,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(s, style: V2.d(11, FontWeight.w600, fg, lh: 1)),
      );

  Widget _tile(String label, Widget value, Widget em, {List<Widget> extra = const []}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: V2.rule)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(height: 15, child: Text(label, maxLines: 1, style: V2.d(12, FontWeight.w500, V2.mute, lh: 1.25))),
          const SizedBox(height: 6),
          SizedBox(height: 22, child: value),
          const SizedBox(height: 6),
          SizedBox(height: 14.95, child: em),
          ...extra,
        ]),
      );

  Widget _big(String a, [String? b]) => Text.rich(
        TextSpan(text: a, style: V2.d(20, FontWeight.w700, V2.ink, lh: 1.1), children: [
          if (b != null) TextSpan(text: ' $b', style: V2.d(14, FontWeight.w600, V2.mute, lh: 1)),
        ]),
        maxLines: 1,
      );

  Widget _em(String s, [Color c = V2.mute]) => Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(11.5, FontWeight.w500, c, lh: 1.3));

  Widget _kpis() {
    final a = (_v2['active'] as Map?) ?? const {};
    final lt = (_v2['logins_today'] as Map?) ?? const {};
    final q = (_v2['questions'] as Map?) ?? const {};
    final ad = (_v2['adoption'] as Map?) ?? const {};
    final f = (_v2['failed'] as Map?) ?? const {};
    final change = (q['change'] as num?)?.toDouble();
    final locked = _i(f['locked_accounts']);
    final on = _i(ad['devices_on_latest']), all = _i(ad['devices']);
    Widget row(Widget x, Widget y) => Row(children: [Expanded(child: x), const SizedBox(width: 8), Expanded(child: y)]);
    return Column(children: [
      row(
        _tile('Pengguna aktif', _big(_nf(_i(a['dau'])), '· ${_nf(_i(a['wau']))} · ${_nf(_i(a['mau']))}'), _em('DAU · WAU · MAU')),
        _tile('Login hari ini', _big(_nf(_i(lt['total']))), _em('Web ${_nf(_i(lt['web']))} · Android ${_nf(_i(lt['android']))}')),
      ),
      const SizedBox(height: 8),
      row(
        _tile('Pertanyaan ke agent', _big(_nf(_i(q['count']))),
            change == null ? _em(_period == 1 ? 'hari ini' : '$_period hari') : _em('${change >= 0 ? '▲' : '▼'} ${change.abs().round()}%', change >= 0 ? const Color(0xFF1F7A3A) : V2.red)),
        _tile('Login gagal', _big(_nf(_i(f['count']))), locked > 0 ? _em('$locked akun terkunci', V2.red) : _em('tidak ada akun terkunci')),
      ),
      const SizedBox(height: 8),
      _tile(
        'Adopsi versi ${ad['version'] ?? '-'}',
        _big(_nf(on), '/ ${_nf(all)} perangkat'),
        _em('${_nf(_i(ad['downloads_since_release']))} unduhan APK sejak rilis'),
        extra: [
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(children: [
                if (on > 0) Expanded(flex: on, child: Container(color: _t)),
                if (all - on > 0) Expanded(flex: all - on, child: Container(color: V2.rule2)),
                if (all == 0) Expanded(child: Container(color: V2.rule2)),
              ]),
            ),
          ),
        ],
      ),
    ]);
  }

  Widget _dauCard() {
    final d = ((_v2['daily_active'] as List?) ?? const []).cast<Map>();
    return _card([
      _ch('Pengguna aktif harian', '30 hari terakhir'),
      _legend([(_t, 'DAU', false), (_l, 'WAU', true)]),
      SizedBox(
        height: 160,
        child: CustomPaint(
          painter: _DauPainter([for (final x in d) (_i(x['dau']), _i(x['wau']))]),
          child: Semantics(label: 'Pengguna aktif harian, hari ini DAU ${d.isEmpty ? 0 : d.last['dau']}, WAU ${d.isEmpty ? 0 : d.last['wau']}'),
        ),
      ),
    ]);
  }

  Future<void> _decide(Map p, bool ok) async {
    final id = _i(p['id']);
    if (widget.preview != null) return;
    setState(() => _busy = id);
    try {
      await ApiClient.decideAccess(id, ok);
      _toast(ok ? 'Akses ${p['full_name']} disetujui. Link pembuatan password dikirim ke email.' : 'Permintaan ${p['full_name']} ditolak.');
      await _load();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _smallBtn(String label, bool primary, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? .55 : 1,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary ? _t : Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: primary ? _t : V2.rule),
            ),
            child: Text(label, style: V2.d(12, FontWeight.w600, primary ? Colors.white : V2.ink2, lh: 1)),
          ),
        ),
      );

  Widget _avatar(String name, Color c) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        child: Text(_initials(name), style: V2.d(12, FontWeight.w700, Colors.white, lh: 1)),
      );

  Widget _pending() {
    final ps = ((_v2['pending'] as List?) ?? const []).cast<Map>();
    return _card(gap: 8, [
      _ch('Menunggu persetujuan', null,
          trailing: Container(
            height: 18.5,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFFDF3E2), borderRadius: BorderRadius.circular(99)),
            child: Text('${ps.length}', style: V2.d(10.5, FontWeight.w600, const Color(0xFFB7791F), lh: 1)),
          )),
      if (ps.isEmpty)
        Container(
          padding: const EdgeInsets.only(top: 9),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: V2.rule2))),
          child: Text('Tidak ada permintaan akses baru.', style: V2.b(12.5, FontWeight.w400, V2.mute, lh: 1.4)),
        ),
      for (var i = 0; i < ps.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: V2.rule2))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _avatar(ps[i]['full_name'].toString(), _pendCol[i % _pendCol.length]),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(height: 15.6, child: Text(ps[i]['full_name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(13, FontWeight.w600, V2.ink, lh: 1.2))),
                const SizedBox(height: 2),
                SizedBox(
                  height: 14.4,
                  child: Text([ps[i]['department'], ps[i]['region']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.25)),
                ),
                const SizedBox(height: 15.6),
              ]),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 17.6),
              child: Row(children: [
                _smallBtn('Tolak', false, _busy == _i(ps[i]['id']) ? null : () => _decide(ps[i], false)),
                const SizedBox(width: 6),
                _smallBtn('Setujui', true, _busy == _i(ps[i]['id']) ? null : () => _decide(ps[i], true)),
              ]),
            ),
          ]),
        ),
    ]);
  }

  Widget _features() {
    final fs = ((_v2['features'] as List?) ?? const []).cast<Map>();
    final tps = ((_v2['topics'] as List?) ?? const []).cast<Map>();
    final top = fs.fold<int>(0, (m, f) => math.max(m, _i(f['sessions'])));
    return _card([
      _ch('Pemakaian fitur', 'Sesi per halaman'),
      Column(children: [
        for (var i = 0; i < fs.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          SizedBox(
            height: 14.4,
            child: Row(children: [
              SizedBox(
                width: 96,
                child: Text(_shortFeature[fs[i]['key']] ?? fs[i]['label'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: V2.d(12, FontWeight.w500, V2.ink, lh: 1.2)),
              ),
              const SizedBox(width: 10),
              Expanded(child: _bar(_i(fs[i]['sessions']), top, _t)),
              const SizedBox(width: 10),
              SizedBox(width: 44, child: Text(_nf(_i(fs[i]['sessions'])), textAlign: TextAlign.right, style: V2.d(12.5, FontWeight.w700, V2.ink, lh: 1))),
            ]),
          ),
        ],
      ]),
      Padding(padding: const EdgeInsets.only(top: 4), child: _topics(tps)),
    ]);
  }

  Widget _bar(int n, int top, Color c) => ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Container(
          height: 10,
          color: V2.rule2,
          child: Row(children: [
            if (n > 0) Expanded(flex: n, child: Container(decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(5)))),
            if (top - n > 0) Expanded(flex: top - n, child: const SizedBox()),
          ]),
        ),
      );

  Widget _topics(List<Map> tps) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 16) / 3 - 24;
        final small = V2.d(11.5, FontWeight.w500, V2.ink2, lh: 1.25);
        int lines(String s) {
          final tp = TextPainter(text: TextSpan(text: s, style: small), textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))
            ..layout(maxWidth: w);
          final n = tp.computeLineMetrics().length;
          tp.dispose();
          return math.max(1, n);
        }

        final ls = [for (final t in tps) lines(t['label'].toString())];
        final natural = [for (final n in ls) 19.8 + 3 + n * 14.375];
        final h = natural.fold<double>(0, math.max);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < tps.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: h + 20,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(color: _topicBg[tps[i]['key']] ?? V2.rule2, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: 19.8 + (h - natural[i]) / 2, child: Text('${_i(tps[i]['pct'])}%', style: V2.d(18, FontWeight.w700, V2.ink, lh: 1.1))),
                  const SizedBox(height: 3),
                  Text(tps[i]['label'].toString(), style: small),
                ]),
              ),
            ),
          ],
        ]);
      });

  Widget _heat() {
    final h = ((_data?['login_heatmap'] as List?) ?? const []).map((r) => [for (final v in (r as List)) _i(v)]).toList();
    final max = h.expand((r) => r).fold<int>(0, math.max);
    int lvl(int v) => v <= 0 || max == 0 ? 0 : math.max(1, (4 * v / max).round());
    final label = V2.d(10, FontWeight.w500, V2.mute, lh: 1);
    return _card([
      _ch('Aktivitas login', 'Per hari dan jam (WIB)'),
      Column(children: [
        for (var d = 0; d < 7; d++) ...[
          if (d > 0) const SizedBox(height: 2),
          SizedBox(
            height: 12,
            child: Row(children: [
              SizedBox(width: 28, child: Text(_days[d], style: label)),
              for (var k = 0; k < 24; k++) ...[
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _hc[lvl(d < h.length && k < h[d].length ? h[d][k] : 0)],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 2),
        SizedBox(
          height: 10,
          child: Row(children: [
            const SizedBox(width: 28),
            for (var k = 0; k < 24; k++) ...[
              const SizedBox(width: 2),
              Expanded(child: k % 6 == 0 ? OverflowBox(maxWidth: 40, child: Text('$k', textAlign: TextAlign.center, style: label)) : const SizedBox()),
            ],
          ]),
        ),
      ]),
    ]);
  }

  int _verGroup(String v, String? latest) {
    final a = (latest ?? '').split('.'), c = v.split('.');
    if (a.length < 2 || c.length < 2) return 2;
    final la = int.tryParse(a[0]), lb = int.tryParse(a[1]), ca = int.tryParse(c[0]), cb = int.tryParse(c[1]);
    if (la == null || lb == null || ca == null || cb == null) return 2;
    if (ca == la && cb == lb) return 0;
    if (ca == la && cb == lb - 1) return 1;
    return 2;
  }

  Widget _adoption() {
    final latest = (_data?['latest_release'] as Map?)?['version_name'] as String?;
    final parts = (latest ?? '0.0').split('.');
    final weeks = [
      for (final w in ((_data?['version_adoption'] as List?) ?? const []).cast<Map>())
        () {
          final g = [0, 0, 0];
          ((w['versions'] as Map?) ?? const {}).forEach((k, v) => g[_verGroup('$k', latest)] += _i(v));
          return g;
        }(),
    ];
    final minor = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return _card([
      _ch('Adopsi versi aplikasi', 'Perangkat per versi, per minggu'),
      _legend([(_t, '${parts[0]}.${parts.length > 1 ? parts[1] : 0}', false), (_li, '${parts[0]}.${minor - 1}.x', false), (_gr, 'Lebih lama', false)]),
      SizedBox(height: 150, child: CustomPaint(painter: _AdoptPainter(weeks))),
    ]);
  }

  Widget _downloads() {
    final d = ((_v2['downloads_14d'] as List?) ?? const []).cast<Map>();
    return _card([
      _ch('Unduhan vs instal update', 'Harian, 14 hari'),
      _legend([(_am, 'Unduhan baru', false), (_t, 'Instal update', false)]),
      SizedBox(height: 140, child: CustomPaint(painter: _BarsPainter([for (final x in d) (_i(x['downloads']), _i(x['updates']))]))),
    ]);
  }

  List<Map> get _users => ((_data?['users'] as List?) ?? const []).cast<Map>();

  String _userLine(Map u) {
    final pl = ((u['platforms'] as List?) ?? const []).map((p) => p == 'web' ? 'Web' : 'Android').toList();
    final ver = u['app_version'];
    final plat = pl.isEmpty ? '-' : '${pl.join(', ')}${pl.contains('Android') && ver != null ? ' $ver' : ''}';
    return '$plat · ${_ago(u['last_seen'] as String?)}';
  }

  Widget _state(Map u) => switch (u['state']) {
        'aktif' => _pill('Aktif', const Color(0xFFE6F4EA), const Color(0xFF1F7A3A)),
        'versi_lama' => _pill('Versi lama', const Color(0xFFFDF3E2), const Color(0xFFB7791F)),
        _ => _pill('Tidak aktif', V2.rule2, V2.mute),
      };

  Widget _userRow(Map u, int i, {bool first = false}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _userSheet(u),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: V2.rule2))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _avatar((u['full_name'] ?? u['username']).toString(), u['state'] == 'tidak_aktif' ? _gr : _rowCol[i % _rowCol.length]),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(height: 15.6, child: Text((u['full_name'] ?? u['username']).toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(13, FontWeight.w600, V2.ink, lh: 1.2))),
                const SizedBox(height: 2),
                SizedBox(height: 14.4, child: Text(_userLine(u), maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.25))),
                const SizedBox(height: 4.6),
              ]),
            ),
            const SizedBox(width: 10),
            Padding(padding: const EdgeInsets.only(top: 17.6), child: _state(u)),
          ]),
        ),
      );

  Future<void> _remind() async {
    final ids = [for (final u in ((_data?['outdated_users'] as List?) ?? const []).cast<Map>()) _i(u['id'])];
    if (ids.isEmpty || widget.preview != null) return;
    setState(() => _reminding = true);
    try {
      final n = await ApiClient.remindUsers(ids);
      _toast('Pengingat update terkirim ke $n pengguna.');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _reminding = false);
    }
  }

  Widget _access() {
    final acc = (_v2['accounts'] as Map?) ?? const {};
    final users = _users;
    final outdated = ((_data?['outdated_users'] as List?) ?? const []).length;
    return _card(gap: 12, [
      _ch('Akses pengguna', '${_nf(_i(acc['total']))} akun · ${_nf(_i(acc['outdated_devices']))} perangkat versi lama', onTap: _allUsers),
      Column(children: [
        for (var i = 0; i < math.min(_shown, users.length); i++) _userRow(users[i], i, first: i == 0),
      ]),
      Semantics(
        button: true,
        child: GestureDetector(
          onTap: outdated == 0 || _reminding ? null : _remind,
          child: Opacity(
            opacity: outdated == 0 ? .55 : 1,
            child: Container(
              height: 36,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: V2.rule)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const MIcon('bell', size: 16, color: V2.teal700),
                const SizedBox(width: 8),
                Text(_reminding ? 'Mengirim...' : 'Ingatkan update ($outdated)', style: V2.d(13, FontWeight.w600, V2.teal700, lh: 1)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Future<void> _allUsers() async {
    var q = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final s = q.toLowerCase();
        final list = _users.where((u) => s.isEmpty || '${u['full_name']} ${u['email']} ${u['username']}'.toLowerCase().contains(s)).toList();
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * .85,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Akses pengguna (${list.length})', style: V2.d(18, FontWeight.w700, V2.ink, lh: 1.3)),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => set(() => q = v),
                decoration: InputDecoration(
                  hintText: 'Cari nama atau email',
                  isDense: true,
                  prefixIcon: const Padding(padding: EdgeInsets.all(10), child: MIcon('search', size: 18, color: V2.mute)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: V2.rule)),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) => _userRow(list[i], i, first: i == 0),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _userSheet(Map u) async {
    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(a, style: V2.b(13, FontWeight.w400, V2.mute))),
            Expanded(child: Text(b.isEmpty ? '-' : b, style: V2.d(13, FontWeight.w600, V2.ink))),
          ]),
        );
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text((u['full_name'] ?? u['username']).toString(), style: V2.d(18, FontWeight.w700, V2.ink, lh: 1.3))),
              _state(u),
            ]),
            const SizedBox(height: 10),
            row('Username', '@${u['username']}'),
            row('Email', '${u['email'] ?? ''}'),
            row('Departemen', '${u['department'] ?? ''}'),
            row('Region', '${u['region'] ?? ''}'),
            row('Platform', _userLine(u).split(' · ').first),
            row('Perangkat', '${u['device_model'] ?? ''}'),
            row('Terakhir aktif', _ago(u['last_seen'] as String?)),
            row('Jumlah login', _nf(_i(u['login_count']))),
          ]),
        ),
      ),
    );
  }

  Widget _security() {
    final ev = ((_v2['security'] as List?) ?? const []).cast<Map>();
    return _card(gap: 12, [
      _ch('Login gagal dan keamanan', null),
      if (ev.isEmpty) Text('Tidak ada login gagal pada periode ini.', style: V2.b(12.5, FontWeight.w400, V2.mute, lh: 1.4)),
      if (ev.isNotEmpty)
        Column(children: [
          for (var i = 0; i < ev.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: V2.rule2))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      height: 16.25,
                      child: Text(ev[i]['title'].toString().replaceFirst(' kali salah password', ' kali salah'), maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: V2.d(13, FontWeight.w600, V2.ink, lh: 1.25)),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 14.95,
                      child: Text(
                          ev[i]['tag'] == 'terkunci'
                              ? '${_when(ev[i]['at'].toString())} · ${ev[i]['note'].toString().replaceFirst('akun ', '')}'
                              : _when(ev[i]['at'].toString()),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3)),
                    ),
                  ]),
                ),
                const SizedBox(width: 10),
                switch (ev[i]['tag']) {
                  'terkunci' => _pill('Terkunci', const Color(0xFFFDECEC), V2.red),
                  'pantau' => _pill('Pantau', const Color(0xFFFDF3E2), const Color(0xFFB7791F)),
                  _ => _pill('Diblokir', V2.rule2, V2.mute),
                },
              ]),
            ),
        ]),
    ]);
  }
}

// ── Charts: same geometry as the mockup SVGs (viewBox fitted into the box, centred) ──

typedef _Fit = ({double s, double dx, double dy});

_Fit _fit(Size size, double w, double h) {
  final s = math.min(size.width / w, size.height / h);
  return (s: s, dx: (size.width - w * s) / 2, dy: (size.height - h * s) / 2);
}

({int step, double top}) _axis(int max, int steps) {
  final m = math.max(1, max);
  final step = _nice.firstWhere((s) => s * steps >= m * 0.95, orElse: () => _nice.last);
  return (step: step, top: math.max(step * steps, ((m * 1.05) / 5).ceil() * 5).toDouble());
}

void _text(Canvas c, String s, double x, double baseline, double size, TextAlign align) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontFamily: V2.body, fontSize: size, color: V2.mute)),
    textDirection: TextDirection.ltr,
  )..layout();
  final b = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  final dx = switch (align) { TextAlign.right => -tp.width, TextAlign.center => -tp.width / 2, _ => 0.0 };
  tp.paint(c, Offset(x + dx, baseline - b));
  tp.dispose();
}

void _grid(Canvas c, _Fit f, double w, double l, double r, ({int step, double top}) ax, double Function(double) y) {
  final line = Paint()..color = V2.rule2..strokeWidth = f.s;
  for (var g = 0; g <= ax.top + 1e-9; g += ax.step) {
    final yy = f.dy + y(g.toDouble()) * f.s;
    c.drawLine(Offset(f.dx + l * f.s, yy), Offset(f.dx + (w - r) * f.s, yy), line);
    _text(c, '$g', f.dx + (l - 6) * f.s, f.dy + (y(g.toDouble()) + 3.5) * f.s, 10 * f.s, TextAlign.right);
  }
}

class _DauPainter extends CustomPainter {
  _DauPainter(this.d);
  final List<(int, int)> d;

  @override
  void paint(Canvas c, Size size) {
    const w = 330.0, h = 160.0, l = 30.0, t = 10.0, b = 22.0, r = 8.0;
    final f = _fit(size, w, h);
    final n = d.length;
    final ax = _axis(d.fold(0, (m, x) => math.max(m, math.max(x.$1, x.$2))), 3);
    double x(int i) => l + (w - l - r) * i / math.max(1, n - 1);
    double y(double v) => t + (h - t - b) * (1 - v / ax.top);
    Offset p(int i, int v) => Offset(f.dx + x(i) * f.s, f.dy + y(v.toDouble()) * f.s);
    _grid(c, f, w, l, r, ax, y);
    if (n == 0) return;
    final dau = Path()..moveTo(p(0, d[0].$1).dx, p(0, d[0].$1).dy);
    for (var i = 1; i < n; i++) {
      dau.lineTo(p(i, d[i].$1).dx, p(i, d[i].$1).dy);
    }
    final area = Path.from(dau)
      ..lineTo(p(n - 1, 0).dx, p(n - 1, 0).dy)
      ..lineTo(p(0, 0).dx, p(0, 0).dy)
      ..close();
    c.drawPath(area, Paint()..color = _t.withValues(alpha: .10));
    final wau = Path()..moveTo(p(0, d[0].$2).dx, p(0, d[0].$2).dy);
    for (var i = 1; i < n; i++) {
      wau.lineTo(p(i, d[i].$2).dx, p(i, d[i].$2).dy);
    }
    final dash = Paint()
      ..color = _l
      ..strokeWidth = 2 * f.s
      ..style = PaintingStyle.stroke;
    for (final m in wau.computeMetrics()) {
      var dist = 0.0;
      while (dist < m.length) {
        c.drawPath(m.extractPath(dist, math.min(dist + 5 * f.s, m.length)), dash);
        dist += 9 * f.s;
      }
    }
    c.drawPath(dau, Paint()
      ..color = _t
      ..strokeWidth = 2.2 * f.s
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round);
    for (final (v, col, rad) in [(d[n - 1].$1, _t, 4.0), (d[n - 1].$2, _l, 3.5)]) {
      c.drawCircle(p(n - 1, v), (rad + 1) * f.s, Paint()..color = Colors.white);
      c.drawCircle(p(n - 1, v), (rad - 1) * f.s, Paint()..color = col);
    }
    if (n == 30) {
      for (final (i, s) in [(0, '30 hari lalu'), (8, '21'), (15, '14'), (22, '7'), (29, 'Hari ini')]) {
        _text(c, s, f.dx + x(i) * f.s, f.dy + (h - 5) * f.s, 10 * f.s, i == 0 ? TextAlign.left : i == 29 ? TextAlign.right : TextAlign.center);
      }
    }
  }

  @override
  bool shouldRepaint(_DauPainter old) => old.d != d;
}

class _AdoptPainter extends CustomPainter {
  _AdoptPainter(this.weeks);
  final List<List<int>> weeks;

  @override
  void paint(Canvas c, Size size) {
    const w = 330.0, h = 150.0, l = 30.0, t = 10.0, b = 22.0, r = 8.0;
    final f = _fit(size, w, h);
    final n = weeks.length;
    final ax = _axis(weeks.fold(0, (m, g) => math.max(m, g[0] + g[1] + g[2])), 2);
    double x(int i) => l + (w - l - r) * i / math.max(1, n - 1);
    double y(double v) => t + (h - t - b) * (1 - v / ax.top);
    _grid(c, f, w, l, r, ax, y);
    if (n > 1) {
      final lo = List<double>.filled(n, 0);
      for (final (k, col) in [(2, _gr), (1, _li), (0, _t)]) {
        final hi = [for (var i = 0; i < n; i++) lo[i] + weeks[i][k]];
        final path = Path()..moveTo(f.dx + x(0) * f.s, f.dy + y(hi[0]) * f.s);
        for (var i = 1; i < n; i++) {
          path.lineTo(f.dx + x(i) * f.s, f.dy + y(hi[i]) * f.s);
        }
        for (var i = n - 1; i >= 0; i--) {
          path.lineTo(f.dx + x(i) * f.s, f.dy + y(lo[i]) * f.s);
        }
        path.close();
        c.drawPath(path, Paint()..color = col.withValues(alpha: .9));
        for (var i = 0; i < n; i++) {
          lo[i] = hi[i];
        }
      }
    }
    for (var i = 0; i < n; i++) {
      final s = i == n - 1 ? 'Kini' : i == 0 ? '${n - 1} mg' : '${n - 1 - i}';
      _text(c, s, f.dx + x(i) * f.s, f.dy + (h - 5) * f.s, 10 * f.s, i == 0 ? TextAlign.left : i == n - 1 ? TextAlign.right : TextAlign.center);
    }
  }

  @override
  bool shouldRepaint(_AdoptPainter old) => old.weeks != weeks;
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.d);
  final List<(int, int)> d;

  @override
  void paint(Canvas c, Size size) {
    const w = 330.0, h = 140.0, l = 30.0, t = 10.0, b = 22.0, r = 8.0;
    final f = _fit(size, w, h);
    final n = d.length;
    final ax = _axis(d.fold(0, (m, x) => math.max(m, math.max(x.$1, x.$2))), 2);
    final bw = (w - l - r) / math.max(1, n);
    double y(double v) => t + (h - t - b) * (1 - v / ax.top);
    _grid(c, f, w, l, r, ax, y);
    for (var i = 0; i < n; i++) {
      final x0 = l + i * bw + bw * .18, bwid = bw * .3;
      for (final (v, x1, col) in [(d[i].$1, x0, _am), (d[i].$2, x0 + bwid + 1.5, _t)]) {
        if (v <= 0) continue;
        final rect = Rect.fromLTWH(f.dx + x1 * f.s, f.dy + y(v.toDouble()) * f.s, bwid * f.s, (y(0) - y(v.toDouble())) * f.s);
        c.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(2 * f.s)), Paint()..color = col);
      }
    }
    if (n == 14) {
      for (final (i, s) in [(0, '14 hari lalu'), (7, '7'), (13, 'Hari ini')]) {
        _text(c, s, f.dx + (l + i * bw + bw / 2) * f.s, f.dy + (h - 5) * f.s, 10 * f.s, i == 0 ? TextAlign.left : i == 13 ? TextAlign.right : TextAlign.center);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.d != d;
}
