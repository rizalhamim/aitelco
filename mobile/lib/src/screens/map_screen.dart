import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../geo/geo_assets.dart';
import '../ui/chart.dart' show formatValue, idNum, toNum;
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import 'location_sheet.dart' show getCurrentCoord;

/// A kabupaten outline in world units (longitude, −Mercator latitude).
class _Shape {
  _Shape(this.id, this.name, this.prov, this.path, this.bounds, this.anchor, this.area);
  final String id, name, prov;
  final Path path;
  final Rect bounds;
  final Offset anchor;
  final double area;
}

const _javaProvinces = {'BANTEN', 'DKI JAKARTA', 'JAWA BARAT', 'JAWA TENGAH', 'DAERAH ISTIMEWA YOGYAKARTA', 'JAWA TIMUR'};

double _mercY(double lat) => -math.log(math.tan(math.pi / 4 + lat * math.pi / 360)) * 180 / math.pi;
Offset _world(double lat, double lon) => Offset(lon, _mercY(lat));

String _title(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String _kabName(String kab) => kab.toUpperCase().startsWith('KOTA ') ? _title(kab) : 'Kab. ${_title(kab)}';

/// Android · Peta: kabupaten choropleth for one metric, site dots for the
/// selected kabupaten and a sheet with its KPIs and the agent's explanation.
/// Data from /api/map/kabupaten and /api/map/kabupaten/detail.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.previewItems, this.previewDetail, this.previewFocus, this.onAsk});

  /// /api/map/kabupaten items and a detail payload to render instead of fetching.
  final List<Map<String, dynamic>>? previewItems;
  final Map<String, dynamic>? previewDetail;

  /// Province whose bounds fill the map at start (golden tests).
  final String? previewFocus;
  final void Function(String question)? onAsk;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<_Shape> _shapes = [];
  List<_Shape> _land = [];
  Map<String, Map<String, dynamic>> _data = {};
  String _metric = 'revenue';
  String? _selected;
  Map<String, dynamic>? _detail;
  bool _loadingDetail = false;
  String? _error;
  bool _showSites = true, _showLabels = true;

  // View transform: screen = world * _scale + _origin.
  double _scale = 0;
  Offset _origin = Offset.zero;
  double _startScale = 1;
  Offset _startOrigin = Offset.zero, _startFocal = Offset.zero;
  Size _size = Size.zero;

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _sheet = DraggableScrollableController();

  bool get _preview => widget.previewItems != null;

  @override
  void initState() {
    super.initState();
    _loadShapes();
    if (_preview) {
      _setItems(widget.previewItems!);
      _detail = widget.previewDetail;
      if (_detail != null) _selected = '${_detail!['kabupaten']}|${_detail!['provinsi']}'.toUpperCase();
    } else {
      _loadData();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _sheet.dispose();
    super.dispose();
  }

  Future<void> _loadShapes() async {
    final feats = await GeoAssets.load('kabupaten');
    final java = <_Shape>[], land = <_Shape>[];
    for (final f in feats) {
      final prov = (f.props['provinsi'] ?? '').toString().toUpperCase();
      final path = Path()..fillType = PathFillType.evenOdd;
      var bounds = Rect.zero;
      var best = 0.0;
      var anchor = Offset.zero;
      for (final ring in f.rings) {
        // Drop points closer than ~400 m; the map never zooms in that far.
        final pts = <Offset>[];
        for (final ll in ring) {
          final w = _world(ll.latitude, ll.longitude);
          if (pts.isEmpty || (w - pts.last).distanceSquared > 1.6e-5) pts.add(w);
        }
        if (pts.length < 3) continue;
        path.addPolygon(pts, true);
        final r = _ringBounds(pts);
        bounds = bounds == Rect.zero ? r : bounds.expandToInclude(r);
        final (a, c) = _areaCentroid(pts);
        if (a > best) {
          best = a;
          anchor = c;
        }
      }
      if (bounds == Rect.zero) continue;
      final inJava = _javaProvinces.contains(prov);
      // Neighbouring land (Lampung, Bali, …) is drawn plain for context.
      final near = bounds.overlaps(const Rect.fromLTRB(104.5, 5.0, 116.5, 9.6));
      if (!inJava && !near) continue;
      (inJava ? java : land).add(_Shape(f.id, f.label, prov, path, bounds, anchor, best));
    }
    // Big kabupaten first so the kota inside them stay visible.
    java.sort((a, b) => b.area.compareTo(a.area));
    if (!mounted) return;
    setState(() {
      _shapes = java;
      _land = land;
    });
  }

  Rect _ringBounds(List<Offset> pts) {
    var l = pts.first.dx, r = l, t = pts.first.dy, b = t;
    for (final p in pts) {
      l = math.min(l, p.dx);
      r = math.max(r, p.dx);
      t = math.min(t, p.dy);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  (double, Offset) _areaCentroid(List<Offset> pts) {
    var a = 0.0, cx = 0.0, cy = 0.0;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i], q = pts[(i + 1) % pts.length];
      final cross = p.dx * q.dy - q.dx * p.dy;
      a += cross;
      cx += (p.dx + q.dx) * cross;
      cy += (p.dy + q.dy) * cross;
    }
    if (a.abs() < 1e-12) return (0, pts.first);
    return (a.abs() / 2, Offset(cx / (3 * a), cy / (3 * a)));
  }

  void _setItems(List<Map<String, dynamic>> items) {
    _data = {for (final it in items) it['kabkot_id'].toString().toUpperCase(): it};
  }

  Future<void> _loadData() async {
    setState(() => _error = null);
    try {
      final d = await ApiClient.mapKabupaten(metric: _metric);
      if (!mounted) return;
      if (d['error'] != null) throw Exception(d['error']);
      setState(() => _setItems(((d['items'] as List?) ?? const []).cast<Map<String, dynamic>>()));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _select(_Shape s) async {
    setState(() {
      _selected = s.id;
      _detail = null;
      _loadingDetail = true;
    });
    if (_sheet.isAttached) _sheet.animateTo(.5, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    if (_preview) return;
    try {
      final d = await ApiClient.mapKabupatenDetail(s.name, s.prov);
      if (!mounted || _selected != s.id) return;
      if (d['error'] != null) throw Exception(d['error']);
      setState(() => _detail = d);
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  // ── View ──

  /// Where the sheet rests, as a fraction of the height (472 of 742 in the mockup).
  static const _sheetTop = .636;

  Rect get _mapRect {
    final top = MediaQuery.of(context).padding.top;
    // Between the chips and the sheet's resting edge.
    return Rect.fromLTRB(0, top + 112, _size.width, math.max(top + 200, _size.height * _sheetTop));
  }

  void _fit(Rect world, {double pad = 0}) {
    final r = _mapRect.deflate(pad);
    final s = math.min(r.width / world.width, r.height / world.height);
    setState(() {
      _scale = s;
      _origin = r.center - world.center * s;
    });
  }

  Rect _boundsOf(bool Function(_Shape) test) {
    Rect? b;
    for (final s in _shapes.where(test)) {
      b = b == null ? s.bounds : b.expandToInclude(s.bounds);
    }
    return b ?? const Rect.fromLTRB(105.1, 5.8, 114.7, 9.1);
  }

  void _zoom(double f, [Offset? focal]) {
    final c = focal ?? _mapRect.center;
    final w = (c - _origin) / _scale;
    setState(() {
      _scale = (_scale * f).clamp(30.0, 6000.0);
      _origin = c - w * _scale;
    });
  }

  _Shape? _hit(Offset screen) {
    final w = (screen - _origin) / _scale;
    // Smallest first, so a kota wins over the kabupaten around it.
    for (final s in _shapes.reversed) {
      if (s.bounds.contains(w) && s.path.contains(w)) return s;
    }
    return null;
  }

  Future<void> _locate() async {
    final c = await getCurrentCoord(context);
    if (c == null || !mounted) return;
    final w = _world(c.$1, c.$2);
    setState(() {
      _scale = math.max(_scale, 900);
      _origin = _mapRect.center - w * _scale;
    });
    final s = _hit(_origin + w * _scale);
    if (s != null) _select(s);
  }

  void _find(String q) {
    final t = q.trim().toUpperCase();
    if (t.isEmpty) return;
    final s = _shapes.where((s) => s.name.toUpperCase().contains(t)).toList()
      ..sort((a, b) => (a.name.toUpperCase().startsWith(t) ? 0 : 1).compareTo(b.name.toUpperCase().startsWith(t) ? 0 : 1));
    if (s.isEmpty) {
      showToast(context, 'Kabupaten "$q" tidak ditemukan di Jawa.', ok: false);
      return;
    }
    _searchFocus.unfocus();
    _fit(s.first.bounds, pad: 40);
    _select(s.first);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      if (size != _size) {
        _size = size;
        if (_scale == 0 && _shapes.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _fitInitial());
        }
      }
      if (_scale == 0 && _shapes.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _fitInitial());
      return ColoredBox(
        color: p.dark ? const Color(0xFF0B1716) : const Color(0xFFE3EEEC),
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: (d) {
                _startScale = _scale;
                _startOrigin = _origin;
                _startFocal = d.localFocalPoint;
              },
              onScaleUpdate: (d) {
                if (_startScale == 0) return;
                final w = (_startFocal - _startOrigin) / _startScale;
                setState(() {
                  _scale = (_startScale * d.scale).clamp(30.0, 6000.0);
                  _origin = d.localFocalPoint - w * _scale;
                });
              },
              onTapUp: (d) {
                final s = _hit(d.localPosition);
                if (s != null) _select(s);
              },
              onDoubleTapDown: (d) => _zoom(2, d.localPosition),
              onDoubleTap: () {},
              child: CustomPaint(
                painter: _MapPainter(
                  pal: p,
                  shapes: _shapes,
                  land: _land,
                  data: _data,
                  metric: _metric,
                  selected: _selected,
                  scale: _scale,
                  origin: _origin,
                  labels: _showLabels,
                  sites: _showSites ? ((_detail?['sites'] as List?) ?? const []).cast<Map>() : const [],
                ),
              ),
            ),
          ),
          Positioned(left: 16, right: 16, top: top + 12, child: _searchBar(p)),
          Positioned(
            left: 0,
            right: 0,
            top: top + 70,
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              for (final (k, l) in const [('revenue', 'Revenue MoM'), ('payload', 'Payload'), ('availability', 'Site')]) ...[
                PillChip(l, selected: _metric == k, onTap: () {
                  if (_metric == k) return;
                  setState(() => _metric = k);
                  if (!_preview) _loadData();
                }),
                const SizedBox(width: 8),
              ],
            ]),
          ),
          Positioned(right: 14, top: top + 150, child: _zoomPanel(p)),
          if (_error != null)
            Positioned(left: 16, right: 16, top: top + 120, child: InlineMessage(_error!, onRetry: _loadData)),
          _bottomSheet(p, size),
        ]),
      );
    });
  }

  void _fitInitial() {
    if (_scale != 0 || !mounted || _size == Size.zero) return;
    final focus = widget.previewFocus;
    _fit(focus == null ? _boundsOf((_) => true) : _boundsOf((s) => s.prov == focus), pad: focus == null ? 12 : 0);
  }

  Widget _searchBar(Pal p) => Container(
        height: 48,
        padding: const EdgeInsets.only(left: 15, right: 6),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.rule),
          boxShadow: p.shadow,
        ),
        child: Row(children: [
          Ic(Icx.search, size: 20, color: p.text2),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onSubmitted: _find,
              style: ts(14, w400, p.ink, lh: 1.5),
              cursorColor: p.teal600,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Cari kabupaten atau site…',
                hintStyle: ts(14, w400, p.mute, lh: 1.5),
              ),
            ),
          ),
          SquareIconButton(Icx.layers, size: 36, iconSize: 20, bordered: false, tooltip: 'Lapisan peta', onTap: _layers),
        ]),
      );

  Future<void> _layers() async {
    final p = Pal.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Center(child: SheetHandle()),
              const SizedBox(height: 16),
              Text('Lapisan peta', style: ts(18, w700, p.ink, lh: 1.35)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.white,
                activeTrackColor: p.teal600,
                title: Text('Site di kabupaten terpilih', style: ts(14, w500, p.ink)),
                value: _showSites,
                onChanged: (v) { set(() {}); setState(() => _showSites = v); },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.white,
                activeTrackColor: p.teal600,
                title: Text('Nama kabupaten', style: ts(14, w500, p.ink)),
                value: _showLabels,
                onChanged: (v) { set(() {}); setState(() => _showLabels = v); },
              ),
              const SizedBox(height: 8),
              Text(_legend(), style: ts(12, w400, p.mute, lh: 1.5)),
            ]),
          ),
        ),
      ),
    );
  }

  String _legend() => switch (_metric) {
        'availability' => 'Warna: availability 4G bulan ini. Hijau tua ≥ 99,7%, merah < 98%.',
        'payload' => 'Warna: perubahan payload MTD vs bulan lalu. Hijau naik, merah turun (merah tua ≤ −5%).',
        _ => 'Warna: perubahan revenue MTD vs bulan lalu. Hijau naik, merah turun (merah tua ≤ −5%).',
      };

  Widget _zoomPanel(Pal p) {
    Widget btn(I3 icon, String tip, VoidCallback onTap) => Tooltip(
          message: tip,
          child: InkWell(onTap: onTap, child: SizedBox(width: 44, height: 44, child: Center(child: Ic(icon, size: 20, color: p.text2)))),
        );
    return Material(
      color: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.rule)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        btn(Icx.plus, 'Perbesar', () => _zoom(1.6)),
        btn(Icx.minus, 'Perkecil', () => _zoom(1 / 1.6)),
        btn(Icx.locate, 'Lokasi saya', _locate),
      ]),
    );
  }

  // ── Sheet ──

  Widget _bottomSheet(Pal p, Size size) {
    const rest = 1 - _sheetTop;
    return DraggableScrollableSheet(
      controller: _sheet,
      initialChildSize: rest,
      minChildSize: .14,
      maxChildSize: .9,
      snap: true,
      snapSizes: const [rest],
      builder: (context, scroll) => DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: const [BoxShadow(color: Color(0x140F1F1D), offset: Offset(0, -4), blurRadius: 16)],
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            const SheetHandle(),
            const SizedBox(height: 12),
            ...(_selected == null ? _overviewContent(p) : _detailContent(p)),
          ],
        ),
      ),
    );
  }

  List<Widget> _overviewContent(Pal p) {
    final items = _data.values.where((e) => toNum(e['value']) != null).toList()
      ..sort((a, b) => toNum(a['value'])!.compareTo(toNum(b['value'])!));
    return [
      Text('Jawa', style: ts(13, w600, p.ink)),
      const SizedBox(height: 12),
      Text(_metric == 'availability' ? 'Availability terendah' : 'Penurunan terbesar', style: ts(18, w700, p.ink, lh: 1.35)),
      const SizedBox(height: 4),
      Text('Ketuk kabupaten di peta untuk melihat detail.', style: ts(12, w400, p.mute)),
      const SizedBox(height: 8),
      for (final it in items.take(6))
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(_kabName(it['kabupaten'].toString()), style: ts(14, w600, p.ink)),
          subtitle: Text(_title((it['region'] ?? it['provinsi'] ?? '').toString()), style: ts(12, w400, p.mute)),
          trailing: Text(_valueLabel(it), style: ts(13, w600, _isBad(it) ? p.danger : p.success)),
          onTap: () {
            final s = _shapes.where((s) => s.id == it['kabkot_id'].toString().toUpperCase());
            if (s.isEmpty) return;
            _fit(s.first.bounds, pad: 40);
            _select(s.first);
          },
        ),
    ];
  }

  bool _isBad(Map it) {
    final v = toNum(it['value']);
    if (v == null) return false;
    return _metric == 'availability' ? v < 99 : v < 0;
  }

  String _valueLabel(Map it) {
    final v = toNum(it['value']);
    if (v == null) return '–';
    return _metric == 'availability' ? '${idNum(v, 2)}%' : '${v >= 0 ? '+' : '−'}${idNum(v.abs(), 1)}%';
  }

  List<Widget> _detailContent(Pal p) {
    final d = _detail;
    final shape = _shapes.where((s) => s.id == _selected).firstOrNull;
    final name = d?['kabupaten']?.toString() ?? shape?.name ?? '';
    final region = (d?['region'] ?? shape?.prov ?? '').toString();
    final status = (d?['status'] ?? '').toString();
    final (label, kind) = switch (status) {
      'kritis' => ('Kritis', BadgeKind.danger),
      'perhatian' => ('Perhatian', BadgeKind.warning),
      'normal' => ('Normal', BadgeKind.success),
      _ => ('', BadgeKind.neutral),
    };
    final kpis = ((d?['kpis'] as List?) ?? const []).cast<Map>();
    final prev = (d?['prev_label'] ?? 'bulan lalu').toString().split(' ').first;
    final expl = (d?['explanation'] as Map?) ?? const {};
    return [
      Row(children: [
        GestureDetector(
          onTap: () {
            setState(() { _selected = null; _detail = null; });
            _fit(_boundsOf((_) => true), pad: 12);
          },
          child: Text('Jawa', style: ts(13, w500, p.teal700)),
        ),
        const SizedBox(width: 6),
        Ic(Icx.chevronRight, size: 14, color: p.mute),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: shape == null ? null : () => _fit(_boundsOf((s) => s.prov == shape.prov)),
          child: Text(_title(region), style: ts(13, w500, p.teal700)),
        ),
        const SizedBox(width: 6),
        Ic(Icx.chevronRight, size: 14, color: p.mute),
        const SizedBox(width: 6),
        Flexible(child: Text(_title(name.replaceFirst(RegExp(r'^KOTA ', caseSensitive: false), 'Kota ')), overflow: TextOverflow.ellipsis, style: ts(13, w600, p.ink))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text(_kabName(name), style: ts(18, w700, p.ink, lh: 1.35))),
        if (label.isNotEmpty) StatusBadge(label, kind: kind),
      ]),
      const SizedBox(height: 12),
      if (d == null && _loadingDetail)
        const Row(children: [Expanded(child: Skeleton(height: 140, radius: 16)), SizedBox(width: 8), Expanded(child: Skeleton(height: 140, radius: 16))])
      else ...[
        for (var i = 0; i < kpis.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _kpi(kpis[i], prev)),
            const SizedBox(width: 8),
            Expanded(child: i + 1 < kpis.length ? _kpi(kpis[i + 1], prev) : const SizedBox()),
          ]),
        ],
        if ((expl['text'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(color: p.teal50, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Ic(Icx.sparkles, size: 24, color: p.teal600),
                const SizedBox(width: 12),
                Expanded(child: Text(expl['text'].toString(), style: ts(12, w400, p.text2))),
              ]),
              for (final a in ((expl['actions'] as List?) ?? const []))
                Padding(
                  padding: const EdgeInsets.only(left: 36, top: 6),
                  child: Text('• $a', style: ts(12, w500, p.teal800)),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        PrimaryButton('Tanya agent soal ${_title(name)}', icon: Icx.sparkles, height: 44, onTap: () {
          widget.onAsk?.call('Kenapa performa ${_kabName(name)} bulan ini ${status == 'normal' ? 'naik' : 'turun'}? '
              'Jelaskan per kecamatan dan site, lalu beri rekomendasi.');
        }),
      ],
    ];
  }

  Widget _kpi(Map k, String prev) {
    final c = toNum(k['pct_change']);
    final v = toNum(k['value']);
    final value = v == null
        ? '–'
        : switch (k['format']) {
            'currency' => formatValue(v, 'currency'),
            'gb' => v >= 1e6 ? '${idNum(v / 1e6, 1)} PB' : v >= 1e3 ? '${idNum(v / 1e3, 1)} TB' : '${idNum(v, 1)} GB',
            'percent' => '${idNum(v, 2)}%',
            _ => formatValue(v, 'number'),
          };
    final (icon, tone) = switch (k['key']) {
      'revenue' => (Icx.wallet, Tone.amber),
      'payload' => (Icx.database, Tone.violet),
      'availability' => (Icx.radio, Tone.teal),
      _ => (Icx.userPlus, Tone.green),
    };
    return KpiTile(
      icon: icon,
      tone: tone,
      label: k['label'].toString(),
      value: value,
      caption: 'vs $prev',
      delta: c == null ? null : (k['change_unit'] == 'pp' ? '${idNum(c.abs(), 2)} pp' : '${idNum(c.abs(), 1)}%'),
      deltaUp: (c ?? 0) >= 0,
      iconSize: k['key'] == 'revenue' ? 18 : 24,
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.pal,
    required this.shapes,
    required this.land,
    required this.data,
    required this.metric,
    required this.selected,
    required this.scale,
    required this.origin,
    required this.labels,
    required this.sites,
  });
  final Pal pal;
  final List<_Shape> shapes, land;
  final Map<String, Map<String, dynamic>> data;
  final String metric;
  final String? selected;
  final double scale;
  final Offset origin;
  final bool labels;
  final List<Map> sites;

  // Diverging scale sampled from the mockup: strong rise → strong fall.
  static const _up3 = Color(0xFF15A697), _up2 = Color(0xFF5BCEC3), _up1 = Color(0xFFC0EDE8);
  static const _dn1 = Color(0xFFFAD9D9), _dn2 = Color(0xFFF29B9B), _dn3 = Color(0xFFE04848);

  Color? _fill(String id) {
    final v = toNum(data[id]?['value']);
    if (v == null) return null;
    if (metric == 'availability') {
      return v >= 99.7 ? _up3 : v >= 99.5 ? _up2 : v >= 99.0 ? _up1 : v >= 98.5 ? _dn1 : v >= 98 ? _dn2 : _dn3;
    }
    return v >= 3 ? _up3 : v >= 1 ? _up2 : v >= 0 ? _up1 : v > -2 ? _dn1 : v > -5 ? _dn2 : _dn3;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (scale == 0) return;
    final landColor = pal.dark ? const Color(0xFF162321) : const Color(0xFFF4F8F7);
    final view = Rect.fromLTWH(-origin.dx / scale, -origin.dy / scale, size.width / scale, size.height / scale);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale
      ..strokeJoin = StrokeJoin.round;
    for (final s in land) {
      if (!s.bounds.overlaps(view)) continue;
      canvas.drawPath(s.path, Paint()..color = landColor);
      canvas.drawPath(s.path, edge..color = pal.rule);
    }
    edge.color = pal.dark ? const Color(0xFF0B1716) : Colors.white;
    for (final s in shapes) {
      if (!s.bounds.overlaps(view)) continue;
      canvas.drawPath(s.path, Paint()..color = _fill(s.id) ?? landColor);
      canvas.drawPath(s.path, edge);
    }
    final sel = shapes.where((s) => s.id == selected).firstOrNull;
    if (sel != null) {
      canvas.drawPath(sel.path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / scale
        ..strokeJoin = StrokeJoin.round
        ..color = pal.ink);
    }
    canvas.restore();

    if (labels) _labels(canvas, size, sel);
    _sites(canvas);
  }

  void _labels(Canvas canvas, Size size, _Shape? sel) {
    final placed = <Rect>[];
    final screen = Offset.zero & size;
    // Name only the largest kabupaten in view (about a dozen), plus the selected one.
    final visible = shapes.where((s) => s != sel && data.containsKey(s.id) && screen.contains(origin + s.anchor * scale)).toList()
      ..sort((a, b) => b.area.compareTo(a.area));
    final ordered = [if (sel != null) sel, ...visible.take(11)];
    for (final s in ordered) {
      if (s != sel && s.bounds.width * scale < 40) continue;
      final pos = origin + s.anchor * scale;
      if (pos.dx < 0 || pos.dy < 0 || pos.dx > size.width || pos.dy > size.height) continue;
      final tp = TextPainter(
        text: TextSpan(text: _title(s.name), style: ts(10, w500, s == sel ? pal.ink : pal.text2, lh: 1.3)),
        textDirection: TextDirection.ltr,
      )..layout();
      final r = Rect.fromCenter(center: pos, width: tp.width + 4, height: tp.height);
      if (placed.any((p) => p.overlaps(r))) continue;
      placed.add(r);
      tp.paint(canvas, r.topLeft + const Offset(2, 0));
    }
  }

  void _sites(Canvas canvas) {
    final pts = <(Offset, bool)>[];
    for (final s in sites) {
      final la = toNum(s['lat']), lo = toNum(s['lon']);
      if (la == null || lo == null) continue;
      pts.add((origin + _world(la, lo) * scale, s['status'] == 'bad'));
    }
    if (pts.isEmpty) return;
    // A pulse on the worst site (the first one the API returns).
    final worst = pts.firstWhere((e) => e.$2, orElse: () => pts.first);
    if (worst.$2) {
      canvas.drawCircle(worst.$1, 22, Paint()
        ..shader = ui.Gradient.radial(worst.$1, 22, [const Color(0x40E04848), const Color(0x00E04848)]));
      canvas.drawCircle(worst.$1, 13, Paint()..color = const Color(0x33E04848));
    }
    for (final (o, bad) in pts) {
      if (bad) {
        canvas.drawCircle(o, 6, Paint()..color = Colors.white);
        canvas.drawCircle(o, 5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFE04848));
      } else {
        canvas.drawCircle(o, 6, Paint()..color = Colors.white);
        canvas.drawCircle(o, 4.5, Paint()..color = pal.teal600);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter o) =>
      o.scale != scale || o.origin != origin || o.data != data || o.selected != selected || o.metric != metric ||
      o.shapes != shapes || o.land != land || o.labels != labels || o.sites != sites || o.pal != pal;
}
