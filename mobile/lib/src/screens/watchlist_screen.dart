// Redesign v2 page 07 (Android): Alert dan Watchlist, opened from the bell in
// every app bar. Tabs Alert aktif / Watchlist / Riwayat, a status summary,
// active alert cards with Tanya agent / Peta / Ditangani, and the watches
// that need attention first. Backed by /api/watchlist/*.
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../ui/chart.dart' show monthsId, toNum;
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../ui/mock_icons.dart';
import '../ui/v2.dart';

const _amber = Color(0xFFB7791F);
const _stripeW = Color(0xFFF5A623);

/// Status pill colours and labels (web .st2).
const _st = <String, (Color, Color, String)>{
  'kritis': (Color(0xFFFDECEC), V2.red, 'Kritis'),
  'peringatan': (Color(0xFFFDF3E2), _amber, 'Peringatan'),
  'normal': (Color(0xFFE6F4EA), Color(0xFF1F7A3A), 'Normal'),
  'nonaktif': (V2.rule2, V2.mute, 'Nonaktif'),
  'nodata': (V2.rule2, V2.mute, 'Tanpa data'),
  'error': (V2.rule2, V2.mute, 'Tanpa data'),
  'baru': (V2.rule2, V2.mute, 'Menunggu'),
};

/// Icon tile colours: Performance per metric, the other groups one colour each.
(Color, Color) _tone(Map<String, dynamic> r) {
  switch (r['group']) {
    case 'prod':
      return (const Color(0xFFF4FCE3), V2.lime700);
    case 'prof':
      return (const Color(0xFFFBE2DA), const Color(0xFFB5401F));
  }
  return switch (r['metric']) {
    'payload' => (const Color(0xFFE3F7FA), const Color(0xFF0E6F7C)),
    'revenue' || 'rev_data' || 'fwa_revenue' => (const Color(0xFFFCEDD3), _amber),
    'availability' => (const Color(0xFFECE5FA), const Color(0xFF6A4CB5)),
    'gross_add' || 'fwa_rgu' => (const Color(0xFFE1ECFA), const Color(0xFF2C6CB0)),
    _ => (V2.teal50, V2.teal700),
  };
}

/// Watch metric -> Peta Agent layer; metrics without a layer get no "Peta" action.
const _mapMetric = {
  'payload': 'payload_mom', 'revenue': 'revenue_mom', 'availability': 'availability', 'rev_site': 'rev_site',
  'rgu_site': 'rgu_site', 'vlr_site': 'vlr_site', 'market_share': 'market_share', 'subs': 'subs',
  'gross_add': 'gross_add', 'fwa_pen': 'fwa_pen',
};

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({
    super.key,
    this.previewAlerts,
    this.previewRules,
    this.previewNow,
    this.onAsk,
    this.onCountChanged,
    this.onNav,
    this.onOpenMap,
  });

  /// Alerts and rules to render instead of fetching (golden tests).
  final List<Map<String, dynamic>>? previewAlerts;
  final List<Map<String, dynamic>>? previewRules;
  final DateTime? previewNow;

  /// Sends a question to the Agent tab.
  final void Function(String question)? onAsk;

  /// Reports the number of open, unhandled alerts (for the bell badge).
  final ValueChanged<int>? onCountChanged;

  /// Bottom nav tap: closes this screen and switches to that tab.
  final ValueChanged<int>? onNav;

  /// Opens the Peta tab on a kabupaten with a metric layer.
  final void Function(String kabupaten, String metric)? onOpenMap;

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen> {
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _rules = [];
  Map<String, dynamic>? _meta;
  bool _loading = false;
  String? _error;
  int _tab = 0;
  String? _filter; // kritis | peringatan | near

  bool get _preview => widget.previewAlerts != null;
  DateTime get _now => widget.previewNow ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (_preview) {
      _alerts = widget.previewAlerts!;
      _rules = widget.previewRules ?? [];
    } else {
      reload();
    }
  }

  Future<void> reload() async {
    if (_preview) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([ApiClient.watchAlerts(status: 'all'), ApiClient.watchRules()]);
      if (!mounted) return;
      setState(() {
        _alerts = res[0].cast<Map<String, dynamic>>();
        _rules = res[1].cast<Map<String, dynamic>>();
      });
      widget.onCountChanged?.call(_open.length);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _open =>
      _alerts.where((a) => a['resolved'] != true && a['acknowledged'] != true && a['severity'] != 'pulih').toList();
  List<Map<String, dynamic>> get _active => _rules.where((r) => r['active'] != false).toList();
  int _count(String s) => _active.where((r) => s == 'near' ? r['near'] == true : r['status'] == s).length;

  /// Watches that need attention first: critical, warning, then near the threshold
  /// (closest to it first). Ties keep the server order.
  List<Map<String, dynamic>> get _top {
    int rank(Map<String, dynamic> r) => r['status'] == 'kritis' ? 0 : r['status'] == 'peringatan' ? 1 : r['near'] == true ? 2 : 3;
    double gap(Map<String, dynamic> r) {
      final v = toNum(r['value']), t = toNum(r['trend_threshold']);
      return v == null || t == null || t == 0 ? double.infinity : (v - t).abs() / t.abs();
    }
    final xs = _active.where((r) => rank(r) < 3).toList();
    final order = {for (var i = 0; i < xs.length; i++) xs[i]: i};
    xs.sort((a, b) {
      if (rank(a) != rank(b)) return rank(a) - rank(b);
      if (rank(a) == 2 && gap(a) != gap(b)) return gap(a).compareTo(gap(b));
      return order[a]! - order[b]!;
    });
    return xs.take(5).toList();
  }

  /// Opens "Pantauan baru", prefilled from an agent question when given.
  Future<void> createFrom([String? question]) async {
    _meta ??= _preview ? null : await ApiClient.watchMeta().catchError((_) => <String, dynamic>{});
    if (!mounted) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _RuleSheet(meta: _meta ?? const {}, question: question),
    );
    if (body == null) return;
    try {
      await ApiClient.createWatchRule(body);
      if (!mounted) return;
      showToast(context, 'Pantauan disimpan. Agent memeriksanya setiap hari.');
      setState(() => _tab = 1);
      reload();
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final open = _open.length;
    return Scaffold(
      backgroundColor: V2.bg,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: top, color: Colors.white),
        V2AppBar(
          title: 'Alert dan Watchlist',
          subtitle: '$open alert aktif · ${_rules.length} pantauan',
          subtitleDot: open > 0 ? V2.red : const Color(0xFF2E9E57),
          back: true,
          showBell: false,
        ),
        _tabs(open),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: RefreshIndicator(
                color: V2.teal600,
                onRefresh: reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
                  children: switch (_tab) { 0 => _alertTab(), 1 => _watchTab(), _ => _historyTab() },
                ),
              ),
            ),
            Positioned(right: 16, bottom: 16, child: _fab()),
          ]),
        ),
      ]),
      bottomNavigationBar: V2BottomNav(
        index: -1,
        onTap: (i) {
          Navigator.of(context).maybePop();
          widget.onNav?.call(i);
        },
      ),
    );
  }

  Widget _tabs(int open) {
    Widget tab(int i, String label, [int? n]) {
      final on = _tab == i;
      return Semantics(
        selected: on,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _tab = i),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? V2.teal600 : Colors.transparent, width: 2.5))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2.5),
                child: Text(label, style: V2.d(13, FontWeight.w600, on ? V2.teal700 : V2.mute, lh: 1)),
              ),
              if (n != null) ...[
                const SizedBox(width: 7),
                Container(
                  height: 17,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: on ? V2.teal600 : V2.rule2, borderRadius: BorderRadius.circular(99)),
                  child: Text('$n', style: V2.d(11, FontWeight.w700, on ? Colors.white : V2.ink2, lh: 1)),
                ),
              ],
            ]),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: V2.rule))),
      child: Row(children: [
        tab(0, 'Alert aktif', open),
        const SizedBox(width: 4),
        tab(1, 'Watchlist', _rules.length),
        const SizedBox(width: 4),
        tab(2, 'Riwayat'),
      ]),
    );
  }

  List<Widget> _gap(List<Widget> xs) => [
        for (var i = 0; i < xs.length; i++) ...[if (i > 0) const SizedBox(height: 12), xs[i]],
      ];

  Widget? _status() {
    if (_rules.isEmpty && _loading) return const Skeleton(height: 120, radius: 16);
    if (_error != null && _rules.isEmpty && _alerts.isEmpty) return InlineMessage(_error!, onRetry: reload);
    return null;
  }

  // ── Alert aktif ──

  List<Widget> _alertTab() {
    final st = _status();
    if (st != null) return [st];
    final open = _open;
    final top = _top;
    return _gap([
      _summary(),
      if (open.isEmpty) _empty('Tidak ada alert aktif. Semua pantauan dalam ambang.'),
      for (final a in open) _alertCard(a),
      if (top.isNotEmpty) _glab('Pantauan teratas'),
      for (final r in top) _row(r),
      if (_rules.isNotEmpty) _more('Lihat ${_rules.length} pantauan', () => setState(() => _tab = 1)),
    ]);
  }

  Widget _summary() {
    Widget cell(String key, String label, Color c) {
      final on = _filter == key;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _filter = on ? null : key;
            _tab = 1;
          }),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? V2.ink : V2.rule),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_count(key)}', style: V2.d(20, FontWeight.w700, c, lh: 1.1)),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(11, FontWeight.w500, V2.mute, lh: 1.2)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      cell('kritis', 'Kritis', V2.red),
      const SizedBox(width: 8),
      cell('peringatan', 'Peringatan', _amber),
      const SizedBox(width: 8),
      cell('near', 'Mendekati', V2.ink),
    ]);
  }

  String _ago(String? iso) {
    final t = DateTime.tryParse(iso ?? '');
    if (t == null) return '';
    final m = _now.difference(t).inMinutes;
    if (m < 1) return 'baru saja';
    if (m < 60) return '$m mnt';
    if (m < 60 * 24) return '${m ~/ 60} jam';
    return '${m ~/ (60 * 24)} hari';
  }

  Widget _tx(String s, TextStyle st) => V2Lines(TextSpan(text: s, style: st), lineHeight: st.fontSize! * st.height!, dy: 0);

  Widget _alertCard(Map<String, dynamic> a) {
    final k = a['severity'] == 'kritis';
    final fg = k ? V2.red : _amber;
    final tint = k ? const Color(0xFFFDECEC) : const Color(0xFFFDF3E2);
    final metric = _mapMetric[a['metric']];
    final kab = a['kabupaten']?.toString();
    final canMap = metric != null && kab != null && kab.isNotEmpty;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: V2.rule)),
      child: Stack(children: [
        Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: k ? V2.red : _stripeW)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)),
              child: MIcon(k ? 'warn' : 'info', size: 18, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: _tx((a['title'] ?? '').toString(), V2.d(13.5, FontWeight.w600, V2.ink, lh: 1.3))),
                  const SizedBox(width: 8),
                  Text(_ago(a['created_at']?.toString()), style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3)),
                ]),
                const SizedBox(height: 4),
                _tx((a['message'] ?? '').toString(), V2.b(12.5, FontWeight.w400, V2.ink2, lh: 1.4)),
                const SizedBox(height: 4),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(99)),
                    child: Text(k ? 'Kritis' : 'Peringatan', style: V2.d(11, FontWeight.w600, fg, lh: 1)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text((a['group_label'] ?? '').toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(11.5, FontWeight.w500, V2.mute, lh: 1)),
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _act('spark', 'Tanya agent', primary: true, onTap: () => _ask(a)),
                  if (canMap) ...[const SizedBox(width: 5), _act('map', 'Peta', onTap: () => _openMap(kab, metric))],
                  const SizedBox(width: 5),
                  _act('check', 'Ditangani', onTap: () => _handled(a)),
                ]),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _act(String icon, String label, {bool primary = false, required VoidCallback onTap}) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: primary ? V2.teal600 : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primary ? V2.teal600 : V2.rule),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MIcon(icon, size: 12, color: primary ? Colors.white : V2.teal700),
              const SizedBox(width: 4),
              Text(label, style: V2.d(11, FontWeight.w600, primary ? Colors.white : V2.teal700, lh: 1)),
            ]),
          ),
        ),
      );

  void _ask(Map<String, dynamic> a) {
    final q = 'Kenapa ${a['title'] ?? ''}? ${a['message'] ?? ''}'.trim();
    Navigator.of(context).maybePop();
    widget.onAsk?.call(q);
  }

  void _openMap(String? kab, String? metric) {
    if (kab == null || metric == null) return;
    Navigator.of(context).maybePop();
    widget.onOpenMap?.call(kab, metric);
  }

  Future<void> _handled(Map<String, dynamic> a) async {
    if (a['id'] is! int) return;
    setState(() {
      a['acknowledged'] = true;
      a['acknowledged_at'] = DateTime.now().toUtc().toIso8601String();
    });
    widget.onCountChanged?.call(_open.length);
    try {
      await ApiClient.ackAlert(a['id'] as int);
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  Widget _glab(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
        child: Text(s.toUpperCase(), style: V2.d(11, FontWeight.w600, V2.teal700, lh: 1, ls: .06)),
      );

  Widget _more(String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13), border: Border.all(color: V2.rule)),
          child: Text(label, style: V2.d(13, FontWeight.w600, V2.teal700, lh: 1)),
        ),
      );

  Widget _empty(String s) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: V2.rule)),
        child: Text(s, style: V2.b(13, FontWeight.w400, V2.mute, lh: 1.45)),
      );

  Widget _pill(String status) {
    final (bg, fg, label) = _st[status] ?? _st['baru']!;
    return Container(
      height: 21,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: V2.d(11, FontWeight.w600, fg, lh: 1)),
      ]),
    );
  }

  /// One watch: icon, title, scope and threshold, current value and status.
  Widget _row(Map<String, dynamic> r) {
    final (bg, fg) = _tone(r);
    final status = r['active'] == false ? 'nonaktif' : (r['status'] ?? 'baru').toString();
    final sub = [r['scope_label'], r['threshold_label']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
    return GestureDetector(
      onTap: () => _ruleActions(r),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: V2.rule)),
        // Two grid rows like the mockup: when the value column is taller, the
        // spare height is shared between the title row and the scope row.
        child: Row(children: [
            Center(
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: MIcon((r['micon'] ?? 'pulse').toString(), size: 16, color: fg),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              // At least as tall as the value column (14 px value, 4 gap, 21 px pill).
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40.4),
                child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.spaceAround, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text((r['title'] ?? r['metric_label'] ?? '').toString(),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(13, FontWeight.w600, V2.ink, lh: 1.25)),
                ),
                Padding(padding: const EdgeInsets.only(top: 2), child: _tx(sub, V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3))),
              ]),
              ),
            ),
            const SizedBox(width: 10),
            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text((r['value_label'] ?? '-').toString(), style: V2.d(14, FontWeight.w700, V2.ink, lh: 1.1)),
              const SizedBox(height: 4),
              _pill(status),
            ]),
          ]),
      ),
    );
  }

  // ── Watchlist ──

  List<Widget> _watchTab() {
    final st = _status();
    if (st != null) return [st];
    if (_rules.isEmpty) {
      return [_empty('Belum ada pantauan. Ketuk Pantauan baru, atau tekan Pantau di jawaban agent.')];
    }
    bool keep(Map<String, dynamic> r) => _filter == null ||
        (r['active'] != false && (_filter == 'near' ? r['near'] == true : r['status'] == _filter));
    final out = <Widget>[_summary()];
    for (final (g, label) in const [('perf', 'Performance'), ('prod', 'Site productivity'), ('prof', 'Profile wilayah')]) {
      final rows = _rules.where((r) => (r['group'] ?? 'perf') == g && keep(r)).toList();
      if (rows.isEmpty) continue;
      out.add(_glab('$label · ${rows.length}'));
      out.addAll(rows.map(_row));
    }
    if (out.length == 1) out.add(_empty('Tidak ada pantauan dengan status ini.'));
    if (_filter != null) out.add(_more('Tampilkan semua pantauan', () => setState(() => _filter = null)));
    return _gap(out);
  }

  Future<void> _ruleActions(Map<String, dynamic> r) async {
    if (_preview) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Widget sw(String key, String label) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: r[key] == true,
              activeThumbColor: Colors.white,
              activeTrackColor: V2.teal600,
              onChanged: (v) {
                set(() => r[key] = v);
                _patch(r, {key: v});
              },
              title: Text(label, style: V2.d(14, FontWeight.w500, V2.ink)),
            );
        final active = r['active'] != false;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 16),
              Text((r['title'] ?? '').toString(), style: V2.d(18, FontWeight.w700, V2.ink, lh: 1.3)),
              const SizedBox(height: 4),
              Text('${r['scope_label'] ?? ''} · ${r['threshold_label'] ?? ''} ${r['threshold_sub'] ?? ''}'.trim(),
                  style: V2.b(13, FontWeight.w400, V2.mute, lh: 1.4)),
              const SizedBox(height: 8),
              sw('notify_inapp', 'Notifikasi in-app'),
              sw('notify_email', 'Email'),
              sw('notify_push', 'Push Android'),
              const SizedBox(height: 8),
              PrimaryButton(active ? 'Jeda pemantauan' : 'Lanjutkan pemantauan', color: V2.rule2, fg: V2.ink, onTap: () {
                Navigator.pop(ctx);
                _patch(r, {'active': !active});
              }),
              const SizedBox(height: 10),
              PrimaryButton('Hapus pantauan', color: const Color(0xFFFDECEC), fg: V2.red, onTap: () {
                Navigator.pop(ctx);
                _delete(r);
              }),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _patch(Map<String, dynamic> r, Map<String, dynamic> patch) async {
    try {
      await ApiClient.updateWatchRule(r['id'] as int, patch);
      if (patch.containsKey('active')) reload();
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Hapus pantauan ini?', style: V2.d(18, FontWeight.w700, V2.ink)),
        content: Text('Agent berhenti memantau ${r['title']} ${r['scope_label']}. Riwayat alertnya ikut terhapus.',
            style: V2.b(14, FontWeight.w400, V2.ink2, lh: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Batal', style: V2.d(14, FontWeight.w600, V2.ink2))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Hapus', style: V2.d(14, FontWeight.w600, V2.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.deleteWatchRule(r['id'] as int);
      reload();
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  // ── Riwayat ──

  List<Widget> _historyTab() {
    final st = _status();
    if (st != null) return [st];
    final xs = _alerts.where((a) => a['severity'] != 'pulih').toList();
    if (xs.isEmpty) return [_empty('Belum ada alert.')];
    return _gap([for (final a in xs) _historyRow(a)]);
  }

  String _when(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    return '${t.day} ${monthsId[t.month - 1]}, ${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';
  }

  Widget _historyRow(Map<String, dynamic> a) {
    final open = a['resolved'] != true && a['acknowledged'] != true;
    final acked = a['acknowledged'] == true;
    final (bg, fg) = open
        ? (a['severity'] == 'kritis' ? (const Color(0xFFFDECEC), V2.red) : (const Color(0xFFFDF3E2), _amber))
        : (const Color(0xFFE6F4EA), const Color(0xFF1F7A3A));
    final label = open ? 'Aktif' : acked ? (a['resolved'] == true ? 'Selesai' : 'Ditangani') : 'Selesai otomatis';
    final by = open
        ? 'Belum ditangani'
        : acked
            ? 'Ditangani ${_when(a['acknowledged_at']?.toString())}'
            : 'Kembali normal ${_when(a['resolved_at']?.toString()).split(',').first}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: V2.rule)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a['rule_title'] ?? a['title'] ?? ''}${a['scope_label'] != null ? ' · ${a['scope_label']}' : ''}',
                style: V2.d(13, FontWeight.w600, V2.ink, lh: 1.25)),
            const SizedBox(height: 4),
            Text('${_when(a['created_at']?.toString())} · $by', style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3)),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text((a['value_label'] ?? '-').toString(), style: V2.d(14, FontWeight.w700, V2.ink, lh: 1.1)),
          const SizedBox(height: 4),
          Container(
            height: 21,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
            child: Text(label, style: V2.d(11, FontWeight.w600, fg, lh: 1)),
          ),
        ]),
      ]),
    );
  }

  Widget _fab() => Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: [cssShadow(const Color(0x590E8579), 0, 10, 24)]),
        child: Material(
          color: V2.teal600,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => createFrom(),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const MIcon('plus', size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text('Pantauan baru', style: V2.d(14, FontWeight.w600, Colors.white, lh: 1)),
              ]),
            ),
          ),
        ),
      );
}

/// "Pantauan baru" form: metric, territory, condition and threshold.
class _RuleSheet extends StatefulWidget {
  const _RuleSheet({required this.meta, this.question});
  final Map<String, dynamic> meta;
  final String? question;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  static const _fallbackMetrics = [
    {'key': 'revenue', 'label': 'Revenue'},
    {'key': 'payload', 'label': 'Payload data'},
    {'key': 'subs', 'label': 'Pelanggan aktif (RGU 90D)'},
    {'key': 'gross_add', 'label': 'Gross add'},
    {'key': 'availability', 'label': 'Site availability 4G'},
  ];
  static const _levels = [('circle', 'Circle Java'), ('region', 'Region'), ('branch', 'Branch'), ('kabkota', 'Kab/Kota')];
  static const _conditions = [('turun', 'Turun'), ('naik', 'Naik'), ('berubah', 'Berubah'), ('di_bawah', 'Di bawah'), ('di_atas', 'Di atas')];

  late String _metric;
  String _level = 'circle';
  String _condition = 'turun';
  final _scope = TextEditingController();
  final _threshold = TextEditingController(text: '5');
  int _days = 1;
  bool _email = false;
  bool _push = true;

  List<Map> get _metrics => ((widget.meta['metrics'] as List?) ?? _fallbackMetrics).cast<Map>();

  @override
  void initState() {
    super.initState();
    // Guess the metric and territory from the agent's question.
    final q = (widget.question ?? '').toLowerCase();
    _metric = q.contains('payload') ? 'payload'
        : q.contains('gross add') ? 'gross_add'
        : q.contains('availability') || q.contains('site') ? 'availability'
        : q.contains('pelanggan') || q.contains('rgu') ? 'subs'
        : 'revenue';
    if (_metric == 'availability') { _condition = 'di_bawah'; _threshold.text = '99'; }
    for (final (pat, r) in [('west java|jawa barat|jabar', 'WEST JAVA'), ('central java|jawa tengah|jateng', 'CENTRAL JAVA'), ('east java|jawa timur|jatim', 'EAST JAVA')]) {
      if (RegExp(pat).hasMatch(q)) { _level = 'region'; _scope.text = r; }
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    _threshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final unit = _condition.startsWith('di_') ? (_metric == 'availability' ? '%' : '') : (_metric == 'availability' ? 'pp' : '%');
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(t, style: ts(13, w600, p.text2)));
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.rule));
    InputDecoration deco(String hint, {String? suffix}) => InputDecoration(
          isDense: true,
          filled: true,
          fillColor: p.surface,
          hintText: hint,
          suffixText: suffix,
          hintStyle: ts(14, w400, p.mute),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: BorderSide(color: p.teal600, width: 1.5)),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: SheetHandle()),
            const SizedBox(height: 16),
            Text('Pantauan baru', style: ts(18, w700, p.ink, lh: 1.35)),
            if (widget.question != null) ...[
              const SizedBox(height: 4),
              Text('Dari pertanyaan: "${widget.question}"', maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(12, w400, p.mute)),
            ],
            label('Metrik'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in _metrics)
                PillChip(m['label'].toString(), selected: _metric == m['key'], onTap: () => setState(() => _metric = m['key'].toString())),
            ]),
            label('Wilayah'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (k, l) in _levels) PillChip(l, selected: _level == k, onTap: () => setState(() => _level = k)),
            ]),
            if (_level != 'circle') ...[
              const SizedBox(height: 8),
              TextField(controller: _scope, textCapitalization: TextCapitalization.characters, style: ts(14, w400, p.ink),
                  decoration: deco(_level == 'region' ? 'mis. WEST JAVA' : _level == 'branch' ? 'mis. BANDUNG' : 'mis. GARUT')),
            ],
            label('Kondisi'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (k, l) in _conditions) PillChip(l, selected: _condition == k, onTap: () => setState(() => _condition = k)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _threshold,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: ts(14, w400, p.ink),
                  decoration: deco('Ambang', suffix: unit),
                ),
              ),
              const SizedBox(width: 12),
              Text('selama', style: ts(13, w400, p.text2)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _days,
                underline: const SizedBox(),
                dropdownColor: p.surface,
                style: ts(14, w600, p.ink),
                items: [for (final d in const [1, 2, 3, 5, 7]) DropdownMenuItem(value: d, child: Text('$d hari'))],
                onChanged: (v) => setState(() => _days = v ?? 1),
              ),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _email,
              activeThumbColor: Colors.white,
              activeTrackColor: p.teal600,
              onChanged: (v) => setState(() => _email = v),
              title: Text('Kirim juga ke email', style: ts(14, w500, p.ink)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _push,
              activeThumbColor: Colors.white,
              activeTrackColor: p.teal600,
              onChanged: (v) => setState(() => _push = v),
              title: Text('Notifikasi di HP (Push Android)', style: ts(14, w500, p.ink)),
            ),
            const SizedBox(height: 8),
            PrimaryButton('Simpan pantauan', icon: Icx.bellRing, onTap: () {
              final t = double.tryParse(_threshold.text.replaceAll(',', '.'));
              if (t == null || (_level != 'circle' && _scope.text.trim().isEmpty)) {
                showToast(context, 'Lengkapi wilayah dan ambang.', ok: false);
                return;
              }
              Navigator.pop(context, {
                'metric': _metric,
                'scope_level': _level,
                'scope_value': _level == 'circle' ? 'JAVA' : _scope.text.trim().toUpperCase(),
                'condition': _condition,
                'threshold': t,
                'days': _days,
                'notify_inapp': true,
                'notify_email': _email,
                'notify_push': _push,
                if (widget.question != null) 'source_question': widget.question,
              });
            }),
          ]),
        ),
      ),
    );
  }
}
