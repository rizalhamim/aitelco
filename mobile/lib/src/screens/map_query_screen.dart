import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../services/keep_alive_service.dart';
import '../app_state.dart';
import '../format/report_format.dart';
import '../theme.dart';
import '../geo/geo_assets.dart';
import '../widgets/report_ui.dart';
import 'location_sheet.dart';

class _ChoroPoly {
  final List<LatLng> ring;
  final List<List<LatLng>> holes;
  final Color color;
  final String label;
  final double value;
  final Map<String, dynamic> extra;
  _ChoroPoly(this.ring, this.color, this.label, this.value, this.extra,
      {this.holes = const []});
}

class _Turn {
  final bool isUser;
  String content;
  String? status;
  String? error;
  _Turn({required this.isUser, this.content = '', this.status});
}

class _MPoint {
  final double lat, lon;
  final String label;
  final Map<String, dynamic> info;
  final Color? color; // AI-driven marker colour
  final String? labelText; // persistent value label (AI or fix label picker)
  final bool fix; // fix-mode site: plain dot, no ranking number
  _MPoint(this.lat, this.lon, this.label, this.info,
      {this.color, this.labelText, this.fix = false});
}

class _MapSheetAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _MapSheetAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });
}

class MapFeatureFieldSliver extends StatelessWidget {
  final List<MapEntry<String, dynamic>> fields;

  const MapFeatureFieldSliver({super.key, required this.fields});

  @override
  Widget build(BuildContext context) {
    final byKey = <String, dynamic>{
      for (final field in fields) field.key.toLowerCase(): field.value,
    };
    Map<String, dynamic> mapped(List<String> aliases) {
      for (final alias in aliases) {
        final value = byKey[alias];
        if (value is Map) {
          return value.map((key, item) => MapEntry(key.toString(), item));
        }
      }
      return const {};
    }

    final current = mapped(const ['perf', 'performance', 'current_perf']);
    final mom = mapped(const ['mom', 'perf_mom', 'performance_mom']);
    final yoy = mapped(const ['yoy', 'perf_yoy', 'performance_yoy']);
    final comparisonKeys = <String>{
      if (current.isNotEmpty) ...['perf', 'performance', 'current_perf'],
      if (mom.isNotEmpty) ...['mom', 'perf_mom', 'performance_mom'],
      if (yoy.isNotEmpty) ...['yoy', 'perf_yoy', 'performance_yoy'],
    };

    // Scalars gather into one attribute panel rather than floating as loose
    // rows on the sheet background, which is what made the list read unstyled.
    final scalars = <ReportAttribute>[];
    final children = <Widget>[];
    var comparisonAdded = false;
    for (final entry in fields) {
      if (comparisonKeys.contains(entry.key.toLowerCase())) {
        if (!comparisonAdded) {
          children.add(_MapPerformanceComparison(
            current: current,
            mom: mom,
            yoy: yoy,
          ));
          comparisonAdded = true;
        }
        continue;
      }
      if (entry.value is Map || entry.value is List) {
        children.add(_MapStructuredFieldCard(
          rawKey: entry.key,
          value: entry.value,
        ));
      } else {
        scalars.add(mapFeatureAttribute(entry.key, entry.value));
      }
    }
    return SliverList.list(children: [
      if (scalars.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: ReportPanel(
            title: 'Atribut',
            subtitle: '${scalars.length} field',
            child: ReportAttributeTable(attributes: scalars),
          ),
        ),
      ...children,
    ]);
  }
}

class _MapPerformanceRow {
  final String key;
  final dynamic current;
  final dynamic mom;
  final dynamic yoy;

  const _MapPerformanceRow(this.key, this.current, this.mom, this.yoy);
}

class _MapStructuredFieldCard extends StatelessWidget {
  final String rawKey;
  final dynamic value;

  const _MapStructuredFieldCard({
    required this.rawKey,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final count = value is Map
        ? (value as Map).length
        : value is List
            ? (value as List).length
            : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ReportPanel(
        title: mapFeatureFieldLabel(rawKey),
        subtitle: '$rawKey | $count item',
        child: _MapStructuredValue(
          key: ValueKey<String>('map-structured-$rawKey'),
          value: value,
        ),
      ),
    );
  }
}

class _MapStructuredValue extends StatelessWidget {
  final dynamic value;
  final int depth;

  const _MapStructuredValue({super.key, required this.value, this.depth = 0});

  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      final entries = (value as Map).entries.toList(growable: false);
      if (entries.isEmpty) return _empty(context);
      return _render([
        for (final entry in entries)
          MapEntry(entry.key.toString(), entry.value),
      ]);
    }
    if (value is List) {
      final items = value as List;
      if (items.isEmpty) return _empty(context);
      return _render([
        for (var index = 0; index < items.length; index++)
          MapEntry('Item ${index + 1}', items[index]),
      ]);
    }
    return ReportAttributeTable(
      attributes: [mapFeatureAttribute('Value', value, depth: depth)],
    );
  }

  /// Renders a level as one attribute table, breaking out to a nested block
  /// only where a value is itself a map or a list.
  Widget _render(List<MapEntry<String, dynamic>> entries) {
    final blocks = <Widget>[];
    var pending = <ReportAttribute>[];

    void flush() {
      if (pending.isEmpty) return;
      blocks.add(ReportAttributeTable(attributes: pending));
      pending = <ReportAttribute>[];
    }

    for (final entry in entries) {
      final item = entry.value;
      if (item is Map || item is List) {
        flush();
        final count = item is Map ? item.length : (item as List).length;
        blocks.add(Padding(
          padding: EdgeInsets.only(left: depth * 8, top: 8, bottom: 4),
          child: ReportSectionHeader(
            mapFeatureFieldLabel(entry.key),
            subtitle: '${entry.key} | $count item',
          ),
        ));
        blocks.add(_MapStructuredValue(value: item, depth: depth + 1));
      } else {
        pending.add(mapFeatureAttribute(entry.key, item, depth: depth));
      }
    }
    flush();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks);
  }

  Widget _empty(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Kosong', style: TextStyle(color: context.vMute)),
      );
}

String mapFeatureFieldLabel(String key) {
  final words = key
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word.length <= 3
          ? word.toUpperCase()
          : '${word[0].toUpperCase()}${word.substring(1)}');
  return words.join(' ');
}

String mapFeatureRawValue(dynamic value) {
  if (value == null) return 'N/A';
  if (value is Map || value is List) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
  return value.toString();
}

/// Display value for one map field.
///
/// The key decides the unit, because these payloads come from arbitrary agent
/// SQL and there is no metric catalog to consult. Revenue keys get an adaptive
/// Mn or Bn, percent keys get a percent, identifiers stay ungrouped, and plain
/// counts get thousands separators.
String mapFeatureScalarValue(dynamic value, {String key = ''}) {
  if (value == null) return kReportNotAvailable;
  if (value is bool) return value ? 'Ya' : 'Tidak';
  if (key.isEmpty) {
    if (value is num) {
      return reportMagnitude(value, decimals: 1, useThousand: false);
    }
    return value.toString();
  }
  return reportValueForKey(key, value);
}

/// One field as a shared attribute row, label humanised and value formatted.
ReportAttribute mapFeatureAttribute(String key, dynamic value,
    {int depth = 0}) {
  final label = mapFeatureFieldLabel(key);
  return ReportAttribute(
    label: label,
    sublabel: label == key ? null : key,
    value: mapFeatureScalarValue(value, key: key),
    depth: depth,
  );
}

String mapFeatureGrowthValue(dynamic value) {
  if (value == null) return kReportNotAvailable;
  if (value is! num) return value.toString();
  return reportPercent(value, signed: true);
}

/// Performance panel: current value beside its MoM and YoY move.
class _MapPerformanceComparison extends StatelessWidget {
  final Map<String, dynamic> current;
  final Map<String, dynamic> mom;
  final Map<String, dynamic> yoy;

  const _MapPerformanceComparison({
    required this.current,
    required this.mom,
    required this.yoy,
  });

  @override
  Widget build(BuildContext context) {
    final keys = <String>[];
    for (final source in [current, mom, yoy]) {
      for (final key in source.keys) {
        if (!keys.contains(key)) keys.add(key);
      }
    }
    final rows = [
      for (final key in keys)
        _MapPerformanceRow(key, current[key], mom[key], yoy[key]),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ReportPanel(
        title: 'Performance Comparison',
        subtitle: '${rows.length} metrik',
        child: ReportAllDataTable<_MapPerformanceRow>(
          key: const ValueKey('map-performance-comparison'),
          semanticLabel: 'Performance current, growth MoM, dan growth YoY',
          rows: rows,
          layoutPolicy: ReportTableLayoutPolicy.horizontal,
          freezeFirstColumn: true,
          storageKey: 'map-performance-comparison',
          headerBackground: IOH.teal500,
          columns: [
            ReportTableColumn(
              label: 'Metric',
              width: 146,
              emphasized: true,
              value: (row) => mapFeatureFieldLabel(row.key),
            ),
            ReportTableColumn(
              label: 'Current',
              width: 96,
              numeric: true,
              emphasized: true,
              value: (row) => mapFeatureScalarValue(row.current, key: row.key),
            ),
            ReportTableColumn(
              label: 'MoM Growth',
              width: 104,
              numeric: true,
              comparison: true,
              value: (row) => mapFeatureGrowthValue(row.mom),
              signal: (row) => row.mom,
              polarityOf: (row) => reportPolarityFor(row.key),
            ),
            ReportTableColumn(
              label: 'YoY Growth',
              width: 104,
              numeric: true,
              comparison: true,
              value: (row) => mapFeatureGrowthValue(row.yoy),
              signal: (row) => row.yoy,
              polarityOf: (row) => reportPolarityFor(row.key),
            ),
          ],
        ),
      ),
    );
  }
}

class MapQueryScreen extends StatefulWidget {
  const MapQueryScreen({super.key});
  @override
  State<MapQueryScreen> createState() => _MapQueryScreenState();
}

class _MapQueryScreenState extends State<MapQueryScreen> {
  final _mapController = MapController();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Turn> _turns = [];
  List<_MPoint> _points = [];
  List<_ChoroPoly> _polys = [];
  String? _legendMetric;
  double _legendMin = 0, _legendMax = 0;
  String _legendColoring = 'range';
  int _unmappedCount = 0;
  int _renderGeneration = 0;
  LatLng? _userLoc;
  LocationFix? _locationFix;
  bool _satellite = true;
  bool _chatOpen = true;
  bool _busy = false;
  bool _locating = true;
  int _selected = -1;
  int? _resultCount;
  Map<String, dynamic>? _lastResult;
  Map<String, dynamic>? _lastSpec;
  // Fix mode (vs AI chat mode): nearest-site overlay from GPS.
  bool _fixMode = false;
  bool _exploreMode = false;
  bool _fixLoading = false;
  String? _fixMonth;
  bool _fixAuto = false;
  Timer? _fixTimer;
  bool _labelOn = false;
  String _labelMetric = 'revenue'; // revenue | site_id | site_name | vlr
  List<Map<String, dynamic>> _fixSitesRaw = [];
  List<Map<String, dynamic>> _exploreMetrics = [];
  Map<String, dynamic>? _exploreResult;
  Map<String, dynamic>? _exploreSpec;
  bool _exploreLoading = false;
  String _exploreError = '';
  String _exploreMetric = 'rev_prepaid';
  String _exploreCircle = 'JAVA';
  String _exploreLevel = 'kecamatan';
  String _exploreBrand = 'ioh';
  String _exploreValueMode = 'growth';
  final Set<String> _chanExpanded =
      {}; // expanded channel groups in site detail
  final List<Map<String, String>> _turnsLog = []; // {role, content} for restore
  StreamSubscription? _sub;
  // Stable per-user map session so map queries persist to history for relearning.
  late final String _sessionId = 'map_${AuthState.user?['username'] ?? 'anon'}';
  String get _stateKey => 'map_state::${AuthState.user?['username'] ?? 'anon'}';

  bool get _id => AppState.I.lang == 'id';

  static const _examples = [
    'Tampilkan 20 site dengan revenue turun bulan ini',
    '10 site terdekat dengan revenue di bawah 40 Mn',
    'Outlet IM3 terdekat dari lokasi saya',
    'Tampilkan outlet di kecamatan Wonocolo',
  ];

  @override
  void initState() {
    super.initState();
    _restoreState();
    _getLoc();
  }

  Future<void> _restoreState() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_stateKey);
      if (raw == null) return;
      final s = jsonDecode(raw) as Map<String, dynamic>;
      // restore chat bubbles
      final turns = (s['turns'] as List?) ?? [];
      for (final t in turns) {
        final m = (t as Map).cast<String, dynamic>();
        _turns.add(_Turn(
            isUser: m['role'] == 'user',
            content: (m['content'] ?? '').toString()));
      }
      // restore the last result + spec, then re-render the visual
      _lastResult = (s['result'] as Map?)?.cast<String, dynamic>();
      _lastSpec = (s['spec'] as Map?)?.cast<String, dynamic>();
      _exploreMetric = (s['explore_metric'] ?? _exploreMetric).toString();
      _exploreCircle = (s['explore_circle'] ?? _exploreCircle).toString();
      _exploreLevel = (s['explore_level'] ?? _exploreLevel).toString();
      _exploreBrand = (s['explore_brand'] ?? _exploreBrand).toString();
      _exploreValueMode =
          (s['explore_value_mode'] ?? _exploreValueMode).toString();
      if (mounted) setState(() {});
      if (_lastResult != null && _lastSpec != null) {
        await _applySpec(_lastSpec!);
      }
    } catch (_) {}
  }

  Future<void> _saveState() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _stateKey,
          jsonEncode({
            'turns': _turnsLog,
            'result': _lastResult,
            'spec': _lastSpec,
            'explore_metric': _exploreMetric,
            'explore_circle': _exploreCircle,
            'explore_level': _exploreLevel,
            'explore_brand': _exploreBrand,
            'explore_value_mode': _exploreValueMode,
          }));
    } catch (_) {}
  }

  Future<void> _refreshMap() async {
    _renderGeneration++;
    _sub?.cancel();
    _input.clear();
    setState(() {
      _turns.clear();
      _turnsLog.clear();
      _points = [];
      _polys = [];
      _legendMetric = null;
      _resultCount = null;
      _selected = -1;
      _lastResult = null;
      _lastSpec = null;
      _busy = false;
    });
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_stateKey);
    } catch (_) {}
    if (_userLoc != null) _mapController.move(_userLoc!, 12);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fixTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Fix mode ──
  void _setMode(String mode) {
    _renderGeneration++;
    final fix = mode == 'fix';
    final explore = mode == 'explore';
    setState(() {
      _fixMode = fix;
      _exploreMode = explore;
      _selected = -1;
      _points = [];
      _polys = [];
      _legendMetric = null;
      _resultCount = null;
      if (fix || explore) {
        _chatOpen = false;
      }
      if (!fix) {
        _fixAuto = false;
        _fixTimer?.cancel();
      }
    });
    if (fix) {
      _loadFixSites();
    } else if (explore) {
      if (_exploreResult != null && _exploreSpec != null) {
        _applySpec(_exploreSpec!, result: _exploreResult);
      } else {
        _loadExplore();
      }
    } else if (_lastResult != null && _lastSpec != null) {
      _applySpec(_lastSpec!);
    }
  }

  Future<void> _loadFixSites() async {
    if (_fixLoading) return;
    final generation = _renderGeneration;
    setState(() {
      _fixLoading = true;
    });
    final fix = await getCurrentLocationFix(context);
    if (!mounted) return;
    if (fix == null || generation != _renderGeneration) {
      if (mounted) setState(() => _fixLoading = false);
      return;
    }
    final loc = LatLng(fix.latitude, fix.longitude);
    _userLoc = loc;
    _locationFix = fix;
    try {
      final d = await ApiClient.nearestSites(loc.latitude, loc.longitude);
      if (!mounted || generation != _renderGeneration) return;
      if (d['ok'] == true) {
        _fixSitesRaw =
            (d['sites'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        setState(() {
          _points = _buildFixPoints();
          _fixMonth = d['month_id']?.toString();
          _selected = -1;
        });
        _fitBounds();
      } else {
        throw Exception(d['error'] ?? 'Data site belum tersedia.');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memuat site terdekat: $error')));
      }
    } finally {
      if (mounted) setState(() => _fixLoading = false);
    }
    if (mounted) setState(() => _fixLoading = false);
  }

  Future<void> _loadExploreCatalog() async {
    if (_exploreMetrics.isNotEmpty) return;
    try {
      final catalog = await ApiClient.reportMetrics();
      final metrics =
          ((catalog['metrics'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _exploreMetrics = metrics;
        if (metrics.isNotEmpty &&
            !metrics.any((metric) => metric['code'] == _exploreMetric)) {
          _exploreMetric = metrics.first['code'].toString();
        }
      });
    } catch (error) {
      if (mounted) setState(() => _exploreError = error.toString());
    }
  }

  Future<void> _loadExplore() async {
    if (_exploreLoading) return;
    setState(() {
      _exploreLoading = true;
      _exploreError = '';
      _selected = -1;
    });
    await _loadExploreCatalog();
    try {
      final data = await ApiClient.reportMapExplore(
        metric: _exploreMetric,
        circle: _exploreCircle,
        level: _exploreLevel,
        brand: _exploreBrand,
        valueMode: _exploreValueMode,
      );
      if (!mounted) return;
      if (data['error'] != null) {
        setState(() => _exploreError = data['error'].toString());
        return;
      }
      final result = Map<String, dynamic>.from(data);
      final spec =
          (data['map_spec'] as Map?)?.cast<String, dynamic>() ?? const {};
      _exploreResult = result;
      _exploreSpec = spec;
      await _applySpec(spec, result: result);
      await _saveState();
    } catch (error) {
      if (mounted) setState(() => _exploreError = error.toString());
    } finally {
      if (mounted) setState(() => _exploreLoading = false);
    }
  }

  String? _fixLabel(Map<String, dynamic> s) {
    final perf = (s['perf'] as Map?)?.cast<String, dynamic>() ?? {};
    switch (_labelMetric) {
      case 'site_id':
        return (s['site_id'] ?? '').toString();
      case 'site_name':
        return (s['site_name'] ?? s['site_id'] ?? '').toString();
      case 'vlr':
        return _mn(perf['vlr_daily']);
      default:
        return _mn(perf['rev_prepaid']); // revenue
    }
  }

  List<_MPoint> _buildFixPoints() {
    final pts = <_MPoint>[];
    for (final s in _fixSitesRaw) {
      final la = (s['latitude'] as num?)?.toDouble();
      final lo = (s['longitude'] as num?)?.toDouble();
      if (la == null ||
          lo == null ||
          !la.isFinite ||
          !lo.isFinite ||
          la.abs() > 90 ||
          lo.abs() > 180) {
        continue;
      }
      pts.add(_MPoint(
          la, lo, (s['site_name'] ?? s['site_id'] ?? 'Site').toString(), s,
          fix: true, labelText: _labelOn ? _fixLabel(s) : null));
    }
    return pts;
  }

  void _toggleLabel() {
    setState(() {
      _labelOn = !_labelOn;
      if (_fixSitesRaw.isNotEmpty) _points = _buildFixPoints();
    });
  }

  void _setLabelMetric(String m) {
    setState(() {
      _labelMetric = m;
      if (_fixSitesRaw.isNotEmpty && _labelOn) _points = _buildFixPoints();
    });
  }

  void _toggleFixAuto() {
    setState(() => _fixAuto = !_fixAuto);
    _fixTimer?.cancel();
    if (_fixAuto) {
      _fixTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (_fixMode) _loadFixSites();
      });
    }
  }

  Future<void> _getLoc() async {
    setState(() => _locating = true);
    final fix = await getCurrentLocationFix(context);
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (fix != null) {
        _locationFix = fix;
        _userLoc = LatLng(fix.latitude, fix.longitude);
      }
    });
    if (_userLoc != null && _points.isEmpty) {
      _mapController.move(_userLoc!, 13);
    }
  }

  double? _toD(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

  static const _green = Color(0xFF2FA84F);
  static const _neutral = Color(0xFFECF3F1);
  static const _red =
      Color(0xFFE13838); // semantic red (decline / low), real red

  Color _colorFor(double v, double min, double max) {
    if (max == min) return IOH.teal;
    final t = ((v - min) / (max - min)).clamp(0.0, 1.0);
    return Color.lerp(_neutral, IOH.teal, t)!;
  }

  // Zero-anchored sign scale: negative=red, ~0=neutral, positive=green.
  Color _colorBySign(double v, double maxAbs) {
    if (maxAbs <= 0) return _neutral;
    final t = (v.abs() / maxAbs).clamp(0.0, 1.0);
    return Color.lerp(_neutral, v >= 0 ? _green : _red, t)!;
  }

  // Apply the backend's authoritative map_spec against the stored result.
  Future<void> _applySpec(Map<String, dynamic> spec,
      {Map<String, dynamic>? result}) async {
    final res = result ?? _lastResult;
    if (res == null) return;
    if (result == null) _lastSpec = spec;
    final cols = (res['columns'] as List?)?.cast<String>() ?? [];
    final rows = (res['rows'] as List?) ?? [];
    final mode = (spec['mode'] ?? 'none').toString();
    if (mode == 'choropleth') {
      await _renderChoroplethSpec(spec, cols, rows);
      return;
    }
    if (mode == 'points') {
      _ingestResult(res,
          style: (spec['style'] as Map?)?.cast<String, dynamic>());
      return;
    }
    // none -> local heuristic fallback
    _ingestResult(res);
  }

  // Resolve a colour word/hex from the AI styling spec.
  Color? _resolveColor(String? c) {
    if (c == null) return null;
    final m = {
      'red': _red,
      'merah': _red,
      'yellow': IOH.yellow,
      'kuning': IOH.yellow,
      'green': _green,
      'hijau': _green,
      'teal': IOH.teal,
      'biru': const Color(0xFF2A74D4),
      'pink': IOH.pink,
      'magenta': IOH.magenta,
    };
    final lc = c.toLowerCase();
    if (m.containsKey(lc)) return m[lc];
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(c)) {
      return Color(int.parse('FF${c.substring(1)}', radix: 16));
    }
    // An agent may name an operator instead of a colour.
    final brand = Brands.of(c);
    if (Brands.all.contains(brand)) return brand.color;
    return null;
  }

  /// Marker label magnitude. `fmt` lets the agent pin a tier explicitly,
  /// otherwise the tier follows the value.
  String _fmtMagnitude(num v, String? fmt) {
    switch (fmt) {
      case 'raw':
      case 'full':
        return reportMagnitude(v, force: ReportMagnitude.plain, decimals: 2);
      case 'mn':
        return reportMagnitude(v, force: ReportMagnitude.million);
      case 'bn':
        return reportMagnitude(v, force: ReportMagnitude.billion);
      default:
        return reportMagnitude(v, decimals: 1);
    }
  }

  Future<void> _renderChoroplethSpec(
      Map<String, dynamic> spec, List<String> cols, List rows) async {
    final generation = ++_renderGeneration;
    setState(() {
      _polys = [];
      _points = [];
      _legendMetric = null;
      _resultCount = 0;
    });
    if (rows.isEmpty) return;
    final dissolveBy = (spec['dissolve_by'] ?? 'id').toString();
    final level = (spec['level'] ?? 'kecamatan').toString();
    final metricCol = (spec['metric_key'] ?? '').toString();
    final metricKey = cols.firstWhere(
        (c) => c.toLowerCase() == metricCol.toLowerCase(),
        orElse: () => '');
    if (metricKey.isEmpty) return;

    // key column whose value joins to geometry/territory
    final keyColName = dissolveBy == 'name'
        ? (spec['group_key'] ?? '').toString()
        : (spec['geo_key'] ?? spec['id_key'] ?? '').toString();
    final keyKey = cols.firstWhere(
        (c) => c.toLowerCase() == keyColName.toLowerCase(),
        orElse: () => '');
    if (keyKey.isEmpty) return;
    final labelKey = cols.firstWhere(
      (c) =>
          c.toLowerCase() ==
          (spec['label_key'] ?? keyKey).toString().toLowerCase(),
      orElse: () => keyKey,
    );

    final valueMap = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final m = (r as Map).cast<String, dynamic>();
      final key = (m[keyKey] ?? '').toString().toUpperCase();
      final v = _toD(m[metricKey]);
      if (key.isEmpty || v == null || !v.isFinite) continue;
      valueMap[key] = {
        'value': v,
        'label': (m[labelKey] ?? key).toString(),
        'extra': m
      };
    }
    if (valueMap.isEmpty) return;

    final vals = valueMap.values.map((e) => e['value'] as double).toList();
    final mn = vals.reduce((a, b) => a < b ? a : b);
    final mx = vals.reduce((a, b) => a > b ? a : b);
    final coloring = (spec['coloring'] ?? 'range').toString();
    final signMode = coloring == 'sign';
    final favorableMode = coloring == 'favorable_sign';
    final maxAbs = mn.abs() > mx.abs() ? mn.abs() : mx.abs();
    Color colorOf(Map<String, dynamic> entry) {
      final value = entry['value'] as double;
      if (favorableMode) {
        final favorable = (entry['extra'] as Map)['favorable'];
        if (favorable is! bool || maxAbs == 0) return _neutral;
        final intensity = (value.abs() / maxAbs).clamp(0.0, 1.0);
        return Color.lerp(_neutral, favorable ? _green : _red, intensity)!;
      }
      return signMode ? _colorBySign(value, maxAbs) : _colorFor(value, mn, mx);
    }

    // geometry: kabupaten only for direct kabkot_id match; else kecamatan
    final geoLevel = (dissolveBy == 'id' &&
            (spec['geo_key'] ?? spec['id_key']) == 'kabkot_id')
        ? 'kabupaten'
        : 'kecamatan';
    List<GeoFeature> feats;
    Map<String, Map<String, dynamic>>? terr;
    try {
      feats = await GeoAssets.load(geoLevel);
      if (dissolveBy == 'name') terr = await GeoAssets.territoryMap();
    } catch (_) {
      return;
    }

    if (!mounted || generation != _renderGeneration) return;
    final polys = <_ChoroPoly>[];
    final matched = <String>{};
    final allPts = <LatLng>[];
    for (final f in feats) {
      Map<String, dynamic>? entry;
      if (dissolveBy == 'name') {
        final t = terr?[f.id.toUpperCase()]?[level];
        if (t == null) continue;
        entry = valueMap[t.toString().toUpperCase()];
      } else {
        entry = valueMap[f.id.toUpperCase()];
      }
      if (entry == null) continue;
      final color = colorOf(entry);
      matched.add(entry['label'] as String);
      for (final part in f.parts) {
        polys.add(_ChoroPoly(
            part.points,
            color,
            entry['label'] as String,
            entry['value'] as double,
            (entry['extra'] as Map).cast<String, dynamic>(),
            holes: part.holes));
        allPts.addAll(part.points);
      }
    }
    if (!mounted || generation != _renderGeneration) return;
    setState(() {
      _points = [];
      _polys = polys;
      _legendMetric = (spec['legend'] ?? metricKey).toString();
      _legendColoring = coloring;
      _legendMin = signMode || favorableMode ? -maxAbs : mn;
      _legendMax = signMode || favorableMode ? maxAbs : mx;
      _resultCount = matched.length;
      _unmappedCount = rows.length - matched.length;
      _selected = -1;
    });
    if (allPts.isNotEmpty) {
      _mapController.fitCamera(
          CameraFit.coordinates(coordinates: allPts, padding: _mapPadding));
    }
  }

  bool _tryChoropleth(List<String> cols, List rows) {
    final hasKec = cols.any((c) => c.toLowerCase() == 'kec_id');
    final hasKab = cols.any((c) => c.toLowerCase() == 'kabkot_id');
    if (rows.isEmpty || (!hasKec && !hasKab)) return false;
    final level = hasKec ? 'kecamatan' : 'kabupaten';
    final idKey = hasKec
        ? cols.firstWhere((c) => c.toLowerCase() == 'kec_id')
        : cols.firstWhere((c) => c.toLowerCase() == 'kabkot_id');
    final labelKey = cols.firstWhere(
      (c) => ['kecamatan', 'kabupaten', 'kabkota', 'kabkot']
          .contains(c.toLowerCase()),
      orElse: () => idKey,
    );
    bool excluded(String c) {
      final lc = c.toLowerCase();
      if (c == idKey || c == labelKey) return true;
      if (lc.endsWith('_id')) return true;
      if ([
        'provinsi',
        'province',
        'kabupaten',
        'kabkota',
        'kecamatan',
        'region',
        'cur_month',
        'prev_month'
      ].contains(lc)) {
        return true;
      }
      if (lc.contains('month') || lc == 'periode' || lc == 'period') {
        return true;
      }
      return false;
    }

    final numeric = <String>[];
    for (final c in cols) {
      if (excluded(c)) continue;
      if (rows.any((r) => (r as Map)[c] is num)) numeric.add(c);
    }
    if (numeric.isEmpty) return false;
    final growthRe = RegExp(
        r'growth|pertumbuhan|change|delta|_pp$|_pct$|_pct_|trend',
        caseSensitive: false);
    final metricKey = numeric.firstWhere((c) => growthRe.hasMatch(c),
        orElse: () => numeric.first);

    final valueMap = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final m = (r as Map).cast<String, dynamic>();
      final id = (m[idKey] ?? '').toString().toUpperCase();
      final v = _toD(m[metricKey]);
      if (id.isEmpty || v == null) continue;
      valueMap[id] = {
        'value': v,
        'label': (m[labelKey] ?? id).toString(),
        'extra': m
      };
    }
    if (valueMap.isEmpty) return false;

    _renderChoropleth(level, valueMap, metricKey);
    return true;
  }

  Future<void> _renderChoropleth(String level,
      Map<String, Map<String, dynamic>> valueMap, String metric) async {
    final idKey = level == 'kabupaten' ? 'kabkot_id' : 'kec_id';
    final rows = valueMap.entries
        .map((entry) => <String, dynamic>{
              ...entry.value['extra'] as Map<String, dynamic>,
              idKey: entry.key,
              metric: entry.value['value'],
            })
        .toList();
    await _renderChoroplethSpec({
      'dissolve_by': 'id',
      'geo_key': idKey,
      'metric_key': metric,
      'legend': metric,
      'coloring':
          RegExp(r'growth|pertumbuhan|change|delta|trend', caseSensitive: false)
                  .hasMatch(metric)
              ? 'sign'
              : 'range',
    }, rows.first.keys.toList(), rows);
  }

  void _ingestResult(Map<String, dynamic> data, {Map<String, dynamic>? style}) {
    final cols = (data['columns'] as List?)?.cast<String>() ?? [];
    final rows = (data['rows'] as List?) ?? [];
    if (style == null && _tryChoropleth(cols, rows)) return;
    String? latKey, lonKey;
    for (final c in cols) {
      final lc = c.toLowerCase();
      if (latKey == null &&
          (lc == 'latitude' ||
              lc == 'lat' ||
              lc.endsWith('_latitude') ||
              lc.endsWith('_lat'))) {
        latKey = c;
      }
      if (lonKey == null &&
          (lc == 'longitude' ||
              lc == 'lon' ||
              lc == 'long' ||
              lc.endsWith('_longitude') ||
              lc.endsWith('_lon'))) {
        lonKey = c;
      }
    }
    if (latKey == null || lonKey == null) {
      _renderGeneration++;
      setState(() {
        _resultCount = 0;
        _points = [];
        _polys = [];
        _legendMetric = null;
      });
      return;
    }
    String labelKey = cols.firstWhere(
      (c) => RegExp(r'site_n|site_name|outlet_n|outlet_name|name|nama|kec|kab',
              caseSensitive: false)
          .hasMatch(c),
      orElse: () => cols.isNotEmpty ? cols.first : 'name',
    );

    // ---- AI styling: per-row colour rules + value label ----
    final rules = (style?['point_rules'] as List?) ?? [];
    final labelCfg = (style?['label'] as Map?)?.cast<String, dynamic>();
    String? colOf(String? name) => name == null
        ? null
        : cols.firstWhere((c) => c.toLowerCase() == name.toLowerCase(),
            orElse: () => '');
    // pre-compute rank sets
    final rankSets = <int, Set<int>>{};
    for (var ri = 0; ri < rules.length; ri++) {
      final rule = (rules[ri] as Map).cast<String, dynamic>();
      final rb = colOf(rule['rank_by']?.toString());
      final top = rule['top'];
      if (rb != null && rb.isNotEmpty && top is num) {
        final idx = <MapEntry<int, double>>[];
        for (var i = 0; i < rows.length; i++) {
          final v = _toD((rows[i] as Map)[rb]);
          if (v != null) idx.add(MapEntry(i, v));
        }
        final desc = (rule['order']?.toString() == 'desc');
        idx.sort((a, b) =>
            desc ? b.value.compareTo(a.value) : a.value.compareTo(b.value));
        rankSets[ri] = idx.take(top.toInt()).map((e) => e.key).toSet();
      }
    }
    final labelKeyName = colOf(labelCfg?['column']?.toString());

    final pts = <_MPoint>[];
    for (var i = 0; i < rows.length; i++) {
      final m = (rows[i] as Map).cast<String, dynamic>();
      final lat = _toD(m[latKey]);
      final lon = _toD(m[lonKey]);
      if (lat == null ||
          lon == null ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180) {
        continue;
      }
      Color? color;
      for (var ri = 0; ri < rules.length; ri++) {
        final rule = (rules[ri] as Map).cast<String, dynamic>();
        bool match = false;
        if (rule['default'] == true) {
          match = true;
        } else if (rankSets.containsKey(ri)) {
          match = rankSets[ri]!.contains(i);
        } else if (rule['where'] != null &&
            rule['op'] != null &&
            rule['value'] is num) {
          final wc = colOf(rule['where'].toString());
          final v = wc != null ? _toD(m[wc]) : null;
          if (v != null) {
            final t = (rule['value'] as num).toDouble();
            switch (rule['op'].toString()) {
              case '<':
                match = v < t;
                break;
              case '<=':
                match = v <= t;
                break;
              case '>':
                match = v > t;
                break;
              case '>=':
                match = v >= t;
                break;
              case '==':
                match = v == t;
                break;
            }
          }
        }
        if (match) {
          color = _resolveColor(rule['color']?.toString());
          break;
        }
      }
      String? labelText;
      if (labelCfg != null &&
          labelCfg['show'] != false &&
          labelKeyName != null &&
          labelKeyName.isNotEmpty) {
        final lv = m[labelKeyName];
        if (lv is num) {
          labelText = _fmtMagnitude(lv, labelCfg['format']?.toString());
        }
      }
      pts.add(_MPoint(lat, lon, (m[labelKey] ?? '-').toString(), m,
          color: color, labelText: labelText));
    }
    setState(() {
      _points = pts;
      _polys = [];
      _legendMetric = null;
      _resultCount = pts.length;
      _selected = -1;
    });
    if (pts.isNotEmpty) _fitBounds();
  }

  void _fitBounds() {
    final all = [
      ..._points.map((p) => LatLng(p.lat, p.lon)),
      if (_fixMode && _userLoc != null) _userLoc!
    ];
    if (all.isEmpty) return;
    if (all.length == 1) {
      _mapController.move(all.first, 15);
      return;
    }
    _mapController.fitCamera(CameraFit.coordinates(
        coordinates: all, padding: _mapPadding, maxZoom: 16));
  }

  EdgeInsets get _mapPadding => EdgeInsets.fromLTRB(
      48,
      120,
      48,
      _chatOpen && !_fixMode && !_exploreMode
          ? MediaQuery.sizeOf(context).height * .5
          : 140);

  void _onMapTap(LatLng p) {
    setState(() => _selected = -1);
    if (_polys.isEmpty) return;
    for (final poly in _polys) {
      if (GeoPolygon(poly.ring, poly.holes).contains(p)) {
        _showRegionInfo(poly);
        return;
      }
    }
  }

  void _showRegionInfo(_ChoroPoly poly) {
    _showMapFeatureSheet(
      title: poly.label,
      accent: poly.color,
      primaryLabel: _legendMetric,
      primaryValue: poly.value,
      fields: poly.extra.entries.toList(growable: false),
    );
  }

  Future<void> _showPointInfo(int index) async {
    if (index < 0 || index >= _points.length) return;
    final point = _points[index];
    setState(() => _selected = index);
    _mapController.move(LatLng(point.lat, point.lon), 15);
    final actions = <_MapSheetAction>[
      _MapSheetAction(
        label: 'Google Maps',
        icon: Icons.navigation_outlined,
        color: IOH.teal,
        onPressed: () => launchUrl(
          Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${point.lat},${point.lon}',
          ),
          mode: LaunchMode.externalApplication,
        ),
      ),
      if (_fixMode && (point.info['site_id']?.toString().isNotEmpty ?? false))
        _MapSheetAction(
          label: 'Site Performance',
          icon: Icons.insights_outlined,
          color: IOH.red,
          onPressed: () => Navigator.pushNamed(
            context,
            '/site',
            arguments: point.info['site_id'].toString(),
          ),
        ),
    ];
    await _showMapFeatureSheet(
      title: point.label,
      accent: point.color ?? IOH.teal,
      coordinates: LatLng(point.lat, point.lon),
      fields: point.info.entries.toList(growable: false),
      actions: actions,
      detailBuilder: _fixMode && point.info['perf'] != null
          ? (rebuildSheet) => _fixSiteDetail(
                point.info,
                rebuildSheet: rebuildSheet,
              )
          : null,
    );
    if (mounted && _selected == index) {
      setState(() => _selected = -1);
    }
  }

  Future<void> _showMapFeatureSheet({
    required String title,
    required Color accent,
    required List<MapEntry<String, dynamic>> fields,
    String? primaryLabel,
    dynamic primaryValue,
    LatLng? coordinates,
    List<_MapSheetAction> actions = const [],
    Widget Function(VoidCallback rebuildSheet)? detailBuilder,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: detailBuilder == null ? 0.48 : 0.68,
          minChildSize: 0.3,
          maxChildSize: 0.92,
          snap: true,
          snapSizes:
              detailBuilder == null ? const [0.48, 0.92] : const [0.68, 0.92],
          builder: (sheetContext, controller) {
            final detail = detailBuilder?.call(
              () => setSheetState(() {}),
            );
            return Semantics(
              container: true,
              label: 'Detail peta $title, ${fields.length} field',
              child: Container(
                decoration: BoxDecoration(
                  color: context.vWhite,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 24,
                      offset: const Offset(0, -6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.vRule,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Icon(
                              Icons.location_on_outlined,
                              color: accent,
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    height: 1.25,
                                    color: context.vInk,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _mapContextChip(
                                      Icons.data_object_outlined,
                                      '${fields.length} fields',
                                    ),
                                    if (coordinates != null)
                                      _mapContextChip(
                                        Icons.my_location,
                                        '${coordinates.latitude.toStringAsFixed(5)}, ${coordinates.longitude.toStringAsFixed(5)}',
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Semantics(
                            button: true,
                            label: 'Tutup detail peta',
                            child: IconButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              tooltip: 'Tutup',
                              icon: const Icon(Icons.close),
                              color: context.vMute,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (primaryLabel != null && primaryLabel.trim().isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                primaryLabel,
                                softWrap: true,
                                style: TextStyle(
                                  color: context.vMute,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SelectableText(
                              reportValueForKey(primaryLabel, primaryValue),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: context.vInk,
                                fontFamily: 'Poppins',
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    Divider(height: 1, color: context.vRule),
                    Expanded(
                      child: CustomScrollView(
                        controller: controller,
                        slivers: [
                          if (detail != null)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                child: detail,
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                detail == null ? 12 : 18,
                                16,
                                6,
                              ),
                              child: ReportSectionHeader(
                                'All Fields',
                                subtitle: '${fields.length} field',
                              ),
                            ),
                          ),
                          MapFeatureFieldSliver(fields: fields),
                          const SliverToBoxAdapter(child: SizedBox(height: 12)),
                        ],
                      ),
                    ),
                    if (actions.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                        decoration: BoxDecoration(
                          color: context.vWhite,
                          border: Border(
                            top: BorderSide(color: context.vRule),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Row(
                            children: [
                              for (var index = 0;
                                  index < actions.length;
                                  index++) ...[
                                if (index > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      final callback = actions[index].onPressed;
                                      Navigator.pop(sheetContext);
                                      callback();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size(0, 48),
                                      backgroundColor: actions[index].color,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: Icon(actions[index].icon, size: 17),
                                    label: Text(
                                      actions[index].label,
                                      textAlign: TextAlign.center,
                                      softWrap: true,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _mapContextChip(IconData icon, String label) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: context.vPanel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.vRule),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.vMute),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: context.vMute,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _send([String? preset]) async {
    final msg = (preset ?? _input.text).trim();
    if (msg.isEmpty || _busy) return;
    _input.clear();

    // Only inject GPS when the question is proximity-based; otherwise send the
    // raw message untouched so the existing AI-agent pipeline behaves normally.
    final proximityRe = RegExp(
        r'terdekat|nearest|lokasi saya|sekitar saya|sekitar sini|dekat sini|dekat saya|dari sini|di sekitar',
        caseSensitive: false);
    final hasCoord =
        RegExp(r'-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+').hasMatch(msg);
    final needsLoc = _userLoc != null && proximityRe.hasMatch(msg) && !hasCoord;
    final outgoing = needsLoc
        ? '$msg (gunakan koordinat lokasi saya: ${_userLoc!.latitude.toStringAsFixed(6)}, ${_userLoc!.longitude.toStringAsFixed(6)})'
        : msg;

    final history = <Map<String, dynamic>>[];
    for (final t
        in _turns.length > 12 ? _turns.sublist(_turns.length - 12) : _turns) {
      history.add({
        'role': t.isUser ? 'user' : 'assistant',
        'content': t.isUser
            ? t.content
            : (t.content.isNotEmpty ? t.content : (t.status ?? '')),
      });
    }

    setState(() {
      _resultCount = null;
      _points = [];
      _polys = [];
      _legendMetric = null;
      _turns.add(_Turn(isUser: true, content: msg));
      _turns.add(
          _Turn(isUser: false, status: _id ? 'Memproses…' : 'Processing…'));
      _turnsLog.add({'role': 'user', 'content': msg});
      _busy = true;
    });
    _scrollDown();
    KeepAliveService.start(
        text: _id ? 'Memproses query peta…' : 'Processing map query…');
    final ai = _turns.last;
    try {
      _sub = ApiClient.chatStream(outgoing, _sessionId, AppState.I.lang,
              history: history, mapContext: true)
          .listen((entry) {
        final ev = entry.key;
        final data = entry.value;
        if (ev == 'step_start') {
          setState(() => ai.status =
              '${data['label'] ?? data['step']} - ${data['desc'] ?? ''}');
        } else if (ev == 'status') {
          setState(() =>
              ai.status = (data['label'] ?? data['stage'] ?? '').toString());
        } else if (ev == 'result') {
          _lastResult = data;
          // points/multi-result fallback; choropleth handled by map_spec below
        } else if (ev == 'map_spec') {
          _applySpec(data);
        } else if (ev == 'token') {
          setState(() {
            ai.content += (data['t'] ?? '').toString();
            ai.status = null;
          });
          _scrollDown();
        } else if (ev == 'error') {
          setState(() {
            ai.error = (data['error'] ?? 'error').toString();
            ai.status = null;
          });
        } else if (ev == 'done') {
          setState(() => ai.status = null);
        }
      }, onError: (e) {
        KeepAliveService.stop();
        setState(() {
          ai.status = null;
          if (ai.content.isEmpty) ai.error = e.toString();
        });
      }, onDone: () {
        KeepAliveService.stop();
        if (mounted) setState(() => _busy = false);
        _turnsLog.add({'role': 'assistant', 'content': ai.content});
        _saveState();
      });
    } catch (e) {
      KeepAliveService.stop();
      setState(() {
        ai.error = e.toString();
        ai.status = null;
        _busy = false;
      });
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  String _fmt(dynamic v) {
    if (v == null) return kReportNotAvailable;
    if (v is num) return reportMagnitude(v, decimals: 1, useThousand: false);
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        _map(),
        _topBar(),
        if (_fixMode) _fixPanel(),
        if (_exploreMode) _explorePanel(),
        if (_legendMetric != null) _legend(),
        if (_resultCount != null && !_fixMode && !_exploreMode) _badge(),
        if (!_chatOpen && !_fixMode && !_exploreMode) _fab(),
        if (_chatOpen && !_fixMode && !_exploreMode) _chatPanel(),
      ]),
    );
  }

  Widget _map() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _userLoc ?? const LatLng(-7.25, 112.75),
        initialZoom: 12,
        onTap: (_, p) => _onMapTap(p),
      ),
      children: [
        TileLayer(
          urlTemplate: _satellite
              ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
              : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.bizplan.bizplan_java_agent',
        ),
        if (_polys.isNotEmpty)
          PolygonLayer(
            polygons: [
              for (final p in _polys)
                Polygon(
                  points: p.ring,
                  holePointsList: p.holes,
                  color: p.color.withValues(alpha: 0.65),
                  borderColor: Colors.white,
                  borderStrokeWidth: 1,
                ),
            ],
          ),
        if (_userLoc != null && (_locationFix?.accuracy ?? 0) > 0)
          CircleLayer(circles: [
            CircleMarker(
                point: _userLoc!,
                radius: _locationFix!.accuracy,
                useRadiusInMeter: true,
                color: IOH.magenta.withValues(alpha: .12),
                borderColor: IOH.magenta.withValues(alpha: .4),
                borderStrokeWidth: 1)
          ]),
        if (_userLoc != null)
          MarkerLayer(markers: [
            Marker(
              point: _userLoc!,
              width: 22,
              height: 22,
              child: Container(
                decoration: BoxDecoration(
                  color: IOH.magenta,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                        color: IOH.magenta.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 3)
                  ],
                ),
              ),
            ),
          ]),
        MarkerLayer(markers: [
          for (int i = 0; i < _points.length; i++)
            Marker(
              point: LatLng(_points[i].lat, _points[i].lon),
              width: 96,
              height: _points[i].labelText != null
                  ? (_points[i].fix ? 36 : 52)
                  : 48,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showPointInfo(i),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _points[i].fix
                      // Fix mode: plain dot per site (no ranking number, no grouping).
                      ? Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _points[i].color ??
                                (i == _selected ? IOH.magenta : IOH.teal),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 3)
                            ],
                          ),
                        )
                      : Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _points[i].color ??
                                (i == 0
                                    ? _red
                                    : (i == _selected
                                        ? IOH.magenta
                                        : IOH.teal)),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 4)
                            ],
                          ),
                          child: Center(
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800))),
                        ),
                  if (_points[i].labelText != null)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                          color: IOH.ink.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(5)),
                      child: Text(_points[i].labelText!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
            ),
        ]),
      ],
    );
  }

  Widget _topBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.vWhite.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.vRule),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15), blurRadius: 14)
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => Navigator.pop(context),
                color: context.vInk,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
            const SizedBox(width: 4),
            // AI/Fix toggle blended into the header (replaces the standalone bar).
            Expanded(child: _modeSeg()),
            const SizedBox(width: 6),
            IconButton(
                tooltip: _satellite ? 'Peta jalan' : 'Satelit',
                icon: Icon(_satellite
                    ? Icons.map_outlined
                    : Icons.satellite_alt_outlined),
                onPressed: () => setState(() => _satellite = !_satellite)),
          ]),
          Row(children: [
            Expanded(
              child: Text(
                _locating
                    ? '📍 …'
                    : (_userLoc != null
                        ? (_locationFix == null
                            ? 'GPS'
                            : 'GPS ±${_locationFix!.accuracy.round()} m · ${_locationFix!.timestamp.toLocal().hour.toString().padLeft(2, '0')}:${_locationFix!.timestamp.toLocal().minute.toString().padLeft(2, '0')}')
                        : '📍 N/A'),
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: context.vMute),
              ),
            ),
            IconButton(
                tooltip: 'Perbarui lokasi GPS',
                icon: const Icon(Icons.my_location, size: 18),
                onPressed: _getLoc,
                color: context.vInk,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
            IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Refresh',
                onPressed: _exploreMode ? _loadExplore : _refreshMap,
                color: context.vInk,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48)),
          ])
        ]),
      ),
    );
  }

  // Compact AI/Fix segmented control, embedded in the header bar.
  Widget _modeSeg() {
    Widget seg(String label, IconData ic, bool active, VoidCallback onTap) =>
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
                color: active ? IOH.red : Colors.transparent,
                borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ic, size: 12, color: active ? Colors.white : context.vMute),
              const SizedBox(width: 3),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: active ? Colors.white : context.vMute)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
          color: context.vPanel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.vRule)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('AI', Icons.smart_toy_outlined, !_fixMode && !_exploreMode,
            () => _setMode('ai')),
        seg('Data', Icons.layers_outlined, _exploreMode,
            () => _setMode('explore')),
        seg('Fix', Icons.cell_tower, _fixMode, () => _setMode('fix')),
      ]),
    );
  }

  Widget _labelChip() {
    return GestureDetector(
      onTap: _toggleLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: _labelOn ? IOH.teal500 : context.vPanel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _labelOn ? IOH.teal500 : context.vRule)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.label_outline,
              size: 13, color: _labelOn ? Colors.white : context.vMute),
          const SizedBox(width: 4),
          Text('Label',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: _labelOn ? Colors.white : context.vMute)),
        ]),
      ),
    );
  }

  Widget _labelPicker() {
    const opts = {
      'revenue': 'Revenue',
      'site_id': 'Site ID',
      'site_name': 'Site Name',
      'vlr': 'VLR'
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          color: context.vPanel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.vRule)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _labelMetric,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, size: 16, color: context.vMute),
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w600, color: context.vInk),
          items: opts.entries
              .map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, style: const TextStyle(fontSize: 11))))
              .toList(),
          onChanged: (v) {
            if (v != null) _setLabelMetric(v);
          },
        ),
      ),
    );
  }

  String get _exploreMetricLabel {
    for (final metric in _exploreMetrics) {
      if (metric['code'] == _exploreMetric) {
        return (metric['name'] ?? metric['code']).toString();
      }
    }
    return _exploreMetric;
  }

  Widget _exploreChip(String label) {
    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: context.vPanel,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.vRule),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.vInk)),
    );
  }

  Widget _explorePanel() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: context.vWhite.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.vRule),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.12), blurRadius: 10)
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.layers_outlined, size: 16, color: IOH.teal600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _exploreError.isNotEmpty
                    ? 'Data map belum dapat dimuat'
                    : '${_resultCount ?? 0} territory · $_exploreMetricLabel',
                maxLines: 2,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color:
                        _exploreError.isNotEmpty ? IOH.danger : context.vInk),
              ),
            ),
            IconButton(
              onPressed: _exploreLoading ? null : _showExploreFilters,
              tooltip: 'Atur data map',
              icon: const Icon(Icons.tune, size: 19),
              color: IOH.teal600,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            IconButton(
              onPressed: _exploreLoading ? null : _loadExplore,
              tooltip: 'Muat ulang data map',
              icon: _exploreLoading
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: IOH.teal500))
                  : const Icon(Icons.refresh, size: 19),
              color: IOH.teal600,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ]),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _exploreChip(_exploreCircle),
                const SizedBox(width: 5),
                _exploreChip(_exploreLevel),
                const SizedBox(width: 5),
                _exploreChip(_exploreBrand.toUpperCase()),
                const SizedBox(width: 5),
                _exploreChip(switch (_exploreValueMode) {
                  'value' => 'MTD Value',
                  'delta' => 'Absolute Change',
                  _ => 'Growth %',
                }),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _showExploreFilters() async {
    await _loadExploreCatalog();
    if (!mounted) return;
    var metric = _exploreMetric;
    var circle = _exploreCircle;
    var level = _exploreLevel;
    var brand = _exploreBrand;
    var valueMode = _exploreValueMode;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.vWhite,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Widget picker({
            required String label,
            required String value,
            required List<DropdownMenuItem<String>> items,
            required ValueChanged<String?> onChanged,
          }) {
            return DropdownButtonFormField<String>(
              value: value,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: label,
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: items,
              onChanged: onChanged,
            );
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 14, 16,
                  16 + MediaQuery.viewInsetsOf(sheetContext).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: context.vRule,
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Explore Data Map',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: context.vInk)),
                  const SizedBox(height: 4),
                  Text(
                      'Pilih metric dan grain. Semua territory pada grain terpilih tetap dimuat.',
                      style: TextStyle(fontSize: 11.5, color: context.vMute)),
                  const SizedBox(height: 16),
                  picker(
                    label: 'Metric',
                    value: metric,
                    items: [
                      for (final item in _exploreMetrics)
                        DropdownMenuItem(
                          value: item['code'].toString(),
                          child: Text('${item['name']} · ${item['category']}',
                              maxLines: 2),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => metric = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: picker(
                        label: 'Circle',
                        value: circle,
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('ALL')),
                          DropdownMenuItem(value: 'JAVA', child: Text('JAVA')),
                          DropdownMenuItem(
                              value: 'JAKARTA RAYA',
                              child: Text('JAKARTA RAYA')),
                          DropdownMenuItem(
                              value: 'SUMATERA', child: Text('SUMATERA')),
                          DropdownMenuItem(
                              value: 'KALISUMAPA', child: Text('KALISUMAPA')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setSheetState(() => circle = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: picker(
                        label: 'Grain',
                        value: level,
                        items: const [
                          DropdownMenuItem(
                              value: 'region', child: Text('Region')),
                          DropdownMenuItem(value: 'area', child: Text('Area')),
                          DropdownMenuItem(
                              value: 'district', child: Text('District')),
                          DropdownMenuItem(
                              value: 'kabkota', child: Text('Kab/Kota')),
                          DropdownMenuItem(
                              value: 'kecamatan', child: Text('Kecamatan')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setSheetState(() => level = value);
                          }
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: picker(
                        label: 'Brand',
                        value: brand,
                        items: const [
                          DropdownMenuItem(value: 'ioh', child: Text('IOH')),
                          DropdownMenuItem(value: 'im3', child: Text('IM3')),
                          DropdownMenuItem(value: '3id', child: Text('3ID')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setSheetState(() => brand = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: picker(
                        label: 'Measure',
                        value: valueMode,
                        items: const [
                          DropdownMenuItem(
                              value: 'growth', child: Text('Growth %')),
                          DropdownMenuItem(
                              value: 'delta', child: Text('Absolute Change')),
                          DropdownMenuItem(
                              value: 'value', child: Text('MTD Value')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setSheetState(() => valueMode = value);
                          }
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Terapkan ke Peta'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: IOH.teal600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (applied == true && mounted) {
      setState(() {
        _exploreMetric = metric;
        _exploreCircle = circle;
        _exploreLevel = level;
        _exploreBrand = brand;
        _exploreValueMode = valueMode;
      });
      await _loadExplore();
    }
  }

  Widget _fixPanel() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: context.vWhite.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.vRule),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)
            ]),
        child: Row(children: [
          Expanded(
              child: Text(
                  _fixLoading
                      ? 'Memuat…'
                      : '${_points.length} site${_fixMonth != null ? ' · $_fixMonth' : ''}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: context.vInk),
                  overflow: TextOverflow.ellipsis)),
          _labelChip(),
          if (_labelOn) ...[const SizedBox(width: 6), _labelPicker()],
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _toggleFixAuto,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: _fixAuto ? IOH.teal500 : context.vPanel,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: _fixAuto ? IOH.teal500 : context.vRule)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.autorenew,
                    size: 13, color: _fixAuto ? Colors.white : context.vMute),
                const SizedBox(width: 4),
                Text('Auto',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: _fixAuto ? Colors.white : context.vMute)),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _fixLoading ? null : _loadFixSites,
            child: _fixLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: IOH.teal500))
                : Icon(Icons.refresh, size: 18, color: IOH.teal600),
          ),
        ]),
      ),
    );
  }

  Widget _badge() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 60,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
              color: IOH.ink, borderRadius: BorderRadius.circular(999)),
          child: Text(
            _resultCount! > 0
                ? '$_resultCount lokasi divisualkan'
                : 'Tidak ada lokasi untuk divisualkan',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _legend() {
    final bottomOffset =
        _chatOpen ? MediaQuery.of(context).size.height * 0.48 + 24 : 24.0;
    return Positioned(
      left: 12,
      bottom: bottomOffset,
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.vWhite.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.vRule),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.2), blurRadius: 12)
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_legendMetric ?? '',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: context.vInk)),
              const SizedBox(height: 6),
              Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                      colors: _legendColoring == 'range'
                          ? [_neutral, IOH.teal]
                          : [_red, _neutral, _green]),
                ),
              ),
              const SizedBox(height: 4),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(
                    _legendColoring == 'favorable_sign'
                        ? 'Tidak favorable'
                        : _fmt(_legendMin),
                    style: TextStyle(fontSize: 10, color: context.vMute)),
                Text(
                    _legendColoring == 'favorable_sign'
                        ? 'Favorable'
                        : _fmt(_legendMax),
                    style: TextStyle(fontSize: 10, color: context.vMute)),
              ]),
              if (_unmappedCount > 0)
                Text('$_unmappedCount data tidak dapat dipetakan; lihat tabel.',
                    style: TextStyle(fontSize: 10, color: context.vMute)),
              if (_legendColoring == 'sign')
                Text('Titik tengah = 0',
                    style: TextStyle(fontSize: 10, color: context.vMute)),
            ]),
      ),
    );
  }

  Widget _fab() {
    return Positioned(
      right: 18,
      bottom: 24,
      child: FloatingActionButton(
        backgroundColor: IOH.red,
        onPressed: () => setState(() => _chatOpen = true),
        child: const Icon(Icons.chat_bubble_outline, color: Colors.white),
      ),
    );
  }

  Widget _chatPanel() {
    final h = MediaQuery.of(context).size.height;
    return Positioned(
      left: 12,
      right: 12,
      bottom: 12,
      child: Container(
        height: h * 0.48,
        decoration: BoxDecoration(
          color: context.vWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.vRule),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.25), blurRadius: 24)
          ],
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [IOH.red, IOH.magenta]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              const Text('Tanya peta',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: 14)),
              const Spacer(),
              GestureDetector(
                onTap: _refreshMap,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Row(children: [
                    Icon(Icons.restart_alt, color: Colors.white, size: 17),
                    SizedBox(width: 2),
                    Text('Reset',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _chatOpen = false),
                child: const Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ]),
          ),
          Expanded(
            child: _turns.isEmpty
                ? _exampleList()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _turns.length,
                    itemBuilder: (_, i) => _turnBubble(_turns[i]),
                  ),
          ),
          _composer(),
        ]),
      ),
    );
  }

  Widget _exampleList() {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text(_id ? 'Coba tanyakan:' : 'Try asking:',
          style: TextStyle(fontSize: 12, color: context.vMute)),
      const SizedBox(height: 8),
      for (final e in _examples)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => _send(e),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                  color: context.vPanel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.vRule)),
              child:
                  Text(e, style: TextStyle(fontSize: 13, color: context.vInk)),
            ),
          ),
        ),
    ]);
  }

  Widget _turnBubble(_Turn t) {
    if (t.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, left: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [IOH.red, IOH.magenta]),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(4)),
          ),
          child: Text(t.content,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (t.status != null)
          Text(t.status!,
              style: TextStyle(
                  fontSize: 12,
                  color: context.vMute,
                  fontStyle: FontStyle.italic)),
        if (t.error != null)
          Text(t.error!, style: const TextStyle(fontSize: 12, color: IOH.red)),
        if (t.content.isNotEmpty)
          MarkdownBody(
            data: t.content,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(fontSize: 13, color: context.vInk, height: 1.5),
              tableColumnWidth: const IntrinsicColumnWidth(),
              tableHead: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.vInk),
              tableBody:
                  TextStyle(fontSize: 12, height: 1.3, color: context.vInk),
              tableCellsPadding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              tableBorder: TableBorder.all(color: context.vRule, width: 1),
              tableScrollbarThumbVisibility: true,
            ),
          ),
      ]),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration:
          BoxDecoration(border: Border(top: BorderSide(color: context.vRule))),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 3,
            style: TextStyle(fontSize: 13, color: context.vInk),
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: _id
                  ? 'Tampilkan 20 site revenue turun…'
                  : 'Show 20 sites with revenue drop…',
              hintStyle: TextStyle(color: context.vMute, fontSize: 12),
              filled: true,
              fillColor: context.vPanel,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.vRule)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: context.vRule)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: IOH.red)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _busy ? null : () => _send(),
          child: CircleAvatar(
            radius: 19,
            backgroundColor: _busy ? IOH.mute : IOH.red,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, color: Colors.white, size: 17),
          ),
        ),
      ]),
    );
  }

  /// Adaptive magnitude: plain below a million, then Mn, then Bn.
  String _mn(dynamic v) => reportMagnitude(v, decimals: 1, useThousand: false);

  // Compact inline 12-month trend line for a given history key.
  Widget _trendChart(List<Map<String, dynamic>> hist,
      {String key = 'rev_prepaid', Color? color}) {
    final vals = hist.map((h) => (h[key] as num?)?.toDouble() ?? 0).toList();
    if (vals.length < 2) return const SizedBox.shrink();
    double maxV = vals.reduce((a, b) => a > b ? a : b);
    double minV = vals.reduce((a, b) => a < b ? a : b);
    final up = vals.last >= vals.first;
    final col = color ?? (up ? IOH.teal500 : IOH.danger);
    return SizedBox(
      height: 90,
      child: LineChart(LineChartData(
        minY: minV - (maxV - minV) * 0.1,
        maxY: maxV + (maxV - minV) * 0.1,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 18,
                  interval: (vals.length / 4).ceilToDouble().clamp(1, 99),
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= hist.length) return const SizedBox();
                    final lbl = (hist[i]['month_id'] ?? '').toString();
                    return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(lbl.length >= 4 ? lbl.substring(2) : lbl,
                            style:
                                TextStyle(fontSize: 8, color: context.vMute)));
                  })),
        ),
        lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (items) => items
                    .map((it) => LineTooltipItem(
                        _mn(it.y),
                        TextStyle(
                            color: col,
                            fontWeight: FontWeight.w700,
                            fontSize: 10)))
                    .toList())),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            color: col,
            barWidth: 2,
            dotData: FlDotData(
                show: vals.length <= 13,
                getDotPainter: (s, p, b, i) =>
                    FlDotCirclePainter(radius: 2, color: col, strokeWidth: 0)),
            belowBarData:
                BarAreaData(show: true, color: col.withValues(alpha: 0.12)),
            spots: [
              for (int i = 0; i < vals.length; i++)
                FlSpot(i.toDouble(), vals[i])
            ],
          ),
        ],
      )),
    );
  }

  Widget _fixSiteDetail(
    Map<String, dynamic> s, {
    VoidCallback? rebuildSheet,
  }) {
    final channels =
        (s['channels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final hist = (s['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final metrics = (s['metrics'] as Map?)?.cast<String, dynamic>() ?? {};
    Map<String, dynamic> block(String key) =>
        (metrics[key] as Map?)?.cast<String, dynamic>() ?? {};

    const metricList = [
      ['Rev Prepaid', 'rev_prepaid'],
      ['Rev Data', 'rev_data'],
      ['RGU 90D', 'rgu_90d'],
      ['Net Add 90D', 'net_add_90d'],
      ['VLR Daily', 'vlr_daily'],
      ['Usage GB', 'usg_data_gb'],
    ];

    ReportPeriodRow monthRow(String label, String code) {
      final m = block(code);
      return ReportPeriodRow(
        name: label,
        code: code,
        cells: {
          'extra': ReportPeriodCell(_mn(m['full_month'])),
          'llmtd': ReportPeriodCell(_mn(m['llmtd'])),
          'lmtd': ReportPeriodCell(_mn(m['lmtd'])),
          'mtd': ReportPeriodCell(_mn(m['mtd'])),
          'growthMom': ReportPeriodCell(
            reportGrowth(m['mtd_growth']),
            secondaryText:
                reportVarianceMagnitude(m['mtd_abs'], useThousand: false),
            raw: m['mtd_growth'] as num?,
          ),
        },
      );
    }

    ReportPeriodRow yearRow(String label, String code) {
      final m = block(code);
      return ReportPeriodRow(
        name: label,
        code: code,
        cells: {
          'llmtd': ReportPeriodCell(_mn(m['llytd'])),
          'lmtd': ReportPeriodCell(_mn(m['lytd'])),
          'mtd': ReportPeriodCell(_mn(m['ytd'])),
          'growthMom': ReportPeriodCell(
            reportGrowth(m['yoy_growth']),
            secondaryText:
                reportVarianceMagnitude(m['yoy_abs'], useThousand: false),
            raw: m['yoy_growth'] as num?,
          ),
        },
      );
    }

    Widget panel(String title, Widget child, {String? subtitle}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ReportPanel(title: title, subtitle: subtitle, child: child),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      panel(
        'Profil Site',
        ReportAttributeTable(attributes: [
          ReportAttribute(
              label: 'Site ID',
              value: (s['site_id'] ?? kReportNotAvailable).toString()),
          ReportAttribute(
              label: 'Jarak',
              value: s['distance_km'] == null
                  ? kReportNotAvailable
                  : '${reportNumber(s['distance_km'], decimals: 2)} km'),
          ReportAttribute(
              label: 'Type',
              value: (s['site_type'] ?? kReportNotAvailable).toString()),
          ReportAttribute(
              label: 'Category',
              value: (s['category'] ?? kReportNotAvailable).toString()),
          ReportAttribute(
              label: 'Area',
              value: (s['branch'] ?? kReportNotAvailable).toString()),
          ReportAttribute(
              label: 'District',
              value: (s['micro_cluster'] ?? kReportNotAvailable).toString()),
          ReportAttribute(
              label: 'Kecamatan',
              value:
                  '${s['kecamatan'] ?? kReportNotAvailable}, ${s['kabupaten'] ?? kReportNotAvailable}'),
          if (s['profitability_status_m1'] != null)
            ReportAttribute(
                label: 'Profitability',
                value: s['profitability_status_m1'].toString()),
        ]),
      ),
      panel(
        'Monthly Absolute',
        ReportPeriodTable(
          rows: [for (final m in metricList) monthRow(m[0], m[1])],
          band: Brands.ioh,
          storageKey: 'map-site-monthly-${s['site_id']}',
          nameLabel: 'Metric',
          columns: const [
            ReportPeriodColumn.extra,
            ReportPeriodColumn.llmtd,
            ReportPeriodColumn.lmtd,
            ReportPeriodColumn.mtd,
            ReportPeriodColumn.growthMom,
          ],
          extraLabel: 'Full Mth',
        ),
        subtitle: 'Full month, LLMTD, LMTD, MTD',
      ),
      panel(
        'Year to Date',
        ReportPeriodTable(
          rows: [for (final m in metricList) yearRow(m[0], m[1])],
          band: Brands.ioh,
          storageKey: 'map-site-yoy-${s['site_id']}',
          nameLabel: 'Metric',
          columns: ReportPeriodTable.monthOnlyPeriods,
        ),
        subtitle: 'LLYTD, LYTD, YTD',
      ),
      if (hist.length >= 2) ...[
        panel('Trend Rev Prepaid (12 bln)',
            _trendChart(hist, key: 'rev_prepaid')),
        panel('Trend VLR Daily (12 bln)',
            _trendChart(hist, key: 'vlr_daily', color: IOH.magenta)),
      ],
      if (channels.isNotEmpty)
        panel(
          'Profil Revenue per Channel',
          ReportAllDataTable<Map<String, dynamic>>(
            semanticLabel: 'Revenue per channel',
            rows: channels
                .where((c) => ((c['value'] as num?)?.toDouble() ?? 0) > 0)
                .toList(growable: false),
            layoutPolicy: ReportTableLayoutPolicy.horizontal,
            freezeFirstColumn: true,
            headerBackground: Brands.ioh.color,
            storageKey: 'map-site-channels-${s['site_id']}',
            columns: [
              ReportTableColumn(
                label: 'Channel',
                width: 150,
                value: (row) => row['label'],
              ),
              ReportTableColumn(
                label: 'Nilai',
                width: 96,
                numeric: true,
                emphasized: true,
                value: (row) => row['value'],
                formatter: (value) => _mn(value),
              ),
              ReportTableColumn(
                label: 'Share',
                width: 84,
                numeric: true,
                value: (row) => row['share_pct'],
                formatter: (value) => reportPercent(value),
              ),
              ReportTableColumn(
                label: 'MoM',
                width: 96,
                numeric: true,
                comparison: true,
                value: (row) => row['mom_pct'],
                formatter: (value) => reportGrowth(value),
                signal: (row) => row['mom_pct'],
                polarity: ReportPolarity.higherIsBetter,
              ),
            ],
          ),
        ),
      ..._channelGroupsSection(s, rebuildSheet: rebuildSheet),
    ]);
  }

  // Revenue Data per channel group, expandable to channel detail, with
  // Full Month / LLMTD / LMTD / MTD / Growth and LLYTD / LYTD / YTD / Growth,
  // apple-to-apple.
  List<Widget> _channelGroupsSection(
    Map<String, dynamic> s, {
    VoidCallback? rebuildSheet,
  }) {
    final groups =
        (s['channel_groups'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (groups.isEmpty) return const [];
    final sid = (s['site_id'] ?? '').toString();

    ReportPeriodRow row(
      String label,
      Map<String, dynamic> m, {
      required bool monthly,
      bool indented = false,
      String? expandKey,
      bool expanded = false,
    }) {
      final growth = (monthly ? m['mtd_growth'] : m['yoy_growth']) as num?;
      final abs = monthly ? m['mtd_abs'] : m['yoy_abs'];
      return ReportPeriodRow(
        name: label,
        code: 'rev_channel',
        indented: indented,
        headline: !indented,
        expandKey: expandKey,
        expanded: expanded,
        cells: {
          if (monthly) 'extra': ReportPeriodCell(_mn(m['full_month'])),
          'llmtd': ReportPeriodCell(_mn(monthly ? m['llmtd'] : m['llytd'])),
          'lmtd': ReportPeriodCell(_mn(monthly ? m['lmtd'] : m['lytd'])),
          'mtd': ReportPeriodCell(_mn(monthly ? m['mtd'] : m['ytd'])),
          'growthMom': ReportPeriodCell(
            reportGrowth(growth),
            secondaryText: reportVarianceMagnitude(abs, useThousand: false),
            raw: growth,
          ),
        },
      );
    }

    List<ReportPeriodRow> build({required bool monthly}) {
      final out = <ReportPeriodRow>[];
      for (final g in groups) {
        final group = (g['channel_group'] ?? '').toString();
        final key = '$sid|$group';
        final open = _chanExpanded.contains(key);
        final details =
            (g['details'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        out.add(row(
          group,
          g,
          monthly: monthly,
          expandKey: details.isEmpty ? null : key,
          expanded: open,
        ));
        if (!open) continue;
        for (final detail in details) {
          out.add(row(
            (detail['detail'] ?? '').toString(),
            detail,
            monthly: monthly,
            indented: true,
          ));
        }
      }
      return out;
    }

    void toggle(String key) {
      setState(() => _chanExpanded.contains(key)
          ? _chanExpanded.remove(key)
          : _chanExpanded.add(key));
      rebuildSheet?.call();
    }

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ReportPanel(
          title: 'Revenue Data per Channel',
          subtitle: 'Full month, LLMTD, LMTD, MTD',
          child: ReportPeriodTable(
            rows: build(monthly: true),
            band: Brands.ioh,
            storageKey: 'map-channel-monthly-$sid',
            nameLabel: 'Channel',
            columns: const [
              ReportPeriodColumn.extra,
              ReportPeriodColumn.llmtd,
              ReportPeriodColumn.lmtd,
              ReportPeriodColumn.mtd,
              ReportPeriodColumn.growthMom,
            ],
            extraLabel: 'Full Mth',
            onToggleRow: toggle,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ReportPanel(
          title: 'Revenue Data per Channel',
          subtitle: 'LLYTD, LYTD, YTD',
          child: ReportPeriodTable(
            rows: build(monthly: false),
            band: Brands.ioh,
            storageKey: 'map-channel-yoy-$sid',
            nameLabel: 'Channel',
            columns: ReportPeriodTable.monthOnlyPeriods,
            onToggleRow: toggle,
          ),
        ),
      ),
    ];
  }
}
