import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../api/api_client.dart';
import '../ui/chart.dart';
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

/// Android · Dashboard (light and dark): greeting, region and period chips,
/// KPI carousel, the agent's daily summary, quick actions, four indicator
/// cards with sparklines and revenue per region with drill-down.
/// Numbers come from GET /api/dashboard/overview.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.preview,
    this.previewNow,
    this.previewTouch,
    this.alertCount = 0,
    this.onAsk,
    this.onTab,
  });

  /// Overview payload to render instead of fetching (golden tests).
  final Map<String, dynamic>? preview;
  final DateTime? previewNow;
  final int? previewTouch;
  final int alertCount;

  /// Sends a question to the Agent tab.
  final void Function(String question)? onAsk;

  /// Switches the home tab (0 Agent, 2 Alert, 3 Laporan, 4 Peta).
  final void Function(int tab)? onTab;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  String _region = '';
  int _page = 0;
  int? _touch;
  DateTime _updated = DateTime.now();
  final _carousel = PageController(viewportFraction: 312 / 358);

  @override
  void initState() {
    super.initState();
    _touch = widget.previewTouch;
    if (widget.preview != null) {
      _data = widget.preview;
      _updated = widget.previewNow ?? DateTime.now();
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _carousel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ApiClient.dashboardOverview(region: _region);
      if (!mounted) return;
      setState(() { _data = d; _updated = DateTime.now(); _touch = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime get _now => widget.previewNow ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    final d = _data;
    return ColoredBox(
      color: p.bg,
      child: RefreshIndicator(
        color: p.teal600,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.only(top: top, bottom: 24),
          children: [
            Stack(clipBehavior: Clip.none, children: [
              Positioned(left: 120, top: -140, width: 380, height: 320, child: Glow(color: p.teal400, alpha: .15)),
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _refreshRow(p),
                const SizedBox(height: 18),
                _greeting(p),
                const SizedBox(height: 18),
                _filters(p),
              ]),
            ]),
            const SizedBox(height: 18),
            if (d == null && _error != null)
              InlineMessage(_error!, onRetry: _load)
            else if (d == null)
              _skeleton(p)
            else ...[
              _kpiCarousel(p, d),
              const SizedBox(height: 18),
              _dots(p, (d['kpis'] as List).length),
              const SizedBox(height: 18),
              _summary(p, d),
              const SizedBox(height: 18),
              _quickActions(p),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Indikator utama', style: ts(16, w600, p.ink)),
              ),
              const SizedBox(height: 18),
              _indicatorGrid(p, d),
              const SizedBox(height: 18),
              _regionChart(p, d),
            ],
          ],
        ),
      ),
    );
  }

  // ── Header ──

  Widget _refreshRow(Pal p) {
    final hhmm = '${_updated.hour.toString().padLeft(2, '0')}.${_updated.minute.toString().padLeft(2, '0')}';
    return SizedBox(
      height: 46,
      child: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: _loading ? null : _load,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle, boxShadow: p.shadow),
              alignment: Alignment.center,
              child: _loading
                  ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.teal600))
                  : Ic(Icx.refresh, size: 16, color: p.teal600),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${_loading || widget.preview != null ? 'Memperbarui' : 'Diperbarui'} · terakhir $hhmm WIB',
                style: ts(12, w400, p.mute)),
          ),
        ]),
      ),
    );
  }

  static const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

  Widget _greeting(Pal p) {
    final h = _now.hour;
    final hello = h < 11 ? 'Selamat pagi' : h < 15 ? 'Selamat siang' : h < 18 ? 'Selamat sore' : 'Selamat malam';
    final name = (AuthState.user?['full_name'] ?? AuthState.user?['username'] ?? 'Rizal').toString().split(' ').first;
    final date = '${_days[_now.weekday - 1]}, ${_now.day} ${monthsId[_now.month - 1]} ${_now.year}';
    final data = widget.preview != null ? 'data ilustrasi' : 'data ${_data?['month_label'] ?? '…'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$hello, $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(24, w700, p.ink, lh: 1.3, ls: -.003)),
            Text('$date · $data', style: ts(12, w400, p.mute)),
          ]),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => Navigator.of(context).pushNamed('/profile'),
          child: InitialAvatar(name, size: 44),
        ),
      ]),
    );
  }

  Widget _filters(Pal p) {
    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
        Material(
          color: p.teal600,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _pickRegion,
            child: Container(
              height: 40,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Row(children: [
                const Ic(Icx.mapPin, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(_region.isEmpty ? 'Jawa' : _title(_region), style: ts(13, w600, Colors.white)),
                const SizedBox(width: 6),
                const Ic(Icx.chevronDown, size: 16, color: Colors.white),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        for (final (i, label) in const [(0, 'Hari ini'), (1, '7 hari'), (2, 'Bulan ini')]) ...[
          Center(
            child: PillChip(label, selected: i == 2, onTap: i == 2 ? null : () => showToast(context, 'Dashboard memakai data bulanan (MTD). Tampilan harian menyusul.')),
          ),
          const SizedBox(width: 8),
        ],
      ]),
    );
  }

  Future<void> _pickRegion() async {
    final regions = ((_data?['scope'] as Map?)?['regions'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final p = Pal.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetHandle(),
            const SizedBox(height: 16),
            Text('Pilih region', style: ts(18, w700, p.ink, lh: 1.35)),
            const SizedBox(height: 8),
            for (final r in ['', ...regions])
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(r.isEmpty ? 'Jawa (semua region)' : _title(r), style: ts(14, w500, p.ink)),
                trailing: (r == _region) ? Ic(Icx.check, size: 18, color: p.teal600) : null,
                onTap: () => Navigator.pop(ctx, r),
              ),
          ]),
        ),
      ),
    );
    if (picked == null || picked == _region) return;
    setState(() => _region = picked);
    _load();
  }

  // ── KPI carousel ──

  static String fmtKpi(Map k, dynamic v) {
    final n = toNum(v);
    if (n == null) return '–';
    switch (k['format']) {
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

  static String _delta(Map k) {
    final c = toNum(k['pct_change']);
    if (c == null) return '–';
    return k['change_unit'] == 'pp' ? '${idNum(c.abs(), 1)} pp' : '${idNum(c.abs(), 1)}%';
  }

  String _title(String s) => s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');

  Widget _kpiCarousel(Pal p, Map d) {
    final kpis = (d['kpis'] as List).cast<Map>();
    final scope = _region.isEmpty ? 'Jawa' : _title(_region);
    return SizedBox(
      height: 184,
      child: PageView.builder(
        controller: _carousel,
        padEnds: false,
        itemCount: kpis.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) {
          final k = kpis[i];
          final c = toNum(k['pct_change']);
          final prev = toNum(k['prev']);
          final cur = toNum(k['value']);
          String note;
          if (k['format'] == 'number' && prev != null && cur != null) {
            final diff = cur - prev;
            note = '${diff >= 0 ? '+' : '−'}${shortNum(diff.abs())} bulan ini';
          } else {
            note = 'vs ${k['note_prev_label'] ?? 'bulan lalu'} ${prev == null ? '' : fmtKpi(k, prev)}'.trim();
          }
          final label = k['key'] == 'subs' ? 'Pelanggan aktif' : '${k['label']} $scope';
          return Padding(
            padding: EdgeInsets.only(left: i == 0 ? 16 : 0, right: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: HeroFill(
                still: i.isEven ? 'assets/img/still_tower.jpg' : 'assets/img/still_light.jpg',
                stillOpacity: .3,
                kawung: .12,
                child: Stack(children: [
                  Positioned(left: 130, top: -110, width: 300, height: 260, child: Glow(color: const Color(0xFF33BCAD), alpha: .33)),
                  const Positioned(left: -40, top: 96, width: 400, height: 140, child: Image(image: AssetImage('assets/img/iso_city.webp'))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: ts(13, w500, const Color(0xFFC0EDE8))),
                      const SizedBox(height: 8),
                      Text(fmtKpi(k, k['value']), style: ts(28, w700, Colors.white, lh: 1.2, ls: -.005, tabular: true)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Container(
                          height: 24,
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withValues(alpha: .35)),
                          ),
                          alignment: Alignment.center,
                          child: Text('${(c ?? 0) >= 0 ? '▲' : '▼'} ${_delta(k)}',
                              style: ts(12, w600, (c ?? 0) >= 0 ? const Color(0xFF8FDFD7) : const Color(0xFFF8B4B4))),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w400, const Color(0xFFC0EDE8)))),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _dots(Pal p, int n) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == _page ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(color: i == _page ? p.teal600 : p.chartGrey, borderRadius: BorderRadius.circular(999)),
          ),
        ],
      ]);

  // ── Agent summary ──

  Widget _summary(Pal p, Map d) {
    final s = (d['summary'] as Map?) ?? {};
    final hhmm = '${_updated.hour.toString().padLeft(2, '0')}.${_updated.minute.toString().padLeft(2, '0')}';
    final alerts = widget.alertCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.teal50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.teal100),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const _Orb(size: 32),
            const SizedBox(width: 8),
            Expanded(child: Text('Ringkasan agent hari ini', style: ts(13, w600, p.teal800))),
            Text(hhmm, style: ts(12, w400, p.mute)),
          ]),
          const SizedBox(height: 10),
          MarkdownBody(
            data: (s['text'] ?? '').toString(),
            styleSheet: MarkdownStyleSheet(p: ts(14, w400, p.text2, lh: 1.5), strong: ts(14, w600, p.ink, lh: 1.5)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _pillButton(p, Icx.sparkles, 'Tanya detail', filled: true,
                onTap: () => widget.onAsk?.call('Jelaskan detail ringkasan dashboard ${_region.isEmpty ? 'Jawa' : _title(_region)} bulan ini dan apa yang perlu ditindaklanjuti')),
            const SizedBox(width: 8),
            _pillButton(p, Icx.bell, '$alerts alert', onTap: () => widget.onTab?.call(2)),
          ]),
        ]),
      ),
    );
  }

  Widget _pillButton(Pal p, I3 icon, String label, {bool filled = false, VoidCallback? onTap}) {
    final fg = filled ? Colors.white : p.ink;
    return Material(
      color: filled ? p.teal600 : p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: filled ? BorderSide.none : BorderSide(color: p.rule)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Ic(icon, size: 24, color: fg),
            const SizedBox(width: 8),
            Text(label, style: ts(13, w600, fg)),
          ]),
        ),
      ),
    );
  }

  // ── Quick actions ──

  Widget _quickActions(Pal p) {
    final items = [
      (Icx.sparkles, 'Tanya', p.teal50, p.teal700, 0),
      (Icx.fileText, 'Laporan', p.amber50, p.amber700, 3),
      (Icx.bellRing, 'Alert', p.rose50, p.rose600, 2),
      (Icx.map, 'Peta', p.violet50, p.violet600, 4),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final (icon, label, bg, fg, tab) in items)
          GestureDetector(
            onTap: () => widget.onTab?.call(tab),
            child: SizedBox(
              width: 76,
              child: Column(children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: p.dark ? bg : Colors.white, width: 2),
                    boxShadow: p.dark ? null : const [BoxShadow(color: Color(0x0D0F1F1D), offset: Offset(0, 1), blurRadius: 3)],
                  ),
                  alignment: Alignment.center,
                  child: Ic(icon, size: 24, color: fg),
                ),
                const SizedBox(height: 6),
                Text(label, style: ts(12, w600, p.text2)),
              ]),
            ),
          ),
      ]),
    );
  }

  // ── Indicator cards ──

  Widget _indicatorGrid(Pal p, Map d) {
    final kpis = (d['kpis'] as List).cast<Map>();
    Map? byKey(String k) => kpis.cast<Map?>().firstWhere((e) => e!['key'] == k, orElse: () => null);
    final order = [
      (byKey('revenue'), 'Revenue', Icx.wallet, Tone.amber, 18.0),
      (byKey('subs'), 'Pelanggan', Icx.users, Tone.blue, 24.0),
      (byKey('payload'), 'Payload', Icx.database, Tone.violet, 24.0),
      (byKey('availability') ?? byKey('gross_add'), null, Icx.radio, Tone.teal, 24.0),
    ];
    final cards = [
      for (final (k, label, icon, tone, iconSize) in order)
        if (k != null) _indicator(p, k, label ?? (k['key'] == 'availability' ? 'Availability' : k['label'].toString()),
            k['key'] == 'gross_add' ? Icx.userPlus : icon, k['key'] == 'gross_add' ? Tone.green : tone, iconSize),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(children: [
            Expanded(child: cards[i]),
            const SizedBox(width: 12),
            Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
          ]),
        ],
      ]),
    );
  }

  Widget _indicator(Pal p, Map k, String label, I3 icon, Tone tone, double iconSize) {
    final (bg, fg) = toneColors(p, tone);
    final c = toNum(k['pct_change']);
    final up = (c ?? 0) >= 0;
    final caption = k['key'] == 'availability'
        ? 'target ${idNum(toNum(k['target']) ?? 99.5, 1)}%'
        : k['key'] == 'subs' ? 'aktif' : 'vs ${k['note_prev_label'] ?? 'bulan lalu'}';
    final spark = ((k['spark'] as List?) ?? const []).map((e) => toNum(e)).toList();
    return Container(
      height: 212,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.rule),
        boxShadow: p.shadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 36,
          child: Row(children: [
            IconTile(icon, bg: bg, fg: fg, size: 36, iconSize: iconSize),
            const Spacer(),
            if (c != null) DeltaPill(_delta(k), up: up),
          ]),
        ),
        const SizedBox(height: 6),
        Text(label, style: ts(13, w500, p.text2)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(fmtKpi(k, k['value']), style: ts(28, w700, p.ink, lh: 1.2, ls: -.005, tabular: true)),
        ),
        const SizedBox(height: 6),
        Text(caption, style: ts(12, w400, p.mute)),
        const SizedBox(height: 7),
        Sparkline(spark, color: up ? p.teal600 : p.dangerSolid, height: 44),
      ]),
    );
  }

  // ── Revenue per region ──

  Widget _regionChart(Pal p, Map d) {
    final r = (d['revenue_by_region'] as Map?) ?? {};
    final labels = ((r['labels'] as List?) ?? const []).map((e) => e.toString()).toList();
    final months = ((r['months'] as List?) ?? const []).map((e) => e.toString()).toList();
    final series = ((r['series'] as List?) ?? const []).cast<Map>().take(3).toList();
    final n = math.min(4, labels.length);
    final from = labels.length - n;
    final colors = [p.teal600, p.teal300, p.chartAmber];
    final data = [
      for (final s in series) [for (var i = from; i < labels.length; i++) toNum((s['values'] as List)[i]) ?? 0],
    ];
    final names = [for (final s in series) _short(s['name'].toString())];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SurfaceCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Revenue per region', style: ts(16, w600, p.ink)),
          const SizedBox(height: 2),
          Text('Ketuk bar untuk drill-down', style: ts(12, w400, p.mute)),
          const SizedBox(height: 10),
          Row(children: [
            GestureDetector(
              onTap: _region.isEmpty ? null : () { setState(() => _region = ''); _load(); },
              child: Text('Jawa', style: ts(13, w500, p.teal700)),
            ),
            const SizedBox(width: 6),
            Ic(Icx.chevronRight, size: 14, color: p.mute),
            const SizedBox(width: 6),
            Text(_region.isEmpty ? 'Semua region' : _title(_region), style: ts(13, w600, p.ink)),
          ]),
          const SizedBox(height: 10),
          if (n == 0 || data.isEmpty)
            SizedBox(height: 170, child: Center(child: Text('Belum ada data per region.', style: ts(13, w400, p.mute))))
          else
            _GroupedBars(
              labels: [for (var i = from; i < labels.length; i++) labels[i]],
              tipTitles: [
                for (var i = from; i < labels.length; i++)
                  i < months.length && months[i].length == 6 ? '${labels[i]} ${months[i].substring(0, 4)}' : labels[i],
              ],
              series: data,
              names: names,
              colors: colors,
              touch: _touch,
              onTouch: (i) => setState(() => _touch = i),
              onDrill: (si) {
                if (_region.isNotEmpty) return;
                setState(() => _region = series[si]['name'].toString());
                _load();
              },
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < names.length; i++)
              Container(
                height: 28,
                padding: const EdgeInsets.fromLTRB(9, 0, 11, 0),
                decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: p.rule)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(names[i], style: ts(12, w600, p.text2)),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }

  /// "JAWA TIMUR" → "Jatim"; other names title-cased.
  String _short(String region) {
    const m = {
      'JAWA TIMUR': 'Jatim', 'JAWA BARAT': 'Jabar', 'JAWA TENGAH': 'Jateng & DIY', 'JATENG DIY': 'Jateng & DIY',
      'JAWA TENGAH & DIY': 'Jateng & DIY', 'JABODETABEK': 'Jabodetabek',
    };
    return m[region.toUpperCase()] ?? _title(region);
  }

  Widget _skeleton(Pal p) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: const [
          Skeleton(height: 184, radius: 20),
          SizedBox(height: 18),
          Skeleton(height: 150, radius: 20),
          SizedBox(height: 18),
          Skeleton(height: 212, radius: 20),
        ]),
      );
}

/// Grouped bars per month with the selected month highlighted and the dark tooltip.
class _GroupedBars extends StatelessWidget {
  const _GroupedBars({
    required this.labels,
    required this.tipTitles,
    required this.series,
    required this.names,
    required this.colors,
    required this.touch,
    required this.onTouch,
    required this.onDrill,
  });
  final List<String> labels, tipTitles, names;
  final List<List<double>> series;
  final List<Color> colors;
  final int? touch;
  final ValueChanged<int> onTouch;
  final ValueChanged<int> onDrill;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final hi = series.expand((s) => s).fold<double>(0, math.max);
    // Round the axis to a "nice" top in billions (M) or trillions (T).
    final div = hi >= 1e12 ? 1e12 : hi >= 1e9 ? 1e9 : hi >= 1e6 ? 1e6 : 1.0;
    final unitTop = hi / div;
    final step = [1, 1.5, 2, 2.5, 3, 4, 5, 10].map((s) => s * math.pow(10, (math.log(unitTop / 2) / math.ln10).floor())).firstWhere((s) => s * 2 >= unitTop);
    final top = step * 2 * div;
    return SizedBox(
      height: 170,
      child: LayoutBuilder(builder: (context, c) {
        const left = 34.0, right = 8.0, plotTop = 8.0, plotBottom = 142.0;
        final w = c.maxWidth - left - right;
        final slot = w / labels.length;
        final barW = 12.0, gap = 3.0;
        final groupW = series.length * barW + (series.length - 1) * gap;
        double y(double v) => plotBottom - (v / top) * (plotBottom - plotTop);

        int? hit(Offset o) {
          final i = ((o.dx - left) / slot).floor();
          return i >= 0 && i < labels.length ? i : null;
        }

        final children = <Widget>[
          for (final (i, v) in [(0, 0.0), (1, step * div), (2, top)]) ...[
            Positioned(left: left, right: right, top: y(v), height: 1, child: ColoredBox(color: p.rule)),
            Positioned(
              left: 0,
              width: 26,
              top: y(v) - 9,
              child: Text(i == 0 ? '0' : idNum(v / (div == 1e12 ? 1e9 : div == 1e9 ? 1e9 : div), 0), style: ts(12, w400, p.mute)),
            ),
          ],
          if (touch != null && touch! < labels.length)
            Positioned(
              left: left + slot * touch! + (slot - 63) / 2,
              top: 4,
              width: 63,
              height: plotBottom - 4,
              child: DecoratedBox(decoration: BoxDecoration(color: p.teal50, borderRadius: BorderRadius.circular(10))),
            ),
          for (var g = 0; g < labels.length; g++) ...[
            for (var s = 0; s < series.length; s++)
              Positioned(
                left: left + slot * g + (slot - groupW) / 2 + s * (barW + gap),
                top: y(series[s][g]),
                width: barW,
                height: plotBottom - y(series[s][g]),
                child: GestureDetector(
                  onTap: () { onTouch(g); onDrill(s); },
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: colors[s], borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
                  ),
                ),
              ),
            Positioned(
              left: left + slot * g,
              width: slot,
              top: 150,
              child: Text(labels[g], textAlign: TextAlign.center,
                  style: g == touch ? ts(12, w600, p.ink) : ts(12, w400, p.mute)),
            ),
          ],
        ];
        if (touch != null && touch! < labels.length) {
          final gx = left + slot * touch! + (slot - 63) / 2;
          final toLeft = gx - 176 - 10 >= 0;
          children.add(Positioned(
            left: toLeft ? gx - 186 : math.min(gx + 63 + 10, c.maxWidth - 176),
            top: 12,
            width: 176,
            child: ChartTip(
              title: tipTitles[touch!],
              width: 176,
              rows: [
                for (var s = 0; s < series.length && s < 3; s++)
                  (s == 0 ? p.teal400 : s == 1 ? p.chartGrey : p.chartAmber, names[s], formatValue(series[s][touch!], 'currency')),
              ],
            ),
          ));
        }
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (d) {
            final i = hit(d.localPosition);
            if (i != null) onTouch(i);
          },
          child: Stack(clipBehavior: Clip.none, children: children),
        );
      }),
    );
  }
}

/// Small AI orb (teal hero fill with the particle orb), used on summary cards.
class _Orb extends StatelessWidget {
  const _Orb({this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: HeroFill(
            kawung: 0,
            child: OverflowBox(
              maxWidth: size * 1.25,
              maxHeight: size * 1.25,
              child: Image.asset('assets/img/ai_orb.webp', width: size * 1.25, height: size * 1.25),
            ),
          ),
        ),
      );
}
