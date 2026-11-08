import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../api/api_client.dart';
import '../ui/answer_v2.dart' show Triangle;
import '../ui/chart.dart' show formatValue, idNum, shortNum, toNum;
import '../ui/mock_icons.dart';
import '../ui/v2.dart';
import 'v3/v3_entry.dart';

/// Android · Dashboard (Redesign v2, design/mockup-v2/03-dashboard): period
/// switch and region chip, the agent's summary hero, four KPI cards with
/// sparklines, revenue per region as grouped bars with a tap-to-read tooltip,
/// active alerts and target achievement per region.
/// Numbers come from GET /api/dashboard/overview (dump Performance when fresh)
/// and the open alerts from GET /api/watchlist/alerts.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.preview,
    this.previewAlerts,
    this.previewNow,
    this.onAsk,
    this.onAlerts,
    this.onPerformance,
  });

  /// Overview payload and alerts to render instead of fetching (golden tests).
  final Map<String, dynamic>? preview;
  final List<Map<String, dynamic>>? previewAlerts;
  final DateTime? previewNow;

  /// Sends a question to the Agent tab.
  final void Function(String question)? onAsk;

  /// Opens Watchlist dan Alert.
  final VoidCallback? onAlerts;

  /// Switches to the Performa tab.
  final VoidCallback? onPerformance;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

const _green = Color(0xFF1F7A3A);
const _amber = Color(0xFFF5A623);
const _amberInk = Color(0xFFB7791F);

class _Look {
  const _Look(this.label, this.icon, this.bg, this.fg, this.spark);
  final String label, icon;
  final Color bg, fg, spark;
}

// Same icon tiles and spark colors as the web dashboard (KPI_LOOK); the phone
// cards use the short labels of the mockup.
const _looks = {
  'revenue': _Look('Revenue', 'wallet', Color(0xFFFCEDD3), _amberInk, V2.teal600),
  'subs': _Look('Pelanggan', 'users', Color(0xFFE1ECFA), Color(0xFF2C6CB0), Color(0xFF1597A8)),
  'payload': _Look('Payload', 'db', Color(0xFFE3F7FA), Color(0xFF0E6F7C), V2.teal600),
  'availability': _Look('Availability', 'tower', Color(0xFFECE5FA), Color(0xFF6A4CB5), V2.teal600),
  'gross_add': _Look('Gross add', 'users', Color(0xFFE6F4EA), _green, V2.teal600),
};

const _extra = [Color(0xFFFF7A59), _amberInk, Color(0xFFC23A5B), Color(0xFF2C6CB0), Color(0xFF5E8A12)];

Color regionColor(String name, int i) {
  final n = name.toLowerCase();
  if (n.contains('east') || n.contains('timur')) return V2.teal600;
  if (n.contains('central') || n.contains('tengah')) return V2.lagoon;
  if (n.contains('west') || n.contains('barat')) return const Color(0xFF6A4CB5);
  return _extra[i % _extra.length];
}

/// "EAST JAVA" → "East Java".
String titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ')
    .replaceAll(RegExp(r'\bDiy\b'), 'DIY');

final _f1 = NumberFormat('#,##0.0', 'id');
final _f2 = NumberFormat('#,##0.00', 'id');

/// "Rp 788,0 M", "Rp 1,84 T".
String rpM(double v) => v.abs() >= 1e12 ? 'Rp ${_f2.format(v / 1e12)} T' : 'Rp ${_f1.format(v / 1e9)} M';

String fmtKpi(String? format, dynamic v) {
  final n = toNum(v);
  if (n == null) return '–';
  switch (format) {
    case 'currency':
      return formatValue(n, 'currency');
    case 'gb':
      if (n >= 1e6) return '${idNum(n / 1e6, 1)} PB';
      if (n >= 1e3) return '${idNum(n / 1e3, 1)} TB';
      return '${idNum(n, 1)} GB';
    case 'percent':
      return '${idNum(n, 2)}%';
    default:
      return shortNum(n);
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _alerts = const [];
  String? _error;
  bool _loading = false;
  String _region = '';
  int _grain = 0; // 0 Harian, 1 Mingguan, 2 Bulanan
  int? _hover;
  List<bool> _on = const [];

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _data = widget.preview;
      _alerts = widget.previewAlerts ?? const [];
    } else {
      _load();
    }
  }

  DateTime get _now => widget.previewNow ?? DateTime.now();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Future.wait([
        ApiClient.dashboardOverview(region: _region),
        ApiClient.watchAlerts(status: 'open').catchError((_) => <dynamic>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _data = res[0] as Map<String, dynamic>;
        _alerts = (res[1] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _hover = null;
        _on = const [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _scopeName => _region.isEmpty ? 'Circle Java' : titleCase(_region);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final scope = V2Scope.maybeOf(context);
    final d = _data;
    final month = (d?['month_label'] ?? '').toString();
    return ColoredBox(
      color: V2.bg,
      child: Column(children: [
        SizedBox(height: top),
        V2AppBar(
          title: 'Dashboard',
          subtitle: month.isEmpty ? _scopeName : '$_scopeName · $month',
          subtitleDot: _loading ? const Color(0xFFE0A100) : const Color(0xFF2E9E57),
          alertCount: scope?.alerts ?? _alerts.length,
          onBell: widget.onAlerts ?? (scope == null ? null : () => scope.openAlerts()),
        ),
        Expanded(
          child: RefreshIndicator(
            color: V2.teal600,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _controls(),
                const SizedBox(height: 12),
                if (d == null && _error != null)
                  _message(_error!, retry: true)
                else if (d == null)
                  _skeleton()
                else ...[
                  _hero(d),
                  const SizedBox(height: 12),
                  _kpis(d),
                  const SizedBox(height: 12),
                  _regionCard(d),
                  const SizedBox(height: 12),
                  _alertCard(),
                  const SizedBox(height: 12),
                  _targetCard(d),
                  const SizedBox(height: 12),
                  const V3EntryCard(),
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Period switch and region chip ──

  Widget _controls() {
    const names = ['Harian', 'Mingguan', 'Bulanan'];
    return SizedBox(
      height: 32,
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            for (var i = 0; i < names.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Semantics(
                button: true,
                selected: _grain == i,
                child: GestureDetector(
                  onTap: () => setState(() => _grain = i),
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: _grain == i
                        ? BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [cssShadow(const Color(0x1F0F1F1D), 0, 1, 3)])
                        : null,
                    child: Text(names[i], style: V2.d(12, FontWeight.w600, _grain == i ? V2.teal700 : V2.ink2, lh: 1)),
                  ),
                ),
              ),
            ],
          ]),
        ),
        const Spacer(),
        Semantics(
          button: true,
          label: 'Pilih region',
          child: GestureDetector(
            onTap: _pickRegion,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: V2.teal50, borderRadius: BorderRadius.circular(99), border: Border.all(color: V2.teal200)),
              child: Row(children: [
                const MIcon('pin', size: 14, color: V2.teal700),
                const SizedBox(width: 7),
                Text(_region.isEmpty ? 'Semua' : titleCase(_region), style: V2.d(12, FontWeight.w500, V2.teal700, lh: 1)),
                const SizedBox(width: 7),
                const MIcon('chev', size: 14, color: V2.teal700),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickRegion() async {
    final regions = ((_data?['scope'] as Map?)?['regions'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: V2.rule, borderRadius: BorderRadius.circular(4)))),
            const SizedBox(height: 16),
            Text('Pilih region', style: V2.d(16, FontWeight.w600, V2.ink, lh: 1.3)),
            const SizedBox(height: 8),
            for (final r in ['', ...regions])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: r.isEmpty ? V2.ink : regionColor(r, regions.indexOf(r)), borderRadius: BorderRadius.circular(3))),
                minLeadingWidth: 10,
                title: Text(r.isEmpty ? 'Circle Java (semua region)' : titleCase(r), style: V2.d(14, FontWeight.w500, V2.ink)),
                trailing: r == _region ? const MIcon('check', size: 18, color: V2.teal600) : null,
                onTap: () => Navigator.pop(ctx, r),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || picked == _region) return;
    setState(() => _region = picked);
    if (widget.preview == null) _load();
  }

  // ── Hero ──

  String _wib(DateTime t) {
    final w = t.toUtc().add(const Duration(hours: 7));
    return '${w.hour.toString().padLeft(2, '0')}.${w.minute.toString().padLeft(2, '0')}';
  }

  Widget _hero(Map<String, dynamic> d) {
    final text = ((d['summary'] as Map?)?['text'] ?? '').toString();
    final created = DateTime.tryParse(((d['source'] as Map?)?['created_at'] ?? '').toString());
    final base = V2.b(14.5, FontWeight.w400, Colors.white, lh: 1.55);
    final spans = <InlineSpan>[];
    var n = 0;
    // **x** pieces: the first is lime (the headline), the rest coral (attention).
    final re = RegExp(r'\*\*([^*]+)\*\*');
    var at = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(
        text: m[1],
        style: base.copyWith(fontWeight: FontWeight.w600, color: n++ == 0 ? V2.lime : const Color(0xFFFFC2AF)),
      ));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    final alerts = V2Scope.maybeOf(context)?.alerts ?? _alerts.length;
    final month = (d['month_label'] ?? '').toString();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      child: CustomPaint(
        painter: _HeroBg(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: const Color(0x1FFFFFFF),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0x2EFFFFFF)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const MIcon('spark', size: 14, color: V2.coral),
                const SizedBox(width: 7),
                Text('Ringkasan agent${created != null ? ' · ${_wib(created)}' : ''}', style: V2.d(12, FontWeight.w600, Colors.white, lh: 1)),
              ]),
            ),
            // the inline-flex tag sits in a line box 0.3 px taller than itself
            const SizedBox(height: 10.3),
            V2Lines(TextSpan(style: base, children: spans), lineHeight: 14.5 * 1.55, dy: 1),
            const SizedBox(height: 12),
            Row(children: [
              _heroButton('spark', 'Tanya detail', solid: true, onTap: () {
                widget.onAsk?.call('Jelaskan performa $_scopeName $month: apa yang mendorong revenue, payload dan gross add, dan wilayah mana yang perlu perhatian?');
              }),
              const SizedBox(width: 10),
              _heroButton('bell', alerts > 0 ? '$alerts alert' : 'Watchlist', onTap: widget.onAlerts ?? () => V2Scope.maybeOf(context)?.openAlerts()),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _heroButton(String icon, String label, {bool solid = false, VoidCallback? onTap}) {
    final fg = solid ? V2.teal900 : Colors.white;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: solid ? V2.lime : null,
            borderRadius: BorderRadius.circular(13),
            border: solid ? null : Border.all(color: const Color(0x59FFFFFF)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            MIcon(icon, size: 17, color: fg),
            const SizedBox(width: 8),
            Text(label, style: V2.d(13, FontWeight.w600, fg, lh: 1)),
          ]),
        ),
      ),
    );
  }

  // ── KPI cards ──

  Widget _kpis(Map<String, dynamic> d) {
    final kpis = (d['kpis'] as List? ?? const []).whereType<Map>().toList();
    final monthLabels = (d['month_labels'] as List? ?? const []).map((e) => e.toString()).toList();
    final cards = [for (final k in kpis) _kpiCard(k, monthLabels)];
    return Column(children: [
      for (var i = 0; i < cards.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: cards[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
          ]),
        ),
      ],
    ]);
  }

  Widget _kpiCard(Map k, List<String> monthLabels) {
    final key = (k['key'] ?? '').toString();
    final look = _looks[key] ?? _Look((k['label'] ?? key).toString(), 'grid', V2.teal50, V2.teal700, V2.teal600);
    final change = toNum(k['pct_change']);
    final pp = k['change_unit'] == 'pp';
    final down = (change ?? 0) < 0;
    List<double> nums(dynamic l) => (l as List? ?? const []).map(toNum).whereType<double>().toList();
    List<String> strs(dynamic l) => (l as List? ?? const []).map((e) => e.toString()).toList();
    final daily = nums(k['spark_daily']), weekly = nums(k['spark_weekly']);
    final (values, labels) = _grain == 0 && daily.length > 1
        ? (daily, strs(k['spark_daily_labels']))
        : _grain == 1 && weekly.length > 1
            ? (weekly, strs(k['spark_weekly_labels']))
            : () {
                final all = nums(k['spark']);
                final v = all.length > 10 ? all.sublist(all.length - 10) : all;
                final l = monthLabels.length >= v.length ? monthLabels.sublist(monthLabels.length - v.length) : <String>[];
                return (v, l);
              }();
    final color = down ? V2.red : look.spark;
    final value = fmtKpi(k['format']?.toString(), k['value']);
    final first = values.isEmpty ? '' : '${labels.isNotEmpty ? labels.first : ''} ${fmtKpi(k['format']?.toString(), values.first)}';
    final last = values.isEmpty ? '' : '${labels.isNotEmpty ? labels.last : ''} ${fmtKpi(k['format']?.toString(), values.last)}';
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
              decoration: BoxDecoration(color: look.bg, borderRadius: BorderRadius.circular(10)),
              child: MIcon(look.icon, size: 15, color: look.fg),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(look.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(13, FontWeight.w500, V2.ink2, lh: 1.2))),
          ]),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 21 * 1.15,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1, style: V2.d(21, FontWeight.w700, V2.ink, lh: 1.15, ls: -.01)),
          ),
        ),
        const SizedBox(height: 4),
        if (change != null)
          Container(
            height: 19,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(color: down ? const Color(0xFFFDECEC) : const Color(0xFFE6F4EA), borderRadius: BorderRadius.circular(99)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Triangle(up: !down, color: down ? V2.red : _green, width: 10, height: 8.5),
              const SizedBox(width: 3),
              Text('${(pp ? _f2 : _f1).format(change.abs())}${pp ? ' pp' : '%'}', style: V2.d(11, FontWeight.w600, down ? V2.red : _green, lh: 1)),
            ]),
          )
        else
          const SizedBox(height: 19),
        const SizedBox(height: 4),
        Semantics(
          label: values.length > 1 ? 'Tren ${look.label}: $first sampai $last' : null,
          child: SizedBox(height: 28, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values, color))),
        ),
      ]),
    );
  }

  // ── Revenue per region ──

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

  Widget _h3(String t) => _tx(t, V2.d(16, FontWeight.w600, V2.ink, lh: 1.3));

  /// Text whose line box keeps the CSS height (Flutter rounds 20.8 px lines to 21).
  Widget _tx(String s, TextStyle st) => V2Lines(TextSpan(text: s, style: st), lineHeight: st.fontSize! * st.height!, dy: 0);

  Widget _regionCard(Map<String, dynamic> d) {
    final rb = d['revenue_by_region'] as Map? ?? const {};
    final months = (rb['months'] as List? ?? const []).map((e) => toNum(e)?.toInt() ?? 0).toList();
    final labels = (rb['labels'] as List? ?? const []).map((e) => e.toString()).toList();
    final raw = (rb['series'] as List? ?? const []).whereType<Map>().toList();
    final series = [
      for (var i = 0; i < raw.length; i++)
        _Series(titleCase((raw[i]['name'] ?? '').toString()), regionColor((raw[i]['name'] ?? '').toString(), i),
            (raw[i]['values'] as List? ?? const []).map((v) => toNum(v) ?? 0).toList()),
    ];
    if (_on.length != series.length) _on = List.filled(series.length, true);
    final n = labels.length;
    final hover = n == 0 ? 0 : (_hover ?? n - 1).clamp(0, n - 1);
    final tips = [
      for (var i = 0; i < n; i++)
        i < months.length && months[i] > 0 ? '${_months[(months[i] % 100) - 1]} ${months[i] ~/ 100}' : labels[i],
    ];
    final shown = [for (var i = 0; i < series.length; i++) if (_on[i]) series[i]];
    return _card(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _h3('Revenue per region'),
        const SizedBox(height: 2),
        _tx('Rp miliar · $n bulan · ketuk bulan untuk detail', V2.b(12, FontWeight.w400, V2.mute, lh: 1.3)),
      ]),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < series.length; i++)
          Semantics(
            button: true,
            toggled: _on[i],
            label: series[i].name,
            child: GestureDetector(
              onTap: () => setState(() {
                if (_on.where((b) => b).length > 1 || !_on[i]) _on = [for (var j = 0; j < _on.length; j++) j == i ? !_on[j] : _on[j]];
              }),
              child: Opacity(
                opacity: _on[i] ? 1 : .45,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: V2.rule)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: series[i].color, shape: BoxShape.circle)),
                    const SizedBox(width: 7),
                    Text(series[i].name.replaceFirst(RegExp(r' Java$'), ''), style: V2.d(12, FontWeight.w500, V2.ink2, lh: 1)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          // The mockup's plot is 18 px wider than the card content: the grid runs
          // into the card's right padding.
          final w = c.maxWidth + 18;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) {
              if (n == 0) return;
              final gw = (w - _BarsPainter.pl - _BarsPainter.pr) / n;
              setState(() => _hover = ((e.localPosition.dx - _BarsPainter.pl) / gw).floor().clamp(0, n - 1));
            },
            child: SizedBox(
              height: 200,
              child: CustomPaint(painter: _BarsPainter(labels, shown, hover, w)),
            ),
          );
        }),
        const SizedBox(height: 11.3),
        if (shown.isNotEmpty && n > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: V2.ink, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _tx(tips[hover], V2.d(12, FontWeight.w700, Colors.white, lh: 1.55)),
              for (final s in shown)
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Expanded(child: _tx(s.name, V2.d(12, FontWeight.w500, Colors.white, lh: 1.55))),
                  const SizedBox(width: 12),
                  Text(hover < s.values.length ? rpM(s.values[hover]) : '–', style: V2.d(12, FontWeight.w700, Colors.white, lh: 1)),
                ]),
            ]),
          ),
      ]),
    ]);
  }

  // ── Alerts ──

  String _ago(String? iso) {
    final t = DateTime.tryParse(iso ?? '');
    if (t == null) return '';
    final m = _now.difference(t).inMinutes;
    if (m < 1) return 'baru';
    if (m < 60) return '$m mnt';
    if (m < 60 * 24) return '${m ~/ 60} jam';
    return '${m ~/ (60 * 24)} hari';
  }

  Widget _alertCard() {
    final total = V2Scope.maybeOf(context)?.alerts ?? _alerts.length;
    final count = math.max(total, _alerts.length);
    final open = widget.onAlerts ?? () => V2Scope.maybeOf(context)?.openAlerts();
    return _card(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _h3('Alert aktif')),
        if (count > 0)
          GestureDetector(
            onTap: open,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: V2.redSolid, borderRadius: BorderRadius.circular(9)),
              child: Text('$count', style: V2.d(10, FontWeight.w700, Colors.white, lh: 1)),
            ),
          ),
      ]),
      if (_alerts.isEmpty)
        Text('Belum ada alert aktif. Pantau KPI Performance, Site productivity atau Profile wilayah agar agent memberi tahu saat ambang terlampaui.',
            style: V2.b(12.5, FontWeight.w400, V2.ink2, lh: 1.4)),
      for (final a in _alerts.take(2)) _alert(a, open),
    ]);
  }

  Widget _alert(Map<String, dynamic> a, VoidCallback open) {
    final k = a['severity'] == 'kritis';
    final stripe = k ? V2.red : _amber;
    final fg = k ? V2.red : _amberInk;
    final tint = k ? const Color(0xFFFDECEC) : const Color(0xFFFDF3E2);
    return GestureDetector(
      onTap: open,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: V2.rule)),
        child: Stack(children: [
          Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: stripe)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(99)),
                      child: Text(k ? 'Kritis' : 'Peringatan', style: V2.d(11, FontWeight.w600, fg, lh: 1)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text((a['scope_label'] ?? a['metric_label'] ?? '').toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(11.5, FontWeight.w500, V2.mute, lh: 1)),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Target achievement per region ──

  Widget _targetCard(Map<String, dynamic> d) {
    final targets = d['has_targets'] == true;
    final regions = (d['regions'] as List? ?? const []).whereType<Map>().toList();
    return _card(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _h3(targets ? 'Pencapaian target' : 'Kontribusi revenue')),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          child: GestureDetector(
            onTap: widget.onPerformance,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: V2.rule)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Performance', style: V2.d(12, FontWeight.w600, V2.teal700, lh: 1)),
                const SizedBox(width: 7),
                const MIcon('arrowr', size: 16, color: V2.teal700),
              ]),
            ),
          ),
        ),
      ]),
      Column(children: [
        for (var i = 0; i < regions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _targetRow(regions[i], i, targets, last: i == regions.length - 1),
        ],
      ]),
    ]);
  }

  Widget _targetRow(Map r, int i, bool targets, {required bool last}) {
    final name = (r['region'] ?? '').toString();
    final c = regionColor(name, i);
    final p = toNum(targets ? r['achievement_pct'] : r['share_pct']);
    final low = targets && p != null && p < 95;
    final txt = !targets ? V2.ink : p != null && p >= 100 ? _green : low ? _amberInk : const Color(0xFF0E6F7C);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: V2.rule2))),
      child: Column(children: [
        SizedBox(
          height: 14,
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(child: Text(titleCase(name), maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(14, FontWeight.w600, V2.ink, lh: 1))),
            const SizedBox(width: 10),
            Text(toNum(r['revenue']) == null ? '–' : rpM(toNum(r['revenue'])!), style: V2.d(14, FontWeight.w700, V2.ink, lh: 1)),
          ]),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 13,
          child: Row(children: [
            Expanded(
              child: Container(
                height: 8,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(8)),
                child: FractionallySizedBox(
                  widthFactor: ((p ?? 0) / 100).clamp(0.0, 1.0),
                  child: Container(decoration: BoxDecoration(color: low ? _amber : c, borderRadius: BorderRadius.circular(8))),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 56,
              child: Text(p == null ? '–' : '${_f1.format(p)}%', textAlign: TextAlign.right, style: V2.d(13, FontWeight.w700, txt, lh: 1)),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── States ──

  Widget _message(String text, {bool retry = false}) {
    return _card(children: [
      Text(text, style: V2.b(13, FontWeight.w400, V2.ink2, lh: 1.4)),
      if (retry)
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: _load,
            child: Text('Coba lagi', style: V2.d(13, FontWeight.w600, V2.teal700, lh: 1.3)),
          ),
        ),
    ]);
  }

  Widget _skeleton() {
    Widget box(double h, [double r = 18]) =>
        Container(height: h, decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(r)));
    return Column(children: [
      box(188, 20),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: box(137, 16)), const SizedBox(width: 10), Expanded(child: box(137, 16))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: box(137, 16)), const SizedBox(width: 10), Expanded(child: box(137, 16))]),
      const SizedBox(height: 12),
      box(426),
    ]);
  }
}

class _Series {
  _Series(this.name, this.color, this.values);
  final String name;
  final Color color;
  final List<double> values;
}

/// Hero background: two soft radial glows over the teal 135deg gradient.
class _HeroBg extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    canvas.drawRect(r, Paint()..shader = cssLinear(135, const [V2.teal700, V2.teal900], s, stops: const [0, .7]).createShader(r));
    // CSS paints the first background layer on top, so draw them in reverse.
    _glow(canvas, s, Offset(s.width * .10, s.height * 1.10), 300, 220, const Color(0x2EC7F25E));
    _glow(canvas, s, Offset(s.width * .82, s.height * .20), 420, 260, const Color(0x7322B8C9));
  }

  void _glow(Canvas canvas, Size s, Offset c, double rx, double ry, Color color) {
    canvas.save();
    canvas.clipRect(Offset.zero & s);
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, ry / rx);
    final paint = Paint()
      ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: Offset.zero, radius: rx));
    canvas.drawRect(Rect.fromLTRB(-c.dx, -c.dy * rx / ry, s.width - c.dx, (s.height - c.dy) * rx / ry), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeroBg old) => false;
}

/// KPI sparkline: line, soft area and an end dot (mockup svg.spark).
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    if (values.length < 2) return;
    final w = s.width, h = s.height;
    final mn = values.reduce(math.min), mx = values.reduce(math.max);
    double x(int i) => 2 + (w - 6) * i / (values.length - 1);
    double y(double a) => 3 + (h - 8) * (1 - (a - mn) / (mx - mn == 0 ? 1 : mx - mn));
    final line = Path();
    for (var i = 0; i < values.length; i++) {
      i == 0 ? line.moveTo(x(i), y(values[i])) : line.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(line)
      ..lineTo(x(values.length - 1), h)
      ..lineTo(x(0), h)
      ..close();
    // SVG gradients span the path's bounding box (objectBoundingBox).
    final b = area.getBounds();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .2), color.withValues(alpha: 0)],
        ).createShader(b),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(Offset(x(values.length - 1), y(values.last)), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.values != values || o.color != color;
}

List<double> _axisSteps(double max) {
  if (max <= 0) return [0, 1];
  final raw = max / 3;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / mag;
  final step = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 3 ? 3 : f <= 5 ? 5 : 10) * mag;
  final out = <double>[];
  for (var v = 0.0; v <= (max / step).ceil() * step + step / 2; v += step) {
    out.add(double.parse(v.toStringAsFixed(6)));
  }
  return out;
}

/// Revenue per region as grouped bars per month (Rp miliar), with the tapped
/// month in a teal band (mockup svg.rchart, small variant).
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.labels, this.series, this.hover, this.width);
  final List<String> labels;
  final List<_Series> series;
  final int hover;
  final double width;

  static const pl = 34.0, pr = 6.0, pt = 10.0, pb = 26.0;

  void _text(Canvas c, String t, double x, double baseline, {TextAlign align = TextAlign.center, bool bold = false, Color color = V2.mute}) {
    final tp = TextPainter(
      text: TextSpan(text: t, style: TextStyle(fontFamily: V2.display, fontSize: 10, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    final asc = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final dx = align == TextAlign.center ? x - tp.width / 2 : x - tp.width;
    tp.paint(c, Offset(dx, baseline - asc));
    tp.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    final w = width, h = size.height;
    final iw = w - pl - pr, ih = h - pt - pb;
    final mx = series.expand((s) => s.values).fold<double>(1e9, math.max) / 1e9;
    final ticks = _axisSteps(mx);
    final top = ticks.last;
    double y(double v) => pt + ih * (1 - v / 1e9 / top);
    final gw = iw / n;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(pl + gw * hover + 4, pt, gw - 8, ih), const Radius.circular(10)),
      Paint()..color = V2.teal50,
    );
    for (final t in ticks) {
      final yy = pt + ih * (1 - t / top);
      canvas.drawLine(Offset(pl, yy), Offset(w - pr, yy), Paint()
        ..color = t == 0 ? const Color(0xFFB9C6C3) : V2.rule2
        ..strokeWidth = 1);
      _text(canvas, idNum(t, 1), pl - 8, yy + 4, align: TextAlign.right);
    }
    final k = series.length;
    final bw = k == 0 ? 0.0 : math.min(12.0, (gw - 16) / k - 4);
    for (var j = 0; j < n; j++) {
      for (var i = 0; i < k; i++) {
        if (j >= series[i].values.length) continue;
        final v = series[i].values[j];
        final x0 = pl + gw * j + gw / 2 - (k * (bw + 4) - 4) / 2 + i * (bw + 4);
        final r = Rect.fromLTRB(x0, y(v), x0 + bw, y(0));
        canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(3, bw / 2))), Paint()..color = series[i].color);
      }
      _text(canvas, labels[j], pl + gw * j + gw / 2, h - 7, bold: j == hover, color: j == hover ? V2.ink : V2.mute);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter o) => o.labels != labels || o.series != series || o.hover != hover || o.width != width;
}
