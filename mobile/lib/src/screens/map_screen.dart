// Peta tab (05 Peta Agent): kecamatan map of one kabupaten with a chat sheet.
// Every answer adds layers (choropleth, site points, uploaded SHP/GeoJSON/KML/CSV)
// and the map recolours by Performance, Site productivity or Profile wilayah.
// The frame comes projected from /api/map/agent (backend/app/map_agent.py), so the
// paths are drawn as they are; only the view (x, y, zoom) lives here.
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../api/api_client.dart';
import '../ui/answer_v2.dart' show Triangle;
import '../ui/kit.dart' show showToast;
import '../ui/mock_icons.dart';
import '../ui/v2.dart';

const _div = [Color(0xFFC42B2B), Color(0xFFE5634F), Color(0xFFF4A08A), Color(0xFFF9D6CB), Color(0xFFD8EFEA), Color(0xFF7FCFC3)];
const _seq = [Color(0xFFEAF6F3), Color(0xFFC3E8E1), Color(0xFF8FD6CB), Color(0xFF4FB8AA), Color(0xFF1A9483), Color(0xFF0A6A5F)];
const _cats = [('perf', 'Performance', 'pulse'), ('prod', 'Site productivity', 'tower'), ('prof', 'Profile', 'users')];

Color _divCol(double v) => v <= -12
    ? _div[0]
    : v <= -8
        ? _div[1]
        : v <= -4
            ? _div[2]
            : v < 0
                ? _div[3]
                : v < 2
                    ? _div[4]
                    : _div[5];

double? _n(Object? v) => v is num ? v.toDouble() : null;

String _idn(double v, int d) {
  final s = v.abs().toStringAsFixed(d);
  final parts = s.split('.');
  final int0 = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${v < 0 ? '-' : ''}$int0${d > 0 ? ',${parts[1]}' : ''}';
}

String _pct(double v) => '${v > 0 ? '+' : v < 0 ? '−' : ''}${_idn(v.abs(), 1)}%';

String fmtMetric(Map<String, dynamic> m, double? v) {
  if (v == null) return '-';
  if (m['kind'] == 'div') return _pct(v);
  final scale = _n(m['scale']) ?? 1;
  return '${m['pre'] ?? ''}${_idn(v / scale, (m['d'] as num).toInt())}${m['unit'] ?? ''}';
}

List<Path> _parse(String d) {
  final out = <Path>[];
  for (final ring in d.split('M')) {
    final r = ring.replaceAll('Z', '').trim();
    if (r.isEmpty) continue;
    final p = Path();
    var first = true;
    for (final pair in r.split(' ')) {
      final xy = pair.split(',');
      if (xy.length != 2) continue;
      final x = double.parse(xy[0]), y = double.parse(xy[1]);
      if (first) {
        p.moveTo(x, y);
        first = false;
      } else {
        p.lineTo(x, y);
      }
    }
    out.add(p..close());
  }
  return out;
}

Path _join(List<Path> rings) {
  final p = Path()..fillType = PathFillType.evenOdd;
  for (final r in rings) {
    p.addPath(r, Offset.zero);
  }
  return p;
}

class _View {
  const _View(this.x, this.y, this.z);
  final double x, y, z;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.onAsk, this.preview, this.previewMessages, this.previewShape, this.focusSite, this.kabupaten = ''});

  /// Opens a question in Tanya Agent (site popup "Tanya").
  final void Function(String q)? onAsk;

  /// Widget tests: map payload, chat turns and uploaded shape without network.
  final Map<String, dynamic>? preview;
  final List<Map<String, dynamic>>? previewMessages;
  final Map<String, dynamic>? previewShape;
  final String? focusSite;
  final String kabupaten;

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  String _kab = '';
  String _cat = 'perf';
  String _metric = 'payload_mom';
  bool _chor = true, _crit = true, _up = true, _all = true;
  double _opacity = .85;
  String _critMetric = 'payload_mom';
  double _critT = -10;
  Map<String, dynamic>? _shape;
  final List<Map<String, dynamic>> _points = [];
  _View? _view;
  Size _size = Size.zero;
  double _sheetH = 392;
  final List<Map<String, dynamic>> _msgs = [];
  final _input = TextEditingController();
  bool _busy = false;
  Map<String, dynamic>? _pending;
  String? _selSite;
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;
  List<double>? _pendingFocus;

  // parsed geometry
  final Map<String, Path> _unitPath = {};
  List<Path> _neighbors = [];
  Path? _outline;
  Path? _shapePath;

  @override
  void initState() {
    super.initState();
    _kab = widget.kabupaten;
    if (widget.preview != null) {
      _setData(widget.preview!);
      if (widget.previewShape != null) _setShape(widget.previewShape!);
      for (final m in widget.previewMessages ?? const <Map<String, dynamic>>[]) {
        _msgs.add(m);
        if (m['role'] == 'agent') _apply(m);
      }
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  /// Opens the map on one site (from Performance "Lihat di peta").
  void focusSite(String siteId) {
    final s = _sites.where((x) => x['id'] == siteId).firstOrNull;
    if (s == null) {
      _kab = '';
      _load(site: siteId);
      return;
    }
    setState(() {
      _selSite = siteId;
      _view = _fit([_x(s) - 60, _y(s) - 50, _x(s) + 60, _y(s) + 50]);
    });
  }

  Future<void> _load({String site = ''}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ApiClient.mapAgent(kabupaten: _kab, site: site);
      if (!mounted) return;
      setState(() {
        _setData(d);
        _view = null;
        if (site.isNotEmpty) _selSite = site;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setData(Map<String, dynamic> d) {
    _data = d;
    _kab = (d['scope'] as Map)['kabupaten'] as String? ?? _kab;
    _unitPath
      ..clear()
      ..addEntries([for (final u in _units) MapEntry(u['n'] as String, _join(_parse(u['d'] as String)))]);
    _neighbors = [for (final n in (d['neighbors'] as List? ?? [])) _join(_parse((n as Map)['d'] as String))];
    final o = d['outline'] as String? ?? '';
    _outline = o.isEmpty ? null : _join(_parse(o));
  }

  void _setShape(Map<String, dynamic> s) {
    _shape = s;
    final d = s['d'] as String? ?? '';
    _shapePath = d.isEmpty ? null : _join(_parse(d));
    _up = true;
  }

  List<Map<String, dynamic>> get _units => [for (final u in (_data?['units'] as List? ?? [])) u as Map<String, dynamic>];
  List<Map<String, dynamic>> get _sites => [for (final s in (_data?['sites'] as List? ?? [])) s as Map<String, dynamic>];
  List<Map<String, dynamic>> get _metrics => [for (final m in (_data?['metrics'] as List? ?? [])) m as Map<String, dynamic>];
  Map<String, dynamic>? get _m => _metrics.where((m) => m['key'] == _metric).firstOrNull ?? _metrics.firstOrNull;
  double _x(Map s) => _n(s['x'])!;
  double _y(Map s) => _n(s['y'])!;
  String get _unitWord => _data?['unit_level'] == 'kabupaten' ? 'kabupaten' : 'kecamatan';

  List<Map<String, dynamic>> get _critSites =>
      [for (final s in _sites) if (_n(s[_critMetric]) != null && _n(s[_critMetric])! <= _critT) s];

  int get _layerCount => (_chor ? 1 : 0) + (_crit ? 1 : 0) + (_shape != null && _up ? 1 : 0) + (_all ? 1 : 0) + _points.length;

  // ── view ──
  EdgeInsets get _free => EdgeInsets.fromLTRB(0, 12, 0, _sheetH);

  _View _fit(List<double> b, [EdgeInsets? free]) {
    final f = free ?? _free;
    final fw = math.max(_size.width - f.left - f.right, 80.0), fh = math.max(_size.height - f.top - f.bottom, 80.0);
    final z = math.min(math.min(fw / math.max(b[2] - b[0], 1), fh / math.max(b[3] - b[1], 1)), 8.0);
    final cx = (b[0] + b[2]) / 2, cy = (b[1] + b[3]) / 2;
    return _View(cx - (f.left + fw / 2) / z, cy - (f.top + fh / 2) / z, z);
  }

  _View _home() {
    final fr = _data!['frame'] as Map;
    return _fit([0, 0, _n(fr['w'])!, _n(fr['h'])!], EdgeInsets.fromLTRB(0, 0, 0, _sheetH));
  }

  void _ensureView() {
    if (_data == null || _size == Size.zero) return;
    if (_pendingFocus != null) {
      _view = _fit(_pendingFocus!);
      _pendingFocus = null;
    }
    if (_view != null) return;
    final site = _selSite == null ? null : _sites.where((x) => x['id'] == _selSite).firstOrNull;
    _view = site != null ? _fit([_x(site) - 60, _y(site) - 50, _x(site) + 60, _y(site) + 50]) : _home();
  }

  // ── chat ──
  void _apply(Map<String, dynamic> a) {
    for (final l in (a['layers'] as List? ?? [])) {
      final m = l as Map;
      if (m['kind'] == 'chor' && m['metric'] != null) {
        final meta = _metrics.where((x) => x['key'] == m['metric']).firstOrNull;
        if (meta != null) {
          _cat = meta['cat'] as String;
          _metric = meta['key'] as String;
        }
        _chor = true;
      } else if (m['kind'] == 'sites') {
        _critMetric = m['metric'] as String? ?? 'payload_mom';
        _critT = _n(m['threshold']) ?? -10;
        _crit = true;
      } else if (m['kind'] == 'point') {
        _points.add(Map<String, dynamic>.from(m));
      }
    }
    final f = a['focus'] as List?;
    if (f != null) {
      _pendingFocus = [for (final v in f) (v as num).toDouble()];
      _view = null;
    }
  }

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.isEmpty || _busy || _data == null) return;
    final scope = _data!['scope'] as Map;
    setState(() {
      _msgs.add({'role': 'user', 'text': q, if (_pending != null) 'file': _pending});
      _pending = null;
      _input.clear();
      _busy = true;
    });
    try {
      final a = await ApiClient.mapAgentAsk(q,
          region: scope['region'] as String? ?? '',
          kabupaten: scope['kabupaten'] as String? ?? '',
          shapes: [if (_shape != null) {'rings': _shape!['rings'], 'name': _shape!['name']}]);
      if (!mounted) return;
      setState(() {
        _msgs.add({'role': 'agent', ...a});
        _apply(a);
        _ensureView();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.add({
            'role': 'agent', 'time': _now(), 'layers': [], 'stats': [], 'actions': [],
            'text': 'Maaf, jawaban belum bisa dibuat (${e.toString().replaceFirst('Exception: ', '')}). Coba lagi sebentar.',
          }));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _now() {
    final d = DateTime.now();
    return '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _attach() async {
    final r = await FilePicker.pickFiles(type: FileType.any, withData: true);
    final f = r?.files.firstOrNull;
    if (f == null || f.bytes == null || !mounted) return;
    if (f.size > 20 * 1024 * 1024) {
      showToast(context, 'File lebih dari 20 MB', ok: false);
      return;
    }
    try {
      final scope = _data!['scope'] as Map;
      final s = await ApiClient.mapAgentUpload(f.name, f.bytes!, region: scope['region'] as String? ?? '', kabupaten: scope['kabupaten'] as String? ?? '');
      if (!mounted) return;
      setState(() {
        _setShape(s);
        _pending = s;
      });
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  Future<void> _voice() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(onStatus: (s) {
      if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
    });
    if (!ok) {
      if (mounted) showToast(context, 'Input suara tidak tersedia di perangkat ini.', ok: false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: 'id_ID'),
      onResult: (r) {
        _input.text = r.recognizedWords;
        if (r.finalResult && mounted) setState(() => _listening = false);
      },
    );
  }

  void _newChat() {
    setState(() {
      _msgs.clear();
      _points.clear();
      _shape = null;
      _shapePath = null;
      _pending = null;
      _critMetric = 'payload_mom';
      _critT = -10;
      _cat = 'perf';
      _metric = 'payload_mom';
      _view = _home();
    });
  }

  // ── exports ──
  List<Map<String, dynamic>> _features(List ids) {
    final by = {for (final s in _sites) s['id']: s};
    return [
      for (final id in ids)
        if (by[id] != null)
          {
            'type': 'Feature',
            'geometry': {'type': 'Point', 'coordinates': [by[id]!['lon'], by[id]!['lat']]},
            'properties': {'site_id': id, 'kecamatan': by[id]!['k'], 'status': by[id]!['status'], 'payload_mom': by[id]!['payload_mom'], 'revenue_mom': by[id]!['revenue_mom']},
          },
      if (_shape != null && (_shape!['rings'] as List).isNotEmpty)
        {'type': 'Feature', 'geometry': {'type': 'Polygon', 'coordinates': _shape!['rings']}, 'properties': {'nama': _shape!['label'], 'area_km2': _shape!['area_km2']}},
    ];
  }

  Future<void> _export(String fmt, List ids) async {
    try {
      final name = 'peta_agent_${_kab.toLowerCase().replaceAll(RegExp(r'\W+'), '_')}';
      final bytes = await ApiClient.mapAgentExport(fmt, name, _features(ids));
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${fmt == 'shp' ? '${name}_shp.zip' : '$name.$fmt'}');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: name));
    } catch (e) {
      if (mounted) showToast(context, 'Ekspor gagal: ${e.toString().replaceFirst('Exception: ', '')}', ok: false);
    }
  }

  // ── gestures ──
  _View? _gStart;
  Offset _gFocal = Offset.zero;

  Offset _toFrame(Offset p) => Offset(_view!.x + p.dx / _view!.z, _view!.y + p.dy / _view!.z);

  void _onTap(Offset p) {
    if (_view == null || _data == null) return;
    final f = _toFrame(p);
    final hitR = 9 / _view!.z;
    final candidates = [if (_crit) ..._critSites, if (_all) ..._sites];
    for (final s in candidates) {
      if ((Offset(_x(s), _y(s)) - f).distance <= hitR) {
        setState(() => _selSite = s['id'] as String);
        _siteSheet(s);
        return;
      }
    }
    for (final u in _units.reversed) {
      if (_unitPath[u['n']]?.contains(f) ?? false) {
        _unitSheet(u);
        return;
      }
    }
  }

  // ── build ──
  @override
  Widget build(BuildContext context) {
    final scope = V2Scope.maybeOf(context);
    final sc = _data?['scope'] as Map?;
    final top = MediaQuery.of(context).padding.top;
    return Column(children: [
      Container(height: top, color: Colors.white),
      V2AppBar(
        title: 'Peta Agent',
        subtitle: sc == null ? (_error ?? 'memuat…') : '${sc['name']} · $_layerCount layer',
        subtitleDot: _error != null || _loading ? const Color(0xFFE0A100) : const Color(0xFF2E9E57),
        alertCount: scope?.alerts ?? 0,
        onBell: scope == null ? null : () => scope.openAlerts(),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          if (_size != c.biggest) {
            _size = c.biggest;
            _sheetH = math.min(_sheetH, _size.height - 56);
          }
          _ensureView();
          return Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned.fill(child: _map()),
            Positioned(left: 12, top: 12, right: 66, height: 32, child: _metricChips()),
            Positioned(left: 12, top: 54, child: _legend()),
            Positioned(right: 12, top: 12, child: _fab('layers', _layersSheet, badge: '$_layerCount')),
            Positioned(right: 12, top: 64, child: _fab('locate', () => setState(() => _view = _home()))),
            if (_error != null && _data == null)
              Positioned(left: 24, right: 24, top: 120, child: _errorCard()),
            Positioned(left: 0, right: 0, bottom: 0, height: _sheetH, child: _sheet()),
          ]);
        }),
      ),
    ]);
  }

  Widget _errorCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: V2.rule)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: V2.d(13, FontWeight.w500, V2.ink), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('Coba lagi')),
        ]),
      );

  Widget _map() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (d) {
        _gStart = _view;
        _gFocal = d.localFocalPoint;
      },
      onScaleUpdate: (d) {
        final v = _gStart;
        if (v == null) return;
        final nz = (v.z * d.scale).clamp(.4, 16.0);
        final fx = v.x + _gFocal.dx / v.z, fy = v.y + _gFocal.dy / v.z;
        setState(() => _view = _View(fx - d.localFocalPoint.dx / nz, fy - d.localFocalPoint.dy / nz, nz));
      },
      onTapUp: (d) => _onTap(d.localPosition),
      onDoubleTapDown: (d) => _gFocal = d.localPosition,
      onDoubleTap: () {
        final v = _view;
        if (v == null) return;
        final fx = v.x + _gFocal.dx / v.z, fy = v.y + _gFocal.dy / v.z, nz = math.min(v.z * 1.6, 16.0);
        setState(() => _view = _View(fx - _gFocal.dx / nz, fy - _gFocal.dy / nz, nz));
      },
      child: CustomPaint(
        size: Size.infinite,
        painter: _MapPainter(
          view: _view,
          neighbors: _neighbors,
          units: [for (final u in _units) (_unitPath[u['n']]!, _fill(u), u)],
          outline: _outline,
          shape: _up ? _shapePath : null,
          shapePoints: _up ? [for (final p in (_shape?['points'] as List? ?? [])) Offset(_n((p as List)[0])!, _n(p[1])!)] : const [],
          chor: _chor,
          opacity: _opacity,
          sites: _all ? [for (final s in _sites) if (!(_crit && _critSites.contains(s))) Offset(_x(s), _y(s))] : const [],
          crit: _crit ? [for (final s in _critSites) Offset(_x(s), _y(s))] : const [],
          bigCrit: _crit ? _worstCrit() : null,
          selected: _selSite == null ? null : _sites.where((s) => s['id'] == _selSite).map((s) => Offset(_x(s), _y(s))).firstOrNull,
          points: [for (final p in _points) Offset(_n(p['x'])!, _n(p['y'])!)],
          labels: [for (final u in _units) if (u['label'] == true) (u['n'] as String, Offset(_n(u['cx'])!, _n(u['cy'])!))],
        ),
      ),
    );
  }

  Offset? _worstCrit() {
    final c = _critSites;
    if (c.isEmpty) return null;
    c.sort((a, b) => (_n(a['payload_mom']) ?? 0).compareTo(_n(b['payload_mom']) ?? 0));
    return Offset(_x(c.first), _y(c.first));
  }

  ({List<double> brk, List<double> vals}) _breaks() {
    final m = _m;
    final vals = [for (final u in _units) if (_n((u['m'] as Map)[m?['key']]) != null) _n((u['m'] as Map)[m!['key']])!]..sort();
    if (vals.isEmpty) return (brk: const [], vals: vals);
    return (brk: [for (var i = 1; i <= 5; i++) vals[(vals.length * i / 6).floor()]], vals: vals);
  }

  Color _fill(Map<String, dynamic> u) {
    final m = _m;
    final v = _n((u['m'] as Map)[m?['key']]);
    if (m == null || v == null) return const Color(0xFFE6ECEA);
    if (m['kind'] == 'div') return _divCol(v);
    final b = _breaks().brk;
    return _seq[b.where((x) => v >= x).length];
  }

  Widget _metricChips() {
    final m = _m;
    final icon = _cats.firstWhere((c) => c.$1 == _cat, orElse: () => _cats.first).$3;
    final others = _cats.where((c) => c.$1 != _cat);
    Widget chip(String label, String ic, {bool on = false, bool chev = false, VoidCallback? tap}) => GestureDetector(
          onTap: tap,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: on ? V2.ink : Colors.white,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: on ? V2.ink : V2.rule),
              boxShadow: const [BoxShadow(color: Color(0x1A0F1F1D), offset: Offset(0, 4), blurRadius: 12)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MIcon(ic, size: 13, color: on ? Colors.white : V2.ink2),
              const SizedBox(width: 5),
              Text(label, style: V2.d(11.5, FontWeight.w600, on ? Colors.white : V2.ink2, lh: 1)),
              if (chev) ...[const SizedBox(width: 5), MIcon('chev', size: 13, color: on ? Colors.white : V2.ink2)],
            ]),
          ),
        );
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        maxWidth: double.infinity,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          chip(m?['name'] as String? ?? 'Payload MoM', icon, on: true, chev: true, tap: _metricSheet),
          for (final c in others)
            chip(c.$2, c.$3, tap: () => setState(() {
                  _cat = c.$1;
                  _metric = _metrics.firstWhere((x) => x['cat'] == c.$1, orElse: () => {'key': _metric})['key'] as String;
                })),
        ]),
      ),
    );
  }

  Widget _legend() {
    final m = _m;
    final div = m == null || m['kind'] == 'div';
    final b = _breaks();
    final ticks = div
        ? const ['−15%', '0', '+5%']
        : b.vals.isEmpty
            ? const ['-', '', '-']
            : [_idn(b.vals.first / (_n(m['scale']) ?? 1), (m['d'] as num).toInt()), '', _idn(b.vals.last / (_n(m['scale']) ?? 1), (m['d'] as num).toInt())];
    return Container(
      width: 168,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xF5FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: V2.rule),
        boxShadow: const [BoxShadow(color: Color(0x1F0F1F1D), offset: Offset(0, 10), blurRadius: 30)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 11, child: Text(m?['name'] as String? ?? 'Payload MoM', style: V2.d(11, FontWeight.w600, V2.ink, lh: 1))),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(width: 148, height: 7, child: Row(children: [for (final c in div ? _div : _seq) Expanded(child: Container(color: c))])),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 148,
          height: 9.5,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final t in ticks) Text(t, style: V2.d(9.5, FontWeight.w500, V2.mute, lh: 1)),
          ]),
        ),
      ]),
    );
  }

  Widget _fab(String icon, VoidCallback onTap, {String? badge}) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: V2.rule),
                boxShadow: const [BoxShadow(color: Color(0x240F1F1D), offset: Offset(0, 6), blurRadius: 18)],
              ),
              child: MIcon(icon, size: 20, color: V2.teal700),
            ),
            if (badge != null)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  height: 18,
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: V2.teal600, borderRadius: BorderRadius.circular(9), border: Border.all(color: Colors.white, width: 2)),
                  child: Text(badge, style: V2.d(10, FontWeight.w700, Colors.white, lh: 1)),
                ),
              ),
          ]),
        ),
      );

  // ── chat sheet ──
  Widget _sheet() {
    final answers = _msgs.where((m) => m['role'] == 'agent').length;
    final last = _msgs.lastWhere((m) => m['role'] == 'agent', orElse: () => const {});
    final sugg = <String>[
      if ((last['actions'] as List? ?? []).contains('sites')) 'Daftar ${(last['site_ids'] as List? ?? []).length} site',
      ...((last['suggestions_short'] ?? last['suggestions'] ?? const ['Payload MoM per kecamatan', 'Site productivity', 'Profile wilayah']) as List).cast<String>(),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Color(0x290F1F1D), offset: Offset(0, -10), blurRadius: 30)],
      ),
      child: Column(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) => setState(() => _sheetH = (_sheetH - d.delta.dy).clamp(150.0, math.max(_size.height - 40, 150.0))),
          onVerticalDragEnd: (_) {
            final stops = [150.0, math.min(392.0, _size.height * .62), math.max(_size.height - 40, 150.0)];
            stops.sort((a, b) => (a - _sheetH).abs().compareTo((b - _sheetH).abs()));
            setState(() => _sheetH = stops.first);
          },
          child: Column(children: [
            Container(width: 40, height: 5, margin: const EdgeInsets.fromLTRB(0, 8, 0, 4), decoration: BoxDecoration(color: const Color(0xFFCBD6D3), borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                height: 16.8,
                child: Row(children: [
                  Text('Percakapan peta', style: V2.d(14, FontWeight.w600, V2.ink, lh: 1.2)),
                  const Spacer(),
                  if (_msgs.isNotEmpty)
                    GestureDetector(onLongPress: _newChat, child: Text('$answers jawaban · $_layerCount layer', style: V2.d(11.5, FontWeight.w500, V2.teal700, lh: 1)))
                  else
                    Text('$_layerCount layer', style: V2.d(11.5, FontWeight.w500, V2.teal700, lh: 1)),
                ]),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _msgs.isEmpty
              ? Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text('Tanya tentang peta: warnai per kecamatan, tandai site yang turun, cek koordinat, atau upload SHP lalu tanya isi areanya.',
                        style: V2.b(13, FontWeight.w400, V2.mute, lh: 1.5)),
                  ),
                )
              : ListView(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    if (_busy) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Agent Java sedang menyusun layer…', style: V2.d(12, FontWeight.w500, V2.mute))),
                    for (var i = _msgs.length - 1; i >= 0; i--) ...[
                      _msgs[i]['role'] == 'user' ? _userMsg(_msgs[i]) : _agentMsg(_msgs[i]),
                      if (i > 0) const SizedBox(height: 10),
                    ],
                  ],
                ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            children: [
              for (final s in sugg)
                GestureDetector(
                  onTap: () => s.startsWith('Daftar ') ? _siteList(last) : _send(s),
                  child: Container(
                    height: 30,
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: V2.teal200)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const MIcon('spark', size: 13, color: V2.coral),
                      const SizedBox(width: 6),
                      Text(s, style: V2.d(12, FontWeight.w500, V2.teal700, lh: 1)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: V2.teal200, width: 1.5)),
                child: Row(children: [
                  GestureDetector(onTap: _attach, child: const MIcon('clip', size: 18, color: V2.ink2)),
                  const SizedBox(width: 8),
                  if (_pending != null)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                      decoration: BoxDecoration(color: V2.coral, borderRadius: BorderRadius.circular(6)),
                      child: Text(_pending!['kind'] == 'GeoJSON' ? 'GEO' : '${_pending!['kind']}', style: V2.d(9, FontWeight.w700, Colors.white, lh: 1)),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onSubmitted: (_) => _send(),
                      textInputAction: TextInputAction.send,
                      style: V2.b(13, FontWeight.w400, V2.ink),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: _pending != null ? 'Tanya tentang ${_pending!['name']}…' : 'Tanya tentang peta…',
                        hintStyle: V2.b(13, FontWeight.w400, V2.mute),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: _voice, child: MIcon('mic', size: 18, color: _listening ? V2.teal600 : V2.ink2)),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: V2.teal600, borderRadius: BorderRadius.circular(14)),
                child: const MIcon('send', size: 18, color: Colors.white),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  double _tw(String text, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  Widget _userMsg(Map<String, dynamic> m) {
    final f = m['file'] as Map?;
    // CSS max-content width: the longest of the question line and the file card.
    var w = _tw('${m['text']}', V2.b(13, FontWeight.w400, Colors.white, lh: 1.45));
    if (f != null) {
      w = math.max(w, 64 + math.max(_tw('${f['name']}', V2.d(12.5, FontWeight.w600, Colors.white, lh: 1.25)), _tw('${f['count']} · ${f['size_kb']} KB', V2.b(11, FontWeight.w400, V2.teal100, lh: 1.3))));
    }
    w = math.min(w.ceilToDouble(), 276);
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: w + 24,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: const BoxDecoration(
              color: V2.teal600,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(6)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (f != null) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: const Color(0x24FFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x38FFFFFF)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: V2.coral, borderRadius: BorderRadius.circular(9)),
                      child: Text(f['kind'] == 'GeoJSON' ? 'GEO' : '${f['kind']}', style: V2.d(10, FontWeight.w700, Colors.white, lh: 1)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(height: 15.6, child: Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(12.5, FontWeight.w600, Colors.white, lh: 1.25))),
                        const SizedBox(height: 1),
                        SizedBox(height: 17, child: Text('${f['count']} · ${f['size_kb']} KB', style: V2.b(11, FontWeight.w400, V2.teal100, lh: 1.3))),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
              V2Lines(TextSpan(text: '${m['text']}', style: V2.b(13, FontWeight.w400, Colors.white, lh: 1.45)), lineHeight: 18.85),
            ]),
          ),
      ),
    );
  }

  List<InlineSpan> _bold(String text, TextStyle base) {
    final out = <InlineSpan>[];
    final re = RegExp(r'\*\*([^*]+)\*\*');
    var i = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > i) out.add(TextSpan(text: text.substring(i, m.start)));
      out.add(TextSpan(text: m.group(1), style: base.copyWith(fontWeight: FontWeight.w600)));
      i = m.end;
    }
    if (i < text.length) out.add(TextSpan(text: text.substring(i)));
    return out;
  }

  Widget _agentMsg(Map<String, dynamic> m) {
    final base = V2.b(13, FontWeight.w400, V2.ink, lh: 1.5);
    final layers = (m['layers'] as List? ?? []).cast<Map>();
    final stats = (m['stats'] as List? ?? []).cast<Map>();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: V2.rule),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 22,
          child: Row(children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), gradient: const LinearGradient(colors: [V2.teal600, V2.lagoon])),
              child: const MIcon('spark', size: 13, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Text('Agent Java', style: V2.d(12, FontWeight.w600, V2.teal700, lh: 1)),
            const Spacer(),
            Text('${m['time'] ?? ''}', style: V2.b(11, FontWeight.w400, V2.mute, lh: 1)),
          ]),
        ),
        const SizedBox(height: 8),
        V2Lines(TextSpan(style: base, children: _bold('${m['text_short'] ?? m['text']}', base)), lineHeight: 19.5),
        if (layers.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final l in layers)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(color: const Color(0xFFF2FBFA), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDCEFEC))),
              child: Row(children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: l['kind'] == 'chor' ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: l['kind'] == 'chor' ? BorderRadius.circular(4) : null,
                    gradient: l['kind'] == 'chor' ? const LinearGradient(colors: [Color(0xFFC42B2B), Color(0xFFF4A08A), Color(0xFF7FCFC3)]) : null,
                    color: l['kind'] == 'chor' ? null : (l['kind'] == 'sites' ? V2.red : V2.teal600),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(child: Text('${l['label']}', style: V2.d(12, FontWeight.w600, V2.ink, lh: 1.2))),
                GestureDetector(
                  onTap: () => setState(() {
                    if (l['kind'] == 'point') {
                      _view = _fit([_n(l['x'])! - 50, _n(l['y'])! - 44, _n(l['x'])! + 50, _n(l['y'])! + 44]);
                    } else if (l['kind'] == 'sites' && _critSites.isNotEmpty) {
                      final c = _critSites;
                      _view = _fit([c.map(_x).reduce(math.min) - 20, c.map(_y).reduce(math.min) - 20, c.map(_x).reduce(math.max) + 20, c.map(_y).reduce(math.max) + 20]);
                    } else {
                      _view = _home();
                    }
                  }),
                  child: Row(children: [const MIcon('zoomto', size: 12, color: V2.teal700), const SizedBox(width: 4), Text('Zoom', style: V2.d(11, FontWeight.w500, V2.teal700, lh: 1))]),
                ),
              ]),
            ),
        ],
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _stat(stats[i])),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _stat(Map s) {
    final sub = '${s['sub'] ?? ''}'.replaceAll(' MoM', '');
    final down = s['tone'] == 'down', up = s['tone'] == 'up';
    final col = down ? V2.red : up ? const Color(0xFF1F7A3A) : V2.mute;
    final arrow = sub.startsWith('▼') || sub.startsWith('▲');
    return Container(
      height: 65.2,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: 12.6, child: Text('${s['short'] ?? s['label']}', style: V2.d(10.5, FontWeight.w500, V2.mute, lh: 1.2))),
        const SizedBox(height: 3),
        SizedBox(height: 18, child: Text('${s['value']}', maxLines: 1, style: V2.d(15, FontWeight.w700, V2.ink, lh: 1.2))),
        const SizedBox(height: 3),
        SizedBox(
          height: 12.6,
          child: Row(children: [
            if (arrow) ...[Triangle(up: sub.startsWith('▲'), color: col, width: 9, height: 8), const SizedBox(width: 3)],
            Text(arrow ? sub.substring(2) : sub, style: V2.d(10.5, FontWeight.w600, col, lh: 1.2)),
          ]),
        ),
      ]),
    );
  }

  // ── sheets ──
  Future<void> _sheetOf(Widget Function(BuildContext, StateSetter) body) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .8),
              child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: body(ctx, set)),
            ),
          ),
        ),
      );

  Widget _sheetTitle(String t, [String? sub]) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: const Color(0xFFCBD6D3), borderRadius: BorderRadius.circular(3)))),
          Text(t, style: V2.d(16, FontWeight.w600, V2.ink)),
          if (sub != null) Text(sub, style: V2.b(12, FontWeight.w400, V2.mute)),
        ]),
      );

  void _metricSheet() => _sheetOf((ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sheetTitle('Warnai peta dengan'),
        for (final c in _cats) ...[
          Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(c.$1 == 'prof' ? 'PROFILE WILAYAH' : c.$2.toUpperCase(), style: V2.d(10.5, FontWeight.w600, V2.teal700, ls: .6))),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in _metrics.where((m) => m['cat'] == c.$1))
              ChoiceChip(
                label: Text('${m['name']}${m['available'] == false ? ' (belum ada data)' : ''}'),
                selected: _metric == m['key'],
                onSelected: (_) {
                  setState(() {
                    _cat = c.$1;
                    _metric = m['key'] as String;
                  });
                  Navigator.pop(ctx);
                },
              ),
          ]),
        ],
        if (_cat == 'prod') Padding(padding: const EdgeInsets.only(top: 10), child: Text('Tipe site: Semua (tipe site belum ada di dump Performance).', style: V2.b(12, FontWeight.w400, V2.mute))),
      ]));

  void _layersSheet() => _sheetOf((ctx, set) {
        Widget row(String title, String sub, bool on, void Function(bool) change) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Colors.white,
              activeTrackColor: V2.teal600,
              title: Text(title, style: V2.d(13, FontWeight.w600, V2.ink)),
              subtitle: Text(sub, style: V2.b(11.5, FontWeight.w400, V2.mute)),
              value: on,
              onChanged: (v) {
                setState(() => change(v));
                set(() {});
              },
            );
        final m = _m;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sheetTitle('Layer', '$_layerCount aktif'),
          row('${m?['name'] ?? 'Payload MoM'} per $_unitWord', 'Choropleth · ${_units.length} $_unitWord', _chor, (v) => _chor = v),
          Row(children: [
            Text('Opasitas', style: V2.d(11.5, FontWeight.w500, V2.mute)),
            Expanded(
              child: Slider(
                value: _opacity,
                min: .2,
                max: 1,
                activeColor: V2.teal600,
                onChanged: (v) {
                  setState(() => _opacity = v);
                  set(() {});
                },
              ),
            ),
            Text('${(_opacity * 100).round()}%', style: V2.d(11.5, FontWeight.w500, V2.mute)),
          ]),
          row('Site ${_critMetric == 'revenue_mom' ? 'revenue' : 'payload'} turun > ${_idn(_critT.abs(), 0)}%', 'Titik koordinat · ${_critSites.length} site', _crit, (v) => _crit = v),
          if (_shape != null)
            row('${_shape!['label']}', (_shape!['d'] as String? ?? '').isNotEmpty ? 'Poligon ${_shape!['kind']} · ${_idn(_n(_shape!['area_km2']) ?? 0, 1)} km²' : 'Titik ${_shape!['kind']} · ${_shape!['count']}', _up, (v) => _up = v),
          row('Semua site', 'Titik koordinat · ${_sites.length} site${(_data?['sites_without_coord'] ?? 0) > 0 ? ' (+${_data!['sites_without_coord']} tanpa koordinat)' : ''}', _all, (v) => _all = v),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(onPressed: () => _scopeSheet(ctx), icon: const MIcon('pin', size: 16, color: V2.teal700), label: const Text('Ganti wilayah')),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _newChat();
              },
              icon: const MIcon('plus', size: 16, color: V2.teal700),
              label: const Text('Percakapan baru'),
            ),
          ]),
        ]);
      });

  Future<void> _scopeSheet(BuildContext from) async {
    Navigator.pop(from);
    List<dynamic> groups = [];
    try {
      groups = await ApiClient.mapAgentScopes();
    } catch (_) {}
    if (!mounted) return;
    var q = '';
    await _sheetOf((ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sheetTitle('Pilih wilayah'),
          TextField(decoration: const InputDecoration(hintText: 'Cari kabupaten atau kota…', isDense: true), onChanged: (v) => set(() => q = v.toLowerCase())),
          for (final g in groups) ...[
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text('${(g as Map)['province']}'.toUpperCase(), style: V2.d(10.5, FontWeight.w600, V2.teal700, ls: .6))),
            for (final it in (g['items'] as List))
              if (q.isEmpty || '${(it as Map)['name']}'.toLowerCase().contains(q))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${(it as Map)['name']}'),
                  selected: it['kabupaten'] == _kab,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _kab = it['kabupaten'] as String;
                      _shape = null;
                      _shapePath = null;
                      _points.clear();
                      _selSite = null;
                    });
                    _load();
                  },
                ),
          ],
        ]));
  }

  void _unitSheet(Map<String, dynamic> u) {
    final sc = _data!['scope'] as Map;
    final prefix = _unitWord == 'kecamatan' ? 'Kec. ' : '';
    final st = u['status'] as String? ?? 'normal';
    _sheetOf((ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sheetTitle('$prefix${u['n']}', '${sc['level'] == 'kabupaten' ? '${sc['name']} · ' : ''}${u['sites']} site · ${_data!['month_label']} · ${st[0].toUpperCase()}${st.substring(1)}'),
          for (final c in _cats) ...[
            Padding(padding: const EdgeInsets.only(top: 6, bottom: 5), child: Text(c.$1 == 'prof' ? 'PROFILE WILAYAH' : c.$2.toUpperCase(), style: V2.d(10.5, FontWeight.w600, V2.teal700, ls: .6))),
            Row(children: [
              for (final m in _metrics.where((m) => m['cat'] == c.$1).take(3))
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 5),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(9)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m['short']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(10, FontWeight.w500, V2.mute)),
                      Text(fmtMetric(m, _n((u['m'] as Map)[m['key']])),
                          style: V2.d(13, FontWeight.w700, m['kind'] == 'div' && _n((u['m'] as Map)[m['key']]) != null ? (_n((u['m'] as Map)[m['key']])! < 0 ? V2.red : const Color(0xFF1F7A3A)) : V2.ink)),
                    ]),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: V2.teal600),
                onPressed: () {
                  Navigator.pop(ctx);
                  _send('Profile $prefix${u['n']}');
                },
                icon: const MIcon('spark', size: 16, color: Colors.white),
                label: const Text('Tanya di peta'),
              ),
            ),
          ]),
        ]));
  }

  void _siteSheet(Map<String, dynamic> s) {
    final pm = _n(s['payload_mom']), rm = _n(s['revenue_mom']);
    _sheetOf((ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sheetTitle('${s['id']}', 'Kec. ${s['k']}${s['name'] != null ? ' · ${s['name']}' : ''} · ${s['status']}'),
          Row(children: [
            for (final (label, v) in [('Payload MoM', pm), ('Revenue MoM', rm)])
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(label, style: V2.d(10.5, FontWeight.w500, V2.mute)),
                    Text(v == null ? '-' : _pct(v), style: V2.d(14, FontWeight.w700, (v ?? 0) < 0 ? V2.red : const Color(0xFF1F7A3A))),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('${(s['lat'] as num).toStringAsFixed(5)}, ${(s['lon'] as num).toStringAsFixed(5)}', style: V2.b(13, FontWeight.w400, V2.ink))),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: '${s['lat']}, ${s['lon']}'));
                showToast(ctx, 'Koordinat disalin');
              },
              icon: const MIcon('copy', size: 16, color: V2.teal700),
              label: const Text('Salin'),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: V2.teal600),
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onAsk?.call('Kenapa site ${s['id']} di Kec. ${s['k']} ${(pm ?? 0) < 0 ? 'turun' : 'berubah'} di ${_data?['month_label']}? Bandingkan payload, revenue dan availability dengan bulan lalu.');
                },
                icon: const MIcon('spark', size: 16, color: Colors.white),
                label: const Text('Tanya Agent'),
              ),
            ),
          ]),
        ])).then((_) {
      if (mounted) setState(() => _selSite = null);
    });
  }

  void _siteList(Map last) {
    final by = {for (final s in _sites) s['id']: s};
    final ids = (last['site_ids'] as List? ?? []);
    _sheetOf((ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sheetTitle('Daftar ${ids.length} site', 'Koordinat dan perubahan MoM'),
          Wrap(spacing: 6, children: [
            OutlinedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: [for (final id in ids) if (by[id] != null) '$id\t${by[id]!['lat']}\t${by[id]!['lon']}'].join('\n')));
                showToast(ctx, 'Koordinat disalin');
              },
              child: const Text('Salin koordinat'),
            ),
            OutlinedButton(onPressed: () => _export('csv', ids), child: const Text('CSV')),
            OutlinedButton(onPressed: () => _export('geojson', ids), child: const Text('GeoJSON')),
            OutlinedButton(onPressed: () => _export('shp', ids), child: const Text('SHP (.zip)')),
          ]),
          const SizedBox(height: 8),
          for (final id in ids)
            if (by[id] != null)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('$id · Kec. ${by[id]!['k']}', style: V2.d(13, FontWeight.w600, V2.ink)),
                subtitle: Text('${(by[id]!['lat'] as num).toStringAsFixed(5)}, ${(by[id]!['lon'] as num).toStringAsFixed(5)}', style: V2.b(12, FontWeight.w400, V2.mute)),
                trailing: Text(_n(by[id]!['payload_mom']) == null ? '-' : _pct(_n(by[id]!['payload_mom'])!),
                    style: V2.d(12.5, FontWeight.w600, (_n(by[id]!['payload_mom']) ?? 0) < 0 ? V2.red : const Color(0xFF1F7A3A))),
                onTap: () {
                  Navigator.pop(ctx);
                  focusSite(id as String);
                },
              ),
        ]));
  }
}

/// Symbol scale of the approved phone mockup: dots, strokes and labels are drawn
/// at 97% of the web size so they stay light on the smaller screen.
const _sym = .971;

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.view,
    required this.neighbors,
    required this.units,
    required this.outline,
    required this.shape,
    required this.shapePoints,
    required this.chor,
    required this.opacity,
    required this.sites,
    required this.crit,
    required this.bigCrit,
    required this.selected,
    required this.points,
    required this.labels,
  });

  final _View? view;
  final List<Path> neighbors;
  final List<(Path, Color, Map<String, dynamic>)> units;
  final Path? outline, shape;
  final List<Offset> shapePoints, sites, crit, points;
  final bool chor;
  final double opacity;
  final Offset? bigCrit, selected;
  final List<(String, Offset)> labels;

  Path _dashed(Path src, double on, double off) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        out.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
        d += on + off;
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFD6EAF0));
    final v = view;
    if (v == null) return;
    final u = _sym / v.z;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(v.z);
    canvas.translate(-v.x, -v.y);
    final white = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white;
    for (final n in neighbors) {
      canvas.drawPath(n, Paint()..color = const Color(0xFFE6ECEA));
      canvas.drawPath(n, white..strokeWidth = 1.2 * u);
    }
    for (final (p, c, _) in units) {
      if (chor) canvas.drawPath(p, Paint()..color = c.withValues(alpha: opacity));
      canvas.drawPath(p, white..strokeWidth = u);
    }
    if (outline != null) {
      canvas.drawPath(outline!, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * u
        ..strokeJoin = StrokeJoin.round
        ..color = V2.teal700);
    }
    if (shape != null) {
      canvas.drawPath(shape!, Paint()..color = const Color(0x29FFFFFF));
      canvas.drawPath(shape!, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * u
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white);
      canvas.drawPath(_dashed(shape!, 7 * u, 4 * u), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * u
        ..color = V2.ink);
    }
    for (final p in shapePoints) {
      canvas.drawCircle(p, 3.2 * u, Paint()..color = V2.ink);
    }
    final dot = Paint()..color = const Color(0xBF3D4C49);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8 * u
      ..color = Colors.white;
    for (final s in sites) {
      canvas.drawCircle(s, 2.2 * u, dot);
      canvas.drawCircle(s, 2.2 * u, ring);
    }
    canvas.restore();

    // labels in screen space
    for (final (name, c) in labels) {
      final sx = (c.dx - v.x) * v.z, sy = (c.dy - v.y) * v.z;
      if (sx < 20 || sx > size.width - 20 || sy < 10 || sy > size.height - 10) continue;
      final style = const TextStyle(fontFamily: V2.display, fontSize: 10.5 * _sym, fontWeight: FontWeight.w600, height: 1);
      final stroke = TextPainter(
        text: TextSpan(text: name, style: style.copyWith(foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * _sym
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white)),
        textDirection: TextDirection.ltr,
      )..layout();
      final fill = TextPainter(text: TextSpan(text: name, style: style.copyWith(color: V2.ink)), textDirection: TextDirection.ltr)..layout();
      final base = fill.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      final o = Offset(sx - fill.width / 2, sy - base);
      stroke.paint(canvas, o);
      fill.paint(canvas, o);
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(v.z);
    canvas.translate(-v.x, -v.y);
    for (final p in points) {
      canvas.drawCircle(p, 9 * u, Paint()..color = V2.teal600.withValues(alpha: .2));
      canvas.drawCircle(p, 4.5 * u, Paint()..color = V2.teal600);
      canvas.drawCircle(p, 4.5 * u, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 * u
        ..color = Colors.white);
    }
    final red = Paint()..color = V2.red;
    final redRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * u
      ..color = Colors.white;
    for (final s in crit) {
      final big = s == bigCrit || s == selected;
      if (big) canvas.drawCircle(s, 10 * u, Paint()..color = V2.red.withValues(alpha: .18));
      final r = (big ? 6 : 4.6) * u;
      canvas.drawCircle(s, r, red);
      canvas.drawCircle(s, r, redRing);
    }
    if (selected != null && !crit.contains(selected)) {
      canvas.drawCircle(selected!, 6 * u, Paint()..color = V2.teal600);
      canvas.drawCircle(selected!, 6 * u, redRing);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MapPainter o) => true;
}

