import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../theme.dart';
import 'location_sheet.dart' show getCurrentCoord;

const _circles = ['JAVA', 'KALISUMAPA', 'JAKARTA RAYA', 'SUMATERA'];

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<Map<String, dynamic>> _categories = [];
  String _mode = 'mycoord'; // mycoord | territory | snapshot
  String _subTab = 'comprehensive'; // comprehensive | datarev | product
  String get _tab => _mode == 'snapshot' ? 'snapshot' : _subTab;
  List<Map<String, dynamic>>? _mcLevels; // located territory levels
  String _mcPick = '';
  String _geoErr = '';
  String _metric = 'rev_prepaid';
  String _circle = 'JAVA';
  String _pdScope = 'total';
  String _scopeType = 'all';
  String _scopeValue = '';
  List<String> _scopeOptions = [];
  String _brand = 'ioh'; // ioh | im3 | 3id
  bool _showFilters = false;
  String _deckTab = 'circle'; // circle | region | branch | microcluster | kabkota | kecamatan
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _comp;
  Map<String, dynamic>? _drev;
  Map<String, dynamic>? _prod;
  Map<String, dynamic>? _bench;
  Map<String, dynamic>? _insight;
  Map<String, dynamic>? _ftth;
  bool _loading = false;
  String? _error;
  String _dataVer = '';
  final Map<String, Map<String, dynamic>> _cache = {};
  final Set<String> _drExpanded = {}; // expanded data-revenue channels
  String _slabScope = 'total'; // total | organic | digital | trade
  String _slabDetail = ''; // selected channel_detail within scope
  String _pdSlabScope = 'total'; // product-demand slab scope tab
  String _pdSlabDetail = ''; // product-demand channel detail within scope
  String _pdSlabDim = 'quota'; // quota | validity

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final m = await ApiClient.reportMetrics();
      final cats = (m['categories'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) setState(() => _categories = cats);
    } catch (_) {}
    try {
      _dataVer = await ApiClient.reportDataVersion();
    } catch (_) {}
    _load();
  }

  // Re-check the server data marker; if it changed, drop the cache so the next
  // load pulls fresh data.
  Future<void> _refreshDataVersion() async {
    final v = await ApiClient.reportDataVersion();
    if (v.isNotEmpty && v != _dataVer) {
      _dataVer = v;
      _cache.clear();
    }
  }

  Future<void> _loadScopeOptions() async {
    if (_scopeType == 'all') {
      setState(() { _scopeOptions = []; _scopeValue = ''; });
      return;
    }
    try {
      final vals = _tab == 'ftth'
          ? await ApiClient.reportFtthScopeOptions(circle: _circle, level: _scopeType)
          : await ApiClient.reportScopeOptions(circle: _circle, level: _scopeType);
      if (mounted) setState(() => _scopeOptions = vals);
    } catch (_) {}
  }

  void _assign(String tab, Map<String, dynamic> d) {
    if (tab == 'snapshot') _data = d;
    else if (tab == 'comprehensive') _comp = d;
    else if (tab == 'datarev') _drev = d;
    else if (tab == 'benchmark') _bench = d;
    else if (tab == 'insight') _insight = d;
    else if (tab == 'ftth') _ftth = d;
    else _prod = d;
  }

  Future<void> _load({bool force = false}) async {
    // My Coordinate: wait until a located level is picked (scope set).
    if (_mode == 'mycoord' && _scopeValue.isEmpty) { setState(() => _loading = false); return; }
    final ft = (_scopeType != 'all' && _scopeValue.isNotEmpty) ? _scopeType : 'all';
    final fv = (_scopeType != 'all') ? _scopeValue : '';
    // snapshot/comprehensive payloads carry all brands → brand not in key.
    // _dataVer makes keys change when server data is refreshed.
    String keyFor() => _tab == 'snapshot' ? 'snap|$_dataVer|$_circle|$_metric|$ft|$fv'
        : _tab == 'comprehensive' ? 'comp|$_dataVer|$_circle|$ft|$fv'
        : _tab == 'datarev' ? 'drev|$_dataVer|$_circle|$_brand|$ft|$fv'
        : _tab == 'benchmark' ? 'bench|$_dataVer|$_circle|$ft|$fv'
        : _tab == 'insight' ? 'ins|$_dataVer|$_circle|$ft|$fv'
        : _tab == 'ftth' ? 'ftth|$_dataVer|$_circle|$ft|$fv'
        : 'prod|$_dataVer|$_circle|$_pdScope|$_brand';

    if (force) {
      _cache.clear();
      await _refreshDataVersion();
      // tell the server to rebuild fresh too
      try { await ApiClient.reportCacheClear(); } catch (_) {}
    }
    final key = keyFor();
    if (_cache.containsKey(key)) {
      setState(() { _error = null; _assign(_tab, _cache[key]!); _loading = false; });
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      Map<String, dynamic> d;
      if (_tab == 'snapshot') {
        d = await ApiClient.reportSnapshot(metric: _metric, circle: _circle, filterType: ft, filterValue: fv);
      } else if (_tab == 'comprehensive') {
        d = await ApiClient.reportComprehensive(circle: _circle, filterType: ft, filterValue: fv);
      } else if (_tab == 'datarev') {
        d = await ApiClient.reportDataRevenue(circle: _circle, brand: _brand, filterType: ft, filterValue: fv);
      } else if (_tab == 'benchmark') {
        d = await ApiClient.reportNetworkBenchmark(circle: _circle, filterType: ft, filterValue: fv);
      } else if (_tab == 'insight') {
        d = await ApiClient.reportMarketInsight(circle: _circle, filterType: ft, filterValue: fv);
      } else if (_tab == 'ftth') {
        d = await ApiClient.reportFtth(circle: _circle, filterType: ft, filterValue: fv);
      } else {
        d = await ApiClient.reportProductDemand(circle: _circle, scope: _pdScope, brand: _brand);
      }
      if (!mounted) return;
      if (d['error'] != null) {
        setState(() => _error = d['error'].toString());
      } else {
        _cache[key] = d;
        setState(() => _assign(_tab, d));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── number helpers ──
  double _div() => ((_data?['display']?['divisor']) as num?)?.toDouble() ?? 1;
  String _unit() => (_data?['display']?['unit'] ?? _data?['metric']?['unit'] ?? '').toString();

  String _fmt(dynamic v, {int dec = 1}) {
    if (v == null) return '—';
    final n = (v as num).toDouble() / _div();
    return NumberFormat('#,##0.${'0' * dec}', 'id').format(n);
  }

  String _pct(dynamic v) {
    if (v == null) return '—';
    final n = (v as num).toDouble();
    final s = n >= 0 ? '+' : '';
    return '$s${NumberFormat('#,##0.0', 'id').format(n)}%';
  }

  String _var(dynamic v) {
    if (v == null) return '—';
    final n = (v as num).toDouble();
    return '${n >= 0 ? '▲' : '▼'} ${_fmt(n.abs())}';
  }

  @override
  Widget build(BuildContext context) {
    final t = _data?['totals'] as Map<String, dynamic>?;
    final up = (t?['trend'] ?? 'up') == 'up';
    return Scaffold(
      backgroundColor: context.vPanel,
      appBar: AppBar(
        title: const Text('Performance Outlook'),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: IOH.teal500))
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _load(force: true),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tabs(),
          if (_mode != 'snapshot') ...[
            const SizedBox(height: 10),
            _subTabs(),
          ],
          if (_mode == 'mycoord') ...[
            const SizedBox(height: 10),
            _myCoordHeader(),
          ],
          if (_mode != 'mycoord') ...[
            const SizedBox(height: 8),
            _filterBar(),
            if (_showFilters) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: context.vWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.vRule)),
                child: _controls(),
              ),
            ],
          ],
          _dataAsOfBar(),
          const SizedBox(height: 14),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: IOH.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(_error!, style: const TextStyle(color: IOH.danger, fontSize: 13)),
            ),
          if (_mode == 'mycoord' && _scopeValue.isEmpty) ...[
            _panel('My Coordinate', Text('Tekan “Gunakan Lokasi Saya”, lalu pilih level wilayah untuk menampilkan laporan.', style: TextStyle(color: context.vMute, fontSize: 12.5))),
          ] else if (_tab == 'snapshot' && _data != null) ...[
            _kpiTile(t!, up),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _chip('Best Branch', _data!['best'], good: true)),
              const SizedBox(width: 10),
              Expanded(child: _chip('Worst Branch', _data!['worst'], good: false)),
            ]),
            const SizedBox(height: 12),
            _panel(
                'Kecamatan Health · ${(_data!['slabs']?['kecamatan']?['total']) ?? 0} kecamatan',
                _slabBars(_data!['slabs']?['kecamatan'] as Map<String, dynamic>?)),
            const SizedBox(height: 12),
            ..._snapshotDeck(),
          ] else if (_tab == 'comprehensive' && _comp != null) ...[
            ..._comprehensiveSections(),
          ] else if (_tab == 'datarev' && _drev != null) ...[
            ..._dataRevSections(),
          ] else if (_tab == 'product' && _prod != null) ...[
             ..._productSections(),
          ] else if (_tab == 'benchmark' && _bench != null) ...[
             ..._benchmarkSections(),
           ] else if (_tab == 'insight' && _insight != null) ...[
              ..._insightSections(),
           ] else if (_tab == 'ftth' && _ftth != null) ...[
              ..._ftthSections(),
           ] else if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator(color: IOH.teal500)),
            ),
        ],
        )),
        if (_tab != 'ftth') _brandBar(),
      ]),
    );
  }

  Widget _myCoordHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.vWhite, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.vRule)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ElevatedButton.icon(
            onPressed: _loading ? null : _locateMe,
            style: ElevatedButton.styleFrom(backgroundColor: IOH.teal500, foregroundColor: Colors.white),
            icon: const Icon(Icons.my_location, size: 16),
            label: Text(_loading && _mcLevels == null ? 'Mencari…' : 'Gunakan Lokasi Saya'),
          ),
        ]),
        if (_geoErr.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_geoErr, style: const TextStyle(color: IOH.danger, fontSize: 12))),
        if (_mcLevels != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 6, runSpacing: 6, children: _mcLevels!.map((lv) {
            final active = _mcPick == lv['level'];
            return GestureDetector(
              onTap: () { setState(() { _mcPick = lv['level'].toString(); _scopeType = _mcPick; _scopeValue = (lv['value'] ?? lv['name']).toString(); }); _prefetchAll(); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: active ? IOH.teal500 : context.vWhite, borderRadius: BorderRadius.circular(999), border: Border.all(color: active ? IOH.teal500 : context.vRule)),
                child: Text('${lv['label']}: ${lv['name']}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: active ? Colors.white : context.vMute)),
              ),
            );
          }).toList()),
        ),
      ]),
    );
  }

  Widget _modeTab(String key, IconData ic, String label) {
    final active = _mode == key;
    return GestureDetector(
      onTap: () { if (_mode != key) { setState(() => _mode = key); _load(); } },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
        decoration: BoxDecoration(color: active ? IOH.teal500 : context.vWhite, borderRadius: BorderRadius.circular(10), border: Border.all(color: active ? IOH.teal500 : context.vRule)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 15, color: active ? Colors.white : context.vMute),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12, color: active ? Colors.white : context.vMute)),
        ]),
      ),
    );
  }

  Widget _tabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _modeTab('mycoord', Icons.my_location_outlined, 'My Coordinate'),
        _modeTab('territory', Icons.table_chart_outlined, 'Territory Wise'),
        _modeTab('snapshot', Icons.dashboard_outlined, 'Daily Snapshot'),
      ]),
    );
  }

  Widget _subTabs() {
    Widget chip(String key, String label) {
      final active = _subTab == key;
      return GestureDetector(
        onTap: () {
          if (_subTab != key) {
            // FTTH and IM3 use different territory level keys; reset scope when
            // crossing the FTTH boundary so a stale level is never sent.
            final crossing = (key == 'ftth') != (_subTab == 'ftth');
            setState(() {
              _subTab = key;
              if (crossing) { _scopeType = 'all'; _scopeValue = ''; _scopeOptions = []; }
            });
            _load();
          }
        },
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(color: active ? IOH.teal500 : context.vWhite, borderRadius: BorderRadius.circular(999), border: Border.all(color: active ? IOH.teal500 : context.vRule)),
          child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : context.vMute)),
        ),
      );
    }
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      chip('comprehensive', 'Comprehensive'), chip('ftth', 'Indosat HiFi (FTTH)'), chip('datarev', 'Data Revenue'), chip('product', 'Product Demand'), chip('benchmark', 'Network Benchmark'), chip('insight', 'Market Insight'),
    ]));
  }

  Widget _brandBar() {
    Widget seg(String key, String label) {
      final active = _brand == key;
      final col = _brandColors[key]!;
      final fg = active ? (key == 'im3' ? const Color(0xFF161616) : Colors.white) : context.vMute;
      return Expanded(child: GestureDetector(
        onTap: () { if (_brand != key) { setState(() => _brand = key); _load(); } },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: active ? col : context.vWhite, borderRadius: BorderRadius.circular(999), border: Border.all(color: active ? col : context.vRule)),
          child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: fg)),
        ),
      ));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: context.vWhite, border: Border(top: BorderSide(color: context.vRule)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))]),
      child: SafeArea(top: false, child: Row(children: [seg('ioh', 'IOH'), seg('im3', 'IM3'), seg('3id', '3ID')])),
    );
  }

  Future<void> _locateMe() async {
    setState(() { _loading = true; _geoErr = ''; _mcLevels = null; });
    final coord = await getCurrentCoord(context);
    if (coord == null) { if (mounted) setState(() => _loading = false); return; }
    try {
      final d = await ApiClient.reportLocate(lat: coord.$1, lon: coord.$2);
      if (!mounted) return;
      if (d['error'] != null) { setState(() { _geoErr = d['error'].toString(); _loading = false; }); }
      else {
        final lvls = ((d['levels'] as List?) ?? []).cast<Map<String, dynamic>>().where((x) => x['name'] != null).toList();
        setState(() {
          if (d['circle'] != null) _circle = d['circle'].toString();
          _mcLevels = lvls;
          if (lvls.isNotEmpty) { _mcPick = lvls.first['level'].toString(); _scopeType = _mcPick; _scopeValue = (lvls.first['value'] ?? lvls.first['name']).toString(); }
        });
        if (lvls.isNotEmpty) {
          // Load active tab data, then background-prefetch the rest
          await _prefetchAll();
        } else {
          if (mounted) setState(() => _loading = false);
        }
      }
    } catch (e) { if (mounted) setState(() { _geoErr = e.toString(); _loading = false; }); }
  }

  // Prefetch all 3 sub-reports for the current scope so tab switches are instant.
  Future<void> _prefetchAll() async {
    final ft = (_scopeType != 'all' && _scopeValue.isNotEmpty) ? _scopeType : 'all';
    final fv = (_scopeType != 'all') ? _scopeValue : '';
    // Fetch the active tab first (if it's not mycoord or snapshot)
    if (['comprehensive', 'datarev', 'product', 'benchmark', 'insight', 'ftth'].contains(_tab)) {
      setState(() { _loading = true; _error = null; });
      try {
        if (_tab == 'comprehensive') await _fetchAndCache('comp|$_dataVer|$_circle|$ft|$fv', () => ApiClient.reportComprehensive(circle: _circle, filterType: ft, filterValue: fv), 'comprehensive');
        else if (_tab == 'datarev') await _fetchAndCache('drev|$_dataVer|$_circle|$_brand|$ft|$fv', () => ApiClient.reportDataRevenue(circle: _circle, brand: _brand, filterType: ft, filterValue: fv), 'datarev');
        else if (_tab == 'product') await _fetchAndCache('prod|$_dataVer|$_circle|$_pdScope|$_brand', () => ApiClient.reportProductDemand(circle: _circle, scope: _pdScope, brand: _brand), 'product');
        else if (_tab == 'benchmark') await _fetchAndCache('bench|$_dataVer|$_circle|$ft|$fv', () => ApiClient.reportNetworkBenchmark(circle: _circle, filterType: ft, filterValue: fv), 'benchmark');
        else if (_tab == 'insight') await _fetchAndCache('ins|$_dataVer|$_circle|$ft|$fv', () => ApiClient.reportMarketInsight(circle: _circle, filterType: ft, filterValue: fv), 'insight');
        else if (_tab == 'ftth') await _fetchAndCache('ftth|$_dataVer|$_circle|$ft|$fv', () => ApiClient.reportFtth(circle: _circle, filterType: ft, filterValue: fv), 'ftth');
      } catch (_) {}
      if (mounted) setState(() => _loading = false);
    }
    
    // Background prefetch for others
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _fetchAndCache('comp|$_dataVer|$_circle|$ft|$fv', () => ApiClient.reportComprehensive(circle: _circle, filterType: ft, filterValue: fv), 'comprehensive');
      _fetchAndCache('drev|$_dataVer|$_circle|$_brand|$ft|$fv', () => ApiClient.reportDataRevenue(circle: _circle, brand: _brand, filterType: ft, filterValue: fv), 'datarev');
      _fetchAndCache('prod|$_dataVer|$_circle|$_pdScope|$_brand', () => ApiClient.reportProductDemand(circle: _circle, scope: _pdScope, brand: _brand), 'product');
      _fetchAndCache('bench|$_dataVer|$_circle|$ft|$fv', () => ApiClient.reportNetworkBenchmark(circle: _circle, filterType: ft, filterValue: fv), 'benchmark');
      _fetchAndCache('ins|$_dataVer|$_circle|$ft|$fv', () => ApiClient.reportMarketInsight(circle: _circle, filterType: ft, filterValue: fv), 'insight');
      _fetchAndCache('ftth|$_dataVer|$_circle|$ft|$fv', () => ApiClient.reportFtth(circle: _circle, filterType: ft, filterValue: fv), 'ftth');
    });
  }

  Future<void> _fetchAndCache(String key, Future<Map<String, dynamic>> Function() call, String tab) async {
    try {
      if (_cache.containsKey(key)) { _assign(tab, _cache[key]!); return; }
      final d = await call();
      if (d['error'] == null) { _cache[key] = d; _assign(tab, d); }
    } catch (_) {}
  }

  Widget _filterBar() {
    String scopeChip = '';
    if (_scopeType != 'all' && _scopeValue.isNotEmpty) scopeChip = _scopeValue;
    return GestureDetector(
      onTap: () => setState(() => _showFilters = !_showFilters),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: context.vWhite, borderRadius: BorderRadius.circular(10), border: Border.all(color: context.vRule)),
        child: Row(children: [
          Icon(Icons.tune, size: 16, color: IOH.teal600),
          const SizedBox(width: 8),
          Text('Filter', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12.5, color: context.vInk)),
          if (scopeChip.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: context.vPanel, borderRadius: BorderRadius.circular(999)),
              child: Text(scopeChip, style: TextStyle(fontSize: 10.5, color: context.vMute), overflow: TextOverflow.ellipsis),
            ),
          ],
          const Spacer(),
          Text('$_circle · ${_metricName()}', style: TextStyle(fontSize: 10.5, color: context.vMute), overflow: TextOverflow.ellipsis),
          const SizedBox(width: 6),
          Icon(_showFilters ? Icons.expand_less : Icons.expand_more, size: 18, color: context.vMute),
        ]),
      ),
    );
  }

  String _metricName() {
    for (final c in _categories) {
      for (final m in (c['metrics'] as List? ?? [])) {
        if (m['code'] == _metric) return m['name'].toString();
      }
    }
    return _metric;
  }

  String? _dataAsOf() {
    final d = _tab == 'snapshot' ? _data
        : _tab == 'comprehensive' ? _comp
        : _tab == 'datarev' ? _drev
        : _tab == 'benchmark' ? _bench
        : _tab == 'insight' ? _insight
        : _tab == 'ftth' ? _ftth
        : _prod;
    final s = d?['scope'] as Map<String, dynamic>?;
    final v = s?['data_as_of']?.toString();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  Widget _dataAsOfBar() {
    final v = _dataAsOf();
    if (v == null) return const SizedBox.shrink();
    final month = (((_tab == 'snapshot' ? _data : _tab == 'comprehensive' ? _comp : _tab == 'datarev' ? _drev : _tab == 'ftth' ? _ftth : _prod)?['scope'] as Map<String, dynamic>?)?['month_id'])?.toString();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Icon(Icons.update, size: 13, color: context.vMute),
        const SizedBox(width: 6),
        Text('Data as of $v${month != null ? "  ·  Month $month" : ""}',
            style: TextStyle(fontSize: 10.5, color: context.vMute, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  static const _brandColors = {'ioh': Color(0xFF15A697), 'im3': Color(0xFFF5A623), '3id': Color(0xFFEB008B)};

  Widget _controls() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_tab == 'snapshot') _dropMetric(),
        _drop('Circle', _circle, {'ALL': 'All Circles', for (final c in _circles) c: c}, (v) {
          setState(() => _circle = v);
          _loadScopeOptions();
          _load();
        }),
        if (_tab == 'snapshot' || _tab == 'comprehensive' || _tab == 'datarev')
          _drop('View', _scopeType, const {
            'all': 'Circle (all)', 'region': 'Region', 'area': 'Area', 'branch': 'Branch',
            'microcluster': 'Micro Cluster', 'kabkota': 'Kab/Kota', 'kecamatan': 'Kecamatan',
          }, (v) {
            setState(() { _scopeType = v; _scopeValue = ''; });
            _loadScopeOptions();
            if (v == 'all') _load();
          }),
        if (_tab == 'ftth')
          _drop('View', _scopeType, const {
            'all': 'Circle (all)', 'ftth_region': 'Region', 'ftth_province': 'Province',
            'ftth_kabkota': 'Kab/Kota', 'ftth_kecamatan': 'Kecamatan',
          }, (v) {
            setState(() { _scopeType = v; _scopeValue = ''; });
            _loadScopeOptions();
            if (v == 'all') _load();
          }),
        if ((_tab == 'snapshot' || _tab == 'comprehensive' || _tab == 'datarev' || _tab == 'ftth') && _scopeType != 'all')
          _wrapDrop(_scopeLabel(_scopeType), SizedBox(
            width: 168,
            height: 30,
            child: InkWell(
              onTap: _scopeOptions.isEmpty ? null : _openScopePicker,
              child: Row(children: [
                Expanded(child: Text(
                  _scopeValue.isEmpty ? '— pilih —' : _scopeValue,
                  style: TextStyle(fontSize: 12, color: _scopeValue.isEmpty ? context.vMute : context.vInk),
                  overflow: TextOverflow.ellipsis,
                )),
                Icon(Icons.search, size: 15, color: context.vMute),
              ]),
            ),
          )),
        if (_tab == 'product')
          _drop('Scope', _pdScope, const {'total': 'Total', 'organic': 'Organic', 'digital': 'Digital', 'trade': 'Trade'}, (v) {
            setState(() => _pdScope = v);
            _load();
          }),
      ],
    );
  }

  String _scopeLabel(String k) => const {
        'region': 'Region', 'area': 'Area', 'branch': 'Branch',
        'microcluster': 'Micro Cluster', 'kabkota': 'Kab/Kota', 'kecamatan': 'Kecamatan',
        'ftth_region': 'Region', 'ftth_province': 'Province',
        'ftth_kabkota': 'Kab/Kota', 'ftth_kecamatan': 'Kecamatan',
      }[k] ?? k;

  Widget _dropMetric() {
    final items = <DropdownMenuItem<String>>[];
    for (final c in _categories) {
      for (final m in (c['metrics'] as List? ?? [])) {
        items.add(DropdownMenuItem(value: m['code'].toString(), child: Text(m['name'].toString(), overflow: TextOverflow.ellipsis)));
      }
    }
    if (items.isEmpty) {
      items.add(const DropdownMenuItem(value: 'rev_prepaid', child: Text('Revenue Prepaid')));
    }
    return _wrapDrop('Metric', SizedBox(
      width: 178,
      height: 30,
      child: DropdownButton<String>(
        value: _metric,
        isExpanded: true,
        isDense: true,
        style: TextStyle(fontSize: 12, color: context.vInk),
        icon: Icon(Icons.arrow_drop_down, size: 18, color: context.vMute),
        underline: const SizedBox.shrink(),
        items: items,
        onChanged: (v) {
          if (v == null) return;
          setState(() => _metric = v);
          _load();
        },
      ),
    ));
  }

  Widget _drop(String label, String value, Map<String, String> opts, ValueChanged<String> onCh) {
    return _wrapDrop(label, SizedBox(
      height: 30,
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        style: TextStyle(fontSize: 12, color: context.vInk),
        icon: Icon(Icons.arrow_drop_down, size: 18, color: context.vMute),
        underline: const SizedBox.shrink(),
        items: opts.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
        onChanged: (v) { if (v != null) onCh(v); },
      ),
    ));
  }

  Widget _wrapDrop(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 8.5, fontWeight: FontWeight.w700, color: IOH.teal600, letterSpacing: 0.6)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: context.vWhite, borderRadius: BorderRadius.circular(9), border: Border.all(color: context.vRule)),
          child: child,
        ),
      ],
    );
  }

  // Searchable scope-value picker (typeable suggestions) used for region /
  // kabkota / kecamatan etc. so long lists don't require scrolling.
  void _openScopePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.vWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _ScopeSearchSheet(
        title: _scopeLabel(_scopeType),
        options: _scopeOptions,
        selected: _scopeValue,
        onPick: (v) {
          Navigator.pop(ctx);
          setState(() => _scopeValue = v);
          _load();
        },
      ),
    );
  }

  Widget _kpiTile(Map<String, dynamic> t, bool up) {
    final c = up ? IOH.teal600 : IOH.danger;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(16),
        border: const Border(top: BorderSide(color: IOH.teal500, width: 3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${(_data!['metric']?['name'] ?? '').toString().toUpperCase()} · MTD',
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w700, color: IOH.teal600, letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: _fmt(t['mtd']), style: TextStyle(fontFamily: 'Poppins', fontSize: 30, fontWeight: FontWeight.w800, color: context.vInk)),
                      TextSpan(text: '  ${_unit()}', style: TextStyle(fontSize: 13, color: context.vMute)),
                    ])),
                    const SizedBox(height: 4),
                    Text('IM3 ${_fmt(t['mtd_im3'])} · 3ID ${_fmt(t['mtd_3id'])}', style: TextStyle(fontSize: 12, color: context.vMute)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${up ? '▲' : '▼'} ${_pct(t['pct_change'])}',
                      style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: c)),
                  const SizedBox(height: 2),
                  Text('${_var(t['abs_change'])} vs LMTD', style: TextStyle(fontSize: 11.5, color: c)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, dynamic obj, {required bool good}) {
    final c = good ? IOH.teal600 : IOH.danger;
    final m = obj as Map<String, dynamic>?;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: c, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: IOH.teal600, letterSpacing: 0.6)),
          const SizedBox(height: 3),
          Text((m?['name'] ?? '—').toString(), style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14, color: context.vInk), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${_var(m?['var'])} · ${_pct(m?['pct'])}', style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }

  Widget _panel(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w700, color: IOH.teal600, letterSpacing: 0.6)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _slabBars(Map<String, dynamic>? s) {
    if (s == null) return const SizedBox.shrink();
    final buckets = [
      ['decline_gt5', '≤ -5%', const Color(0xFFB91C1C)],
      ['decline_3_5', '-5..-3%', const Color(0xFFDC2626)],
      ['decline_1_3', '-3..-1%', const Color(0xFFEF4444)],
      ['decline_0_1', '-1..0%', const Color(0xFFF87171)],
      ['growth_0_1', '0..1%', const Color(0xFF5EEAD4)],
      ['growth_1_3', '1..3%', const Color(0xFF2DD4BF)],
      ['growth_3_5', '3..5%', const Color(0xFF14B8A6)],
      ['growth_gt5', '≥ 5%', const Color(0xFF0E8579)],
    ];
    int maxv = 1;
    for (final b in buckets) {
      final v = (s[b[0]] as num?)?.toInt() ?? 0;
      if (v > maxv) maxv = v;
    }
    return Column(
      children: buckets.map((b) {
        final v = (s[b[0]] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(children: [
            SizedBox(width: 56, child: Text(b[1] as String, textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: context.vMute))),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 16,
                  color: context.vPanel,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: maxv == 0 ? 0 : v / maxv,
                    child: Container(color: b[2] as Color),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 26, child: Text('$v', style: TextStyle(fontSize: 11.5, color: context.vInk, fontFeatures: const [FontFeature.tabularFigures()]))),
          ]),
        );
      }).toList(),
    );
  }

  Widget _brandTable(dynamic rowsData) {
    final rows = (rowsData as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (rows.isEmpty) return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    const bands = [
      ['ioh', 'IOH', Color(0xFF15A697), Colors.white],
      ['im3', 'IM3', Color(0xFFF5A623), Color(0xFF161616)],
      ['3id', '3ID', Color(0xFFEB008B), Colors.white],
    ];
    const subs = ['LLMTD', 'LMTD', 'MTD', 'Var', '%'];
    const nameW = 116.0, headH1 = 28.0, headH2 = 24.0, rowH = 42.0;
    Color signColor(num? v) => (v ?? 0) >= 0 ? IOH.teal600 : IOH.danger;

    Widget cell(String text, {Color? color, bool bold = false, Color? bg, double w = 76}) =>
        Container(
          width: w, height: rowH, alignment: Alignment.centerRight, color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(text, style: TextStyle(fontSize: 11.5, color: color ?? context.vInk, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()])),
        );

    // Frozen Name column (header + body cells).
    final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: nameW, height: headH1, color: context.vWhite),
      Container(width: nameW, height: headH2, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.vMute))),
      for (var i = 0; i < rows.length; i++)
        Container(
          width: nameW, height: rowH,
          color: i.isOdd ? context.vZebra : context.vWhite,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((rows[i]['name'] ?? '').toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: context.vInk), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (rows[i]['parent'] != null) Text(rows[i]['parent'].toString(), style: TextStyle(fontSize: 9, color: context.vMute), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
    ]);

    // Scrollable data columns.
    final headRow1 = Row(children: [
      for (final b in bands)
        Container(width: 76 * 5, height: headH1, color: b[2] as Color, alignment: Alignment.center,
            child: Text(b[1] as String, style: TextStyle(color: b[3] as Color, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 12))),
    ]);
    final headRow2 = Row(children: [
      for (final b in bands)
        for (final s in subs)
          Container(width: 76, height: headH2, color: (b[2] as Color).withValues(alpha: 0.85), alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(s, style: TextStyle(color: b[3] as Color, fontSize: 10))),
    ]);
    final body = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final bg = i.isOdd ? context.vZebra : context.vWhite;
      final cells = <Widget>[];
      for (final b in bands) {
        final k = b[0] as String;
        final va = r['abs_growth_$k'] as num?;
        final pc = (k == 'ioh' ? r['growth_pct'] : r['growth_pct_$k']) as num?;
        cells.addAll([
          cell(_fmt(r['llmtd_$k']), bg: bg),
          cell(_fmt(r['lmtd_$k']), bg: bg),
          cell(_fmt(r['mtd_$k']), bold: true, bg: bg),
          cell(_var(va), color: signColor(va), bg: const Color(0xFFDAE5EE)),
          cell(_pct(pc), color: signColor(pc), bg: const Color(0xFFF2EAD2)),
        ]);
      }
      body.add(Row(children: cells));
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [headRow1, headRow2, ...body]),
        ),
      ),
    ]);
  }

  // ── Snapshot full deck (sub-tabbed to keep the view short) ──

  String _fmtBy(String kind, dynamic v) {
    if (v == null) return '—';
    final n = (v as num).toDouble();
    if (kind == 'mn') return _mn(n);
    if (kind == 'pct') return '${NumberFormat('#,##0.0', 'id').format(n)}%';
    return _num(n);
  }

  Widget _monthlyKVTable(List<Map<String, dynamic>> hist, List<List<String>> rowsDef) {
    const nameW = 140.0, headH = 28.0, rowH = 34.0, colW = 84.0;
    final months = hist.map((h) => h['month_id'].toString()).toList();
    final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: nameW, height: headH, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Metric', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
      for (var i = 0; i < rowsDef.length; i++)
        Container(width: nameW, height: rowH, color: i.isOdd ? context.vZebra : context.vWhite,
            padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.centerLeft,
            child: Text(rowsDef[i][1], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: context.vInk), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
    Widget cell(String t, {bool head = false}) => Container(width: colW, height: head ? headH : rowH, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t, style: TextStyle(fontSize: head ? 10 : 11, fontWeight: head ? FontWeight.w700 : FontWeight.w400, color: head ? context.vMute : context.vInk, fontFeatures: const [FontFeature.tabularFigures()])));
    final dataCols = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [for (final m in months) cell(m, head: true)]),
      for (var i = 0; i < rowsDef.length; i++)
        Container(color: i.isOdd ? context.vZebra : context.vWhite, child: Row(children: [
          for (final h in hist) cell(_fmtBy(rowsDef[i][2], h[rowsDef[i][0]])),
        ])),
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }
  List<Widget> _snapshotDeck() {
    final deck = _data!['deck'] as Map<String, dynamic>?;
    if (deck == null) return [];
    final counts = (deck['counts'] as Map<String, dynamic>?) ?? {};
    const sections = [
      ['circle', 'Circle'], ['region', 'Region'], ['branch', 'Branch'],
      ['microcluster', 'Micro Cluster'], ['kabkota', 'Kab/Kota'], ['kecamatan', 'Kecamatan'],
    ];
    const fullLevels = ['circle', 'region', 'branch'];

    // sub-tab selector
    final tabRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: sections.map((s) {
        final active = _deckTab == s[0];
        return GestureDetector(
          onTap: () => setState(() => _deckTab = s[0]),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            decoration: BoxDecoration(
              color: active ? IOH.teal500 : context.vWhite,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? IOH.teal500 : context.vRule),
            ),
            child: Text(s[1], style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : context.vMute)),
          ),
        );
      }).toList()),
    );

    Widget content;
    final cnt = counts[_deckTab] ?? 0;
    if (fullLevels.contains(_deckTab)) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Brand Breakdown · $cnt total', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: IOH.teal600)),
        const SizedBox(height: 8),
        _brandTable((deck[_deckTab] as Map<String, dynamic>?)?['rows']),
      ]);
    } else {
      final set = deck[_deckTab] as Map<String, dynamic>?;
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$cnt total', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: IOH.teal600)),
        const SizedBox(height: 8),
        Text('▼ Top 10 Decline', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: IOH.danger)),
        const SizedBox(height: 6),
        _brandTable(set?['decline']),
        const SizedBox(height: 16),
        Text('▲ Top 10 Growth', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w700, color: IOH.teal600)),
        const SizedBox(height: 6),
        _brandTable(set?['growth']),
      ]);
    }

    return [
      _panel('Territory Breakdown', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        tabRow,
        const SizedBox(height: 12),
        content,
      ])),
    ];
  }

  // ── Comprehensive ──
  List<double> _scaleFor(double peak, String unit) {
    if (unit == 'GB' && peak >= 100000) return [1000, 0]; // [divisor, unitMode]
    if (peak >= 100000000) return [1000000, 1];
    if (peak >= 100000) return [1000, 2];
    return [1, 3];
  }

  String _fmtScaled(dynamic v, double divisor) {
    if (v == null) return '—';
    final n = (v as num).toDouble() / divisor;
    return NumberFormat('#,##0.0', 'id').format(n);
  }

  List<Widget> _comprehensiveSections([Map<String, dynamic>? payload]) {
    final src = payload ?? _comp;
    final sections = (src?['sections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final out = <Widget>[];
    String? lastGroup;
    for (final s in sections) {
      final group = s['group'] as String?;
      if (group != null && group != lastGroup) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(group.toUpperCase(),
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, fontWeight: FontWeight.w800, color: context.vInk, letterSpacing: 0.6)),
        ));
      }
      lastGroup = group;
      final layout = s['layout'];
      if (layout == 'flat') {
        out.add(_panel('${s['title']}${s['month_used'] != null ? ' · ${s['month_used']}' : ''}', _flatTable(s)));
      } else if (layout == 'ftth_counts') {
        out.add(_panel(s['title'].toString(), _ftthCountTable(s)));
      } else if (layout == 'hierarchy') {
        out.add(_panel(s['title'].toString(), _ftthHierarchyTable(s)));
      } else {
        final cum = s['cumulative_yoy'] == true;
        out.add(_panel('${s['title']}${cum ? ' · YTD/YoY' : ''}', _compTable(s, cum)));
      }
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  Widget _flatTable(Map<String, dynamic> s) {
    final rows = (s['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final columns = (s['columns'] as List?)?.cast<String>() ?? ['Share %'];
    String fmtCell(dynamic v, int ci) {
      if (v == null) return '—';
      final n = (v as num).toDouble();
      return ci == 0 ? '${NumberFormat('#,##0.0', 'id').format(n)}%' : NumberFormat('#,##0', 'id').format(n);
    }
    Widget cell(String t, {bool header = false, bool bold = false, double w = 90}) => SizedBox(
        width: w, child: Text(t, textAlign: TextAlign.right,
          style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            color: header ? context.vMute : context.vInk, fontFeatures: const [FontFeature.tabularFigures()])));
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(width: 90, child: Text('Operator', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.vMute))),
        ...columns.map((c) => cell(c, header: true)),
      ]),
      ...rows.asMap().entries.map((e) {
        final r = e.value;
        final cells = (r['cells'] as List?) ?? [r['value']];
        final actor = (r['actor'] ?? '').toString();
        return Container(
          color: e.key.isOdd ? context.vZebra : context.vWhite,
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            SizedBox(width: 90, child: Text(actor, style: TextStyle(fontSize: 12, fontWeight: actor == 'IOH' || actor == 'Industry' ? FontWeight.w700 : FontWeight.w500, color: context.vInk))),
            ...columns.asMap().entries.map((ce) => cell(fmtCell(ce.key < cells.length ? cells[ce.key] : null, ce.key), bold: ce.key == 0)),
          ]),
        );
      }),
    ]));
  }

  Widget _compTable(Map<String, dynamic> s, bool cum) {
    final metrics = (s['metrics'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (metrics.isEmpty) return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    Color sign(num? v) => (v ?? 0) >= 0 ? IOH.teal600 : IOH.danger;
    // Single selected brand → full MoM + YoY set (compact).
    final subs = ['LLMTD', 'LMTD', 'MTD', 'Var', '%', 'LYTD', 'YTD', 'Var YoY', 'YoY%'];
    final bandBg = _brandColors[_brand]!;
    final bandFg = _brand == 'im3' ? const Color(0xFF161616) : Colors.white;
    const nameW = 138.0, headH = 30.0, rowH = 40.0;

    Widget c(String text, {Color? color, bool bold = false, Color? bg, double w = 70}) => Container(
          width: w, height: rowH, alignment: Alignment.centerRight, color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(text, style: TextStyle(fontSize: 11, color: color ?? context.vInk, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()])),
        );

    // Precompute per-metric scaling + unit label. Computed (ratio/%) metrics are
    // not scaled — shown as-is with their own unit.
    final scales = <List>[]; // [div, unitLbl]
    for (final m in metrics) {
      if (m['computed'] == true) {
        scales.add([1.0, (m['unit'] ?? '').toString()]);
        continue;
      }
      final b = m[_brand] as Map<String, dynamic>;
      final peak = [b['mtd'], b['lmtd'], b['llmtd']].map((x) => (x as num?)?.abs().toDouble() ?? 0).fold<double>(0, (a, v) => a > v ? a : v);
      final sc = _scaleFor(peak, (m['unit'] ?? '').toString());
      final um = sc[1].toInt();
      final unitLbl = um == 0 ? 'K GB' : um == 1 ? 'Mn ${m['unit']}' : um == 2 ? 'K ${m['unit']}' : '${m['unit']}';
      scales.add([sc[0], unitLbl]);
    }

    String fmtComp(dynamic v, String unit) {
      if (v == null) return '—';
      final n = (v as num).toDouble();
      if (unit == '%') return _pct(n);
      if (unit == 'ratio') return NumberFormat('#,##0.00', 'id').format(n);
      if (unit == 'GB') return NumberFormat('#,##0.0', 'id').format(n);
      return NumberFormat('#,##0', 'id').format(n); // Rp
    }
    String varComp(dynamic v, String unit) {
      if (v == null) return '—';
      final n = (v as num).toDouble();
      return '${n >= 0 ? '▲' : '▼'} ${fmtComp(n.abs(), unit)}';
    }

    // Frozen Metric column (header + body).
    final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: nameW, height: headH, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Metric', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.vMute))),
      for (var i = 0; i < metrics.length; i++)
        Container(
          width: nameW, height: rowH,
          color: i.isOdd ? context.vZebra : context.vWhite,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((metrics[i]['name'] ?? '').toString(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: context.vInk), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(scales[i][1] as String, style: TextStyle(fontSize: 8.5, color: context.vMute), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
    ]);

    // Scrollable data columns.
    Widget subHead(String t) => Container(width: 70, height: headH, color: bandBg, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t, style: TextStyle(color: bandFg, fontSize: 9.5, fontWeight: FontWeight.w600)));
    final head = Row(children: [for (final h in subs) subHead(h)]);
    final body = <Widget>[];
    for (var i = 0; i < metrics.length; i++) {
      final isComp = metrics[i]['computed'] == true;
      final b = metrics[i][_brand] as Map<String, dynamic>;
      final div = scales[i][0] as double;
      final unit = scales[i][1] as String;
      final bg = i.isOdd ? context.vZebra : context.vWhite;
      String fNum(dynamic v) => isComp ? fmtComp(v, unit) : _fmtScaled(v, div);
      String fVar(dynamic v) => isComp ? varComp(v, unit) : _var2(v, div);
      body.add(Row(children: [
        c(fNum(b['llmtd']), bg: bg),
        c(fNum(b['lmtd']), bg: bg),
        c(fNum(b['mtd']), bold: true, bg: bg),
        c(fVar(b['var_mom']), color: sign(b['var_mom'] as num?), bg: const Color(0xFFDAE5EE)),
        c(_pct(b['growth_mom_pct']), color: sign(b['growth_mom_pct'] as num?), bg: const Color(0xFFF2EAD2)),
        c(fNum(b['lytd']), bg: bg),
        c(fNum(b['ytd']), bold: true, bg: bg),
        c(fVar(b['var_yoy']), color: sign(b['var_yoy'] as num?), bg: const Color(0xFFDAE5EE)),
        c(_pct(b['growth_yoy_pct']), color: sign(b['growth_yoy_pct'] as num?), bg: const Color(0xFFF2EAD2)),
      ]));
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, ...body]),
        ),
      ),
    ]);
  }

  String _var2(dynamic v, double divisor) {
    if (v == null) return '—';
    final n = (v as num).toDouble() / divisor;
    return '${n >= 0 ? '▲' : '▼'} ${NumberFormat('#,##0.0', 'id').format(n.abs())}';
  }

  // ── Data Revenue ──
  String _mn(dynamic v) {
    if (v == null) return '—';
    final n = (v as num).toDouble();
    if (n.abs() >= 1e6) return '${NumberFormat('#,##0.0', 'id').format(n / 1e6)} Mn';
    return NumberFormat('#,##0', 'id').format(n);
  }

  String _num(dynamic v) => v == null ? '—' : NumberFormat('#,##0', 'id').format((v as num).toDouble());

  List<Widget> _dataRevSections() {
    final chunks = (_drev!['chunks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final slabs = (_drev!['price_slabs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final ratios = _drev!['ratios'] as Map<String, dynamic>?;
    final out = <Widget>[];

    // Ratios panel: channel mix + ATL/BTL
    if (ratios != null) {
      Widget chip(String text, Color bg, Color fg) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)));
      final cp = (ratios['channel_pct'] as Map<String, dynamic>?) ?? {};
      final avb = ratios['atl_vs_btl'];
      out.add(_panel('Ratios — Channel Mix & ATL/BTL', Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in cp.entries) chip('${e.key}: ${_pct(e.value)}', const Color(0xFFEAF6F4), IOH.teal600),
        chip('ATL: ${_pct(ratios['atl_pct'])}', context.vPanel, context.vInk),
        chip('BTL: ${_pct(ratios['btl_pct'])}', context.vPanel, context.vInk),
        chip('ATL/BTL: ${avb == null ? '—' : '${NumberFormat('#,##0.00', 'id').format((avb as num).toDouble())}×'}', const Color(0xFFFDF3E2), const Color(0xFF9A6B00)),
      ])));
      out.add(const SizedBox(height: 12));
    }

    for (final c in chunks) {
      out.add(_panel('${c['name']} (Mn IDR)', _drChunkTable(c)));
      out.add(const SizedBox(height: 12));
    }
    // price slabs — with channel scope tabs + channel-detail chips
    out.add(_panel('Price Slab Breakdown (Mn IDR)', _slabPanel(slabs)));
    return out;
  }

  Widget _slabPanel(List<Map<String, dynamic>> fallbackSlabs) {
    final scopes = (_drev!['price_slab_scopes'] as Map?)?.cast<String, dynamic>();
    if (scopes == null) return _slabTable(fallbackSlabs);
    const order = ['total', 'organic', 'digital', 'trade'];
    final avail = order.where((k) => scopes.containsKey(k)).toList();
    if (!avail.contains(_slabScope)) _slabScope = 'total';
    final cur = (scopes[_slabScope] as Map?)?.cast<String, dynamic>() ?? {};
    final details = (cur['details'] as Map?)?.cast<String, dynamic>() ?? {};
    final detailNames = details.keys.toList()..sort();
    final slabs = (_slabDetail.isNotEmpty && details.containsKey(_slabDetail))
        ? (details[_slabDetail] as List).cast<Map<String, dynamic>>()
        : (cur['slabs'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    Widget scopeTab(String k) {
      final active = _slabScope == k;
      final label = (scopes[k] as Map?)?['label']?.toString() ?? k;
      return GestureDetector(
        onTap: () => setState(() { _slabScope = k; _slabDetail = ''; }),
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(color: active ? IOH.teal500 : context.vWhite, borderRadius: BorderRadius.circular(999), border: Border.all(color: active ? IOH.teal500 : context.vRule)),
          child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : context.vMute)),
        ),
      );
    }

    Widget chip(String label, String val) {
      final active = _slabDetail == val;
      return GestureDetector(
        onTap: () => setState(() => _slabDetail = val),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: active ? IOH.teal500 : context.vWhite, borderRadius: BorderRadius.circular(999), border: Border.all(color: active ? IOH.teal500 : context.vRule)),
          child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: active ? Colors.white : context.vMute)),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: avail.map(scopeTab).toList())),
      if (detailNames.isNotEmpty) ...[
        const SizedBox(height: 8),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: chip('All ${(cur['label'] ?? '')}', '')),
          ...detailNames.map((dn) => Padding(padding: const EdgeInsets.only(right: 6), child: chip(dn, dn))),
        ])),
      ],
      const SizedBox(height: 10),
      _slabTable(slabs),
    ]);
  }

  // Price slab table — frozen Slab column + full timeframe data columns.
  Widget _slabTable(List<Map<String, dynamic>> slabs, {String nameLabel = 'Slab', double nameW = 120.0}) {
    Color sign(num? v) => (v ?? 0) >= 0 ? IOH.teal600 : IOH.danger;
    final bandBg = _brandColors[_brand]!;
    final bandFg = _brand == 'im3' ? const Color(0xFF161616) : Colors.white;
    const headH = 28.0, rowH = 36.0;
    final subs = ['LLMTD', 'LMTD', 'MTD', 'Var', '%', 'LYTD', 'YTD', 'Var YoY', 'YoY%', 'Hits'];
    double bv(Map<String, dynamic> r) => (r[_brand] as num?)?.toDouble() ?? 0;
    double sh(Map<String, dynamic> r) {
      final i = (r['ioh'] as num?)?.toDouble() ?? 0;
      return i == 0 ? 1 : bv(r) / i;
    }
    Widget cl(String t, {Color? color, bool bold = false, Color? bg, double w = 78}) => Container(
        width: w, height: rowH, alignment: Alignment.centerRight, color: bg, padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t, style: TextStyle(fontSize: 11, color: color ?? context.vInk, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()])));

    final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: nameW, height: headH, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(nameLabel, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.vMute))),
      for (var i = 0; i < slabs.length; i++)
        Container(width: nameW, height: rowH, color: i.isOdd ? context.vZebra : context.vWhite,
            padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.centerLeft,
            child: Text((slabs[i]['slab'] ?? '').toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: context.vInk), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);

    Widget subHead(String t) => Container(width: 78, height: headH, color: bandBg, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t, style: TextStyle(color: bandFg, fontSize: 9.5, fontWeight: FontWeight.w600)));
    final head = Row(children: [for (final s in subs) subHead(s)]);
    final body = <Widget>[];
    for (var i = 0; i < slabs.length; i++) {
      final s = slabs[i];
      final bg = i.isOdd ? context.vZebra : context.vWhite;
      final f = sh(s);
      final mtd = bv(s);
      final lmtd = ((s['lmtd'] as num?)?.toDouble() ?? 0) * f;
      final llmtd = ((s['llmtd'] as num?)?.toDouble() ?? 0) * f;
      final ytd = ((s['ytd'] as num?)?.toDouble() ?? 0) * f;
      final lytd = ((s['lytd'] as num?)?.toDouble() ?? 0) * f;
      final vM = mtd - lmtd, vY = ytd - lytd;
      body.add(Row(children: [
        cl(_mn(llmtd), bg: bg),
        cl(_mn(lmtd), bg: bg),
        cl(_mn(mtd), bold: true, bg: bg),
        cl('${vM >= 0 ? '▲' : '▼'} ${_mn(vM.abs())}', color: sign(vM), bg: const Color(0xFFDAE5EE)),
        cl(_pct(lmtd != 0 ? vM / lmtd * 100 : null), color: sign(vM), bg: const Color(0xFFF2EAD2)),
        cl(_mn(lytd), bg: bg),
        cl(_mn(ytd), bold: true, bg: bg),
        cl('${vY >= 0 ? '▲' : '▼'} ${_mn(vY.abs())}', color: sign(vY), bg: const Color(0xFFDAE5EE)),
        cl(_pct(lytd != 0 ? vY / lytd * 100 : null), color: sign(vY), bg: const Color(0xFFF2EAD2)),
        cl('${(s['hit'] as num?)?.toInt() ?? 0}', color: context.vMute, bg: bg),
      ]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, ...body]))),
    ]);
  }

  // Data Revenue chunk table — same visual as Comprehensive: frozen Channel
  // column + horizontally-scrollable brand-band data columns, with a TOTAL
  // headline row and expandable channel_detail rows.
  Widget _drChunkTable(Map<String, dynamic> c) {
    Color sign(num? v) => (v ?? 0) >= 0 ? IOH.teal600 : IOH.danger;
    final channels = (c['channels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final h = c['headline'] as Map<String, dynamic>;
    final bandBg = _brandColors[_brand]!;
    final bandFg = _brand == 'im3' ? const Color(0xFF161616) : Colors.white;
    const nameW = 150.0, headH = 28.0, rowH = 38.0;
    final subs = ['LLMTD', 'LMTD', 'MTD', 'Var', '%', 'LYTD', 'YTD', 'Var YoY', 'YoY%', 'Contrib%'];
    double bval(Map<String, dynamic> r) => (r[_brand] as num?)?.toDouble() ?? 0;
    // brand share to scale IOH-only timeframes (lmtd/llmtd/ytd/lytd) per brand
    double bshare(Map<String, dynamic> r) {
      final i = (r['ioh'] as num?)?.toDouble() ?? 0;
      return i == 0 ? 1 : bval(r) / i;
    }

    Widget c2(String text, {Color? color, bool bold = false, Color? bg, double w = 78}) => Container(
          width: w, height: rowH, alignment: Alignment.centerRight, color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(text, style: TextStyle(fontSize: 11, color: color ?? context.vInk, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()])),
        );

    // Build (label, indent, bg, map, isHeadline) rows in display order.
    final rowsData = <Map<String, dynamic>>[];
    rowsData.add({'label': 'TOTAL', 'indent': false, 'm': h, 'contrib': 100.0, 'tap': null, 'hl': true});
    for (var i = 0; i < channels.length; i++) {
      final ch = channels[i];
      final details = (ch['details'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final key = '${c['name']}|${ch['channel']}';
      final isOpen = _drExpanded.contains(key);
      rowsData.add({'label': '${details.isEmpty ? '' : (isOpen ? '▾ ' : '▸ ')}${ch['channel'] ?? ''}',
        'indent': false, 'm': ch, 'contrib': ch['contrib_pct'], 'tap': details.isEmpty ? null : key, 'hl': false, 'odd': i.isOdd});
      if (isOpen) {
        for (final dt in details) {
          rowsData.add({'label': (dt['detail'] ?? '').toString(), 'indent': true, 'm': dt, 'contrib': dt['contrib_pct'], 'tap': null, 'hl': false});
        }
      }
    }

    Color rowBg(int i, Map<String, dynamic> rd) {
      if (rd['hl'] == true) return context.vHeadline;
      if (rd['indent'] == true) return context.vSubtle;
      return (rd['odd'] == true) ? context.vZebra : context.vWhite;
    }

    // Frozen Channel column.
    final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: nameW, height: headH, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Channel', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.vMute))),
      for (var i = 0; i < rowsData.length; i++)
        GestureDetector(
          onTap: rowsData[i]['tap'] == null ? null : () {
            final k = rowsData[i]['tap'] as String;
            setState(() => _drExpanded.contains(k) ? _drExpanded.remove(k) : _drExpanded.add(k));
          },
          child: Container(
            width: nameW, height: rowH, color: rowBg(i, rowsData[i]),
            padding: EdgeInsets.only(left: rowsData[i]['indent'] == true ? 22 : 8, right: 8),
            alignment: Alignment.centerLeft,
            child: Text(rowsData[i]['label'] as String,
                style: TextStyle(fontSize: 11, fontWeight: rowsData[i]['hl'] == true ? FontWeight.w700 : (rowsData[i]['indent'] == true ? FontWeight.w400 : FontWeight.w600), color: rowsData[i]['indent'] == true ? context.vMute : context.vInk),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
    ]);

    // Scrollable data columns.
    Widget subHead(String t) => Container(width: 78, height: headH, color: bandBg, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t, style: TextStyle(color: bandFg, fontSize: 9.5, fontWeight: FontWeight.w600)));
    final head = Row(children: [for (final s in subs) subHead(s)]);
    String varTxt(double v) => '${v >= 0 ? '▲' : '▼'} ${_mn(v.abs())}';
    final body = <Widget>[];
    for (var i = 0; i < rowsData.length; i++) {
      final rd = rowsData[i];
      final m = rd['m'] as Map<String, dynamic>;
      final bg = rowBg(i, rd);
      final sh = bshare(m);
      final mtd = bval(m);
      final lmtd = ((m['lmtd'] as num?)?.toDouble() ?? 0) * sh;
      final llmtd = ((m['llmtd'] as num?)?.toDouble() ?? 0) * sh;
      final ytd = ((m['ytd'] as num?)?.toDouble() ?? 0) * sh;
      final lytd = ((m['lytd'] as num?)?.toDouble() ?? 0) * sh;
      final vMom = mtd - lmtd, vYoy = ytd - lytd;
      body.add(Row(children: [
        c2(_mn(llmtd), bg: bg),
        c2(_mn(lmtd), bg: bg),
        c2(_mn(mtd), bold: true, bg: bg),
        c2(varTxt(vMom), color: sign(vMom), bg: const Color(0xFFDAE5EE)),
        c2(_pct(lmtd != 0 ? vMom / lmtd * 100 : null), color: sign(vMom), bg: const Color(0xFFF2EAD2)),
        c2(_mn(lytd), bg: bg),
        c2(_mn(ytd), bold: true, bg: bg),
        c2(varTxt(vYoy), color: sign(vYoy), bg: const Color(0xFFDAE5EE)),
        c2(_pct(lytd != 0 ? vYoy / lytd * 100 : null), color: sign(vYoy), bg: const Color(0xFFF2EAD2)),
        c2(_pct(rd['contrib']), color: context.vMute, bg: bg),
      ]));
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, ...body]),
      )),
    ]);
  }

  // ── Product Demand ──
  static const _rankBg = [Color(0xFFED1C24), Color(0xFFEC008C), Color(0xFFFFCB05)];
  static const _rankFg = [Colors.white, Colors.white, Color(0xFF161616)];

  Widget _pill(String label, bool active, VoidCallback onTap, {bool small = false}) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: small ? EdgeInsets.zero : const EdgeInsets.only(right: 6),
          padding: EdgeInsets.symmetric(vertical: small ? 5 : 6, horizontal: small ? 10 : 12),
          decoration: BoxDecoration(color: active ? IOH.teal500 : context.vWhite, borderRadius: BorderRadius.circular(999), border: Border.all(color: active ? IOH.teal500 : context.vRule)),
          child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: small ? 10.5 : 12, fontWeight: FontWeight.w600, color: active ? Colors.white : context.vMute)),
        ),
      );

  Widget _pdSlabPanel(Map<String, dynamic> scopes) {
    const order = ['total', 'organic', 'digital', 'trade'];
    final avail = order.where((k) => scopes.containsKey(k)).toList();
    if (!avail.contains(_pdSlabScope)) _pdSlabScope = 'total';
    final cur = (scopes[_pdSlabScope] as Map?)?.cast<String, dynamic>() ?? {};
    final details = (cur['details'] as Map?)?.cast<String, dynamic>() ?? {};
    final detailNames = details.keys.toList()..sort();
    final dimSrc = (_pdSlabDetail.isNotEmpty && details.containsKey(_pdSlabDetail))
        ? (details[_pdSlabDetail] as Map).cast<String, dynamic>() : cur;
    final rows = ((_pdSlabDim == 'quota' ? dimSrc['quota'] : dimSrc['validity']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    final tops = (dimSrc['top_products'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // channel scope tabs
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: avail.map((k) =>
        _pill((scopes[k] as Map?)?['label']?.toString() ?? k, _pdSlabScope == k, () => setState(() { _pdSlabScope = k; _pdSlabDetail = ''; }))).toList())),
      // channel detail chips
      if (detailNames.isNotEmpty) ...[
        const SizedBox(height: 8),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: _pill('All ${(cur['label'] ?? '')}', _pdSlabDetail == '', () => setState(() => _pdSlabDetail = ''), small: true)),
          ...detailNames.map((dn) => Padding(padding: const EdgeInsets.only(right: 6), child: _pill(dn, _pdSlabDetail == dn, () => setState(() => _pdSlabDetail = dn), small: true))),
        ])),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: [
        _pill('Slab Kuota', _pdSlabDim == 'quota', () => setState(() => _pdSlabDim = 'quota'), small: true),
        _pill('Slab Masa Aktif', _pdSlabDim == 'validity', () => setState(() => _pdSlabDim = 'validity'), small: true),
      ]),
      const SizedBox(height: 10),
      _slabTable(rows),
      if (tops.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('TOP PRODUCTS · ${cur['label']}', style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w700, color: IOH.teal600, letterSpacing: 0.4)),
        const SizedBox(height: 8),
        _slabTable(tops.map((p) => {...p, 'slab': p['product']}).toList(), nameLabel: 'Product', nameW: 170),
      ],
    ]);
  }

  List<Widget> _productSections() {
    final qLabels = (_prod!['quota_labels'] as List?)?.cast<String>() ?? [];
    final vLabels = (_prod!['validity_labels'] as List?)?.cast<String>() ?? [];
    final rev = (_prod!['revenue_matrix'] as List?)?.map((r) => (r as List).map((x) => (x as num?)?.toDouble() ?? 0).toList()).toList() ?? [];
    final growth = (_prod!['growth_matrix'] as List?)?.map((r) => (r as List).map((x) => (x as num?)?.toDouble()).toList()).toList() ?? [];
    final top3 = (_prod!['top_3'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    double flatMax = 1;
    for (final r in rev) { for (final x in r) { if (x > flatMax) flatMax = x; } }
    double gMax = 1;
    for (final r in growth) { for (final x in r) { final a = (x ?? 0).abs(); if (a > gMax) gMax = a; } }

    int rankOf(String q, String v) => top3.indexWhere((t) => t['quota'] == q && t['validity'] == v);

    final out = <Widget>[];
    // Slab tables (Data-Revenue style) — channel scope tabs + quota/validity dim
    final ss = (_prod!['slab_scopes'] as Map?)?.cast<String, dynamic>();
    if (ss != null) {
      out.add(_panel('Slab Breakdown (Mn IDR)', _pdSlabPanel(ss)));
      out.add(const SizedBox(height: 12));
    }
    // legend
    out.add(_panel('Rank Legend', Wrap(spacing: 8, runSpacing: 8, children: top3.map((t) {
      final r = (t['rank'] as num).toInt();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: _rankBg[r - 1], borderRadius: BorderRadius.circular(8)),
        child: Text('#$r ${t['quota']} × ${t['validity']} · ${_mn(t['value'])} Mn', style: TextStyle(color: _rankFg[r - 1], fontSize: 11.5, fontWeight: FontWeight.w600)),
      );
    }).toList())));
    out.add(const SizedBox(height: 12));

    // revenue heatmap
    Widget heatCell(int ri, int ci) {
      final val = rev[ri][ci];
      final rank = rankOf(qLabels[ri], vLabels[ci]);
      final alpha = 0.1 + 0.8 * (val / flatMax);
      final bg = rank >= 0 ? _rankBg[rank] : Color.fromRGBO(21, 166, 151, alpha);
      final fg = rank >= 0 ? _rankFg[rank] : (alpha > 0.55 ? Colors.white : IOH.ink);
      return Container(
        width: 60, padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        alignment: Alignment.center, color: bg,
        child: Text(val > 0 ? _mn(val) : '—', style: TextStyle(fontSize: 10, color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
      );
    }
    out.add(_panel('Revenue Heatmap · Quota × Validity (Mn IDR)', SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [SizedBox(width: 72, child: Text('', style: TextStyle(color: context.vMute))), ...vLabels.map((v) => SizedBox(width: 60, child: Text(v, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: context.vMute))))]),
        ...qLabels.asMap().entries.map((e) => Row(children: [
          SizedBox(width: 72, child: Text(e.value, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.vInk))),
          ...vLabels.asMap().entries.map((c) => heatCell(e.key, c.key)),
        ])),
      ]),
    )));
    out.add(const SizedBox(height: 12));

    // growth heatmap
    Widget gCell(int ri, int ci) {
      final g = growth[ri][ci];
      Color bg = context.vWhite;
      if (g != null) {
        final a = (g.abs() / gMax).clamp(0.0, 1.0);
        bg = g >= 0 ? Color.fromRGBO(14, 133, 121, a) : Color.fromRGBO(185, 28, 28, a);
      }
      return Container(width: 56, padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4), alignment: Alignment.center, color: bg,
          child: Text(g == null ? '—' : _pct(g), style: const TextStyle(fontSize: 9.5)));
    }
    out.add(_panel('Growth MoM% Heatmap', SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [SizedBox(width: 72, child: Text('', style: TextStyle(color: context.vMute))), ...vLabels.map((v) => SizedBox(width: 56, child: Text(v, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: context.vMute))))]),
        ...qLabels.asMap().entries.map((e) => Row(children: [
          SizedBox(width: 72, child: Text(e.value, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.vInk))),
          ...vLabels.asMap().entries.map((c) => gCell(e.key, c.key)),
        ])),
      ]),
    )));
    return out;
  }

  // ── Network Benchmark ──
  List<Widget> _benchmarkSections() {
    final fb = (_bench!['fb_benchmark'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final av = (_bench!['availability'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final out = <Widget>[];

    if (fb.isNotEmpty) {
      out.add(_panel('Network Benchmark (FB) · 3 Bulan Terakhir', _fbBenchmarkTable(fb)));
      out.add(const SizedBox(height: 12));
    }
    if (av.isNotEmpty) {
      out.add(_panel('Network Availability · 3 Bulan Terakhir', _availTable(av)));
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  Widget _fbBenchmarkTable(List<Map<String, dynamic>> fb) {
    const ops = [
      ['im3', 'IM3', Color(0xFFF5A623)],
      ['tri', '3ID', Color(0xFFEB008B)],
      ['tsel', 'TSEL', Color(0xFF00549F)],
      ['xl', 'XL', Color(0xFF0058A3)],
      ['sf', 'SF', Color(0xFF7B2D8B)],
    ];
    final nameW = 64.0, colW = 52.0;
    final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: nameW, height: 28, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('Bulan', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
      Container(width: nameW, height: 22, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8)),
      ...fb.asMap().entries.map((e) => Container(width: nameW, height: 36, color: e.key.isOdd ? context.vZebra : context.vWhite, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(e.value['month_prefix'].toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.vInk)))),
    ]);

    Widget head(String t, Color bg, Color fg) => Container(width: colW, height: 28, color: bg, alignment: Alignment.center, child: Text(t, style: TextStyle(color: fg, fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 10)));
    Widget subH(String t, Color bg, Color fg) => Container(width: colW, height: 22, color: bg.withValues(alpha: 0.85), alignment: Alignment.center, child: Text(t, style: TextStyle(color: fg, fontSize: 9)));
    Widget cell(dynamic v, {bool bold = false, Color? bg}) => Container(width: colW, height: 36, color: bg, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(v == null ? '—' : NumberFormat('#,##0.0', 'id').format((v as num).toDouble()), style: TextStyle(fontSize: 10.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: context.vInk, fontFeatures: const [FontFeature.tabularFigures()])));

    final dataCols = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [for (final op in ops) head(op[1] as String, op[2] as Color, op[1] == 'IM3' ? const Color(0xFF161616) : Colors.white)]),
      Row(children: [for (final op in ops) ...[subH('DL', op[2] as Color, op[1] == 'IM3' ? const Color(0xFF161616) : Colors.white), subH('Lat', op[2] as Color, op[1] == 'IM3' ? const Color(0xFF161616) : Colors.white), subH('Sig', op[2] as Color, op[1] == 'IM3' ? const Color(0xFF161616) : Colors.white)]]),
      ...fb.asMap().entries.map((e) {
        final r = e.value;
        final bg = e.key.isOdd ? context.vZebra : context.vWhite;
        return Row(children: [
          for (final op in ops) ...[
            cell(r['dl_speed_${op[0]}_4g'], bg: bg),
            cell(r['latency_${op[0]}_4g'], bg: bg),
            cell(r['signal_${op[0]}_4g'], bg: bg),
          ],
        ]);
      }),
    ]);

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }

  Widget _availTable(List<Map<String, dynamic>> av) {
    final keys = ['mean_avg_avail_pct_2g', 'mean_avg_avail_pct_4g', 'mean_avg_avail_pct_5g', 'min_avail_pct_2g', 'min_avail_pct_4g', 'min_avail_pct_5g', 'sites_below_sla99_4g', 'sites_below_sla95_4g', 'total_down_day_events_4g', 'total_downtime_hrs_4g'];
    final labels = ['Avg Avail 2G%', 'Avg Avail 4G%', 'Avg Avail 5G%', 'Min 2G%', 'Min 4G%', 'Min 5G%', 'SLA 99%', 'SLA 95%', 'Down Events 4G', 'Downtime 4G (hrs)'];
    return _monthlyKVTable(av, [for (var i = 0; i < keys.length; i++) [keys[i], labels[i], 'num']]);
  }

  // ── Market Insight ──
  List<Widget> _insightSections() {
    final panels = (_insight!['panels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final out = <Widget>[];
    for (final p in panels) {
      out.add(_panel(p['title']?.toString() ?? '', _insightTable(p)));
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  // ── FTTH ──
  List<Widget> _ftthSections() {
    // FTTH uses the exact same data structure as Comprehensive
    return _comprehensiveSections(_ftth);
  }

  String _intFmt(dynamic v) {
    if (v == null) return '—';
    return NumberFormat('#,##0', 'id').format((v as num).toDouble());
  }

  Widget _ftthCountTable(Map<String, dynamic> s) {
    final rows = (s['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final columns = (s['columns'] as List?)?.cast<String>() ?? ['Count'];
    if (rows.isEmpty) return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    return Column(children: [
      Row(children: [
        Expanded(child: Text('Item', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.vMute))),
        ...columns.map((c) => SizedBox(width: 96, child: Text(c, textAlign: TextAlign.right, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.vMute)))),
      ]),
      const SizedBox(height: 4),
      ...rows.asMap().entries.map((e) {
        final r = e.value;
        final cells = (r['cells'] as List?) ?? [r['value']];
        return Container(
          color: e.key.isOdd ? context.vZebra : context.vWhite,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(child: Text((r['label'] ?? r['actor'] ?? '').toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.vInk))),
            ...columns.asMap().entries.map((ce) => SizedBox(
                width: 96,
                child: Text(_intFmt(ce.key < cells.length ? cells[ce.key] : null),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.vInk, fontFeatures: const [FontFeature.tabularFigures()])))),
          ]),
        );
      }),
    ]);
  }

  Widget _ftthHierarchyTable(Map<String, dynamic> s) {
    final rows = (s['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final columns = (s['columns'] as List?)?.cast<String>() ?? ['SO', 'SA', 'PA'];
    if (rows.isEmpty) return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Ketuk baris untuk drilldown · urut MTD', style: TextStyle(fontSize: 10, color: context.vMute)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: Text('SM / TL / AE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: context.vMute))),
        ...columns.map((c) => SizedBox(width: 56, child: Text(c, textAlign: TextAlign.right, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: IOH.teal600)))),
      ]),
      const SizedBox(height: 4),
      _FtthHierTree(nodes: rows, columns: columns),
    ]);
  }

  Widget _insightTable(Map<String, dynamic> p) {
    final actors = (p['actors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final months = (p['months'] as List?)?.cast<String>() ?? [];
    if (actors.isEmpty || months.isEmpty) return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    
    final kind = p['kind'].toString();
    final isPct = kind.startsWith('pct');
    final colW = 84.0;
    final nameW = 80.0;
    
    final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: nameW, height: 34, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Operator', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
      for (var i = 0; i < actors.length; i++)
        Container(width: nameW, height: 42, color: i.isOdd ? context.vZebra : context.vWhite,
            padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.centerLeft,
            child: Text(actors[i]['actor'].toString(), style: TextStyle(fontSize: 11, fontWeight: actors[i]['actor'] == 'Industry' ? FontWeight.w700 : FontWeight.w500, color: context.vInk))),
    ]);
    
    Widget head(String t) => Container(width: colW, height: 34, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute)));
    
    final dataCols = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [for (final m in months) head(m)]),
      for (var i = 0; i < actors.length; i++)
        Container(color: i.isOdd ? context.vZebra : context.vWhite, height: 42, child: Row(children: [
          for (final h in (actors[i]['history'] as List).cast<Map<String, dynamic>>()) 
            Container(
              width: colW, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), alignment: Alignment.centerRight,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(h['value'] == null ? '—' : (isPct ? _pct(h['value']) : NumberFormat('#,##0', 'id').format(h['value'])), style: TextStyle(fontSize: 11, fontWeight: actors[i]['actor'] == 'Industry' ? FontWeight.w700 : FontWeight.w500, color: context.vInk, fontFeatures: const [FontFeature.tabularFigures()])),
                if (h['growth'] != null) Text('${(h['growth'] as num) >= 0 ? '▲' : '▼'} ${NumberFormat('#,##0.0', 'id').format((h['growth'] as num).abs())}${isPct ? 'pp' : '%'}', style: TextStyle(fontSize: 9, color: (h['growth'] as num) >= 0 ? IOH.teal600 : IOH.danger)),
              ]),
            ),
        ])),
    ]);
    
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }
}

// Expandable SM -> TL -> AE drilldown tree for the FTTH report.
class _FtthHierTree extends StatefulWidget {
  final List<Map<String, dynamic>> nodes;
  final List<String> columns;
  const _FtthHierTree({required this.nodes, required this.columns});
  @override
  State<_FtthHierTree> createState() => _FtthHierTreeState();
}

class _FtthHierTreeState extends State<_FtthHierTree> {
  final Set<String> _open = {};

  String _intFmt(dynamic v) => v == null ? '—' : NumberFormat('#,##0', 'id').format((v as num).toDouble());

  List<Widget> _rows(List<Map<String, dynamic>> nodes, int depth, String prefix) {
    final out = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final key = '$prefix/$i';
      final kids = (n['children'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final hasKids = kids.isNotEmpty;
      final isOpen = _open.contains(key);
      final cells = (n['cells'] as List?) ?? [];
      final bg = depth == 0 ? context.vWhite : depth == 1 ? context.vZebra : context.vPanel;
      out.add(GestureDetector(
        onTap: hasKids ? () => setState(() { isOpen ? _open.remove(key) : _open.add(key); }) : null,
        child: Container(
          color: bg,
          padding: EdgeInsets.only(left: 4 + depth * 16, top: 7, bottom: 7),
          child: Row(children: [
            Expanded(child: Text(
              '${hasKids ? (isOpen ? '▾ ' : '▸ ') : depth > 0 ? '• ' : ''}${n['label'] ?? ''}',
              style: TextStyle(fontSize: 11.5, fontWeight: depth == 0 ? FontWeight.w700 : depth == 1 ? FontWeight.w600 : FontWeight.w400, color: context.vInk),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            )),
            ...List.generate(widget.columns.length, (ci) => SizedBox(
                width: 56,
                child: Text(_intFmt(ci < cells.length ? cells[ci] : null),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11.5, fontWeight: ci == widget.columns.length - 1 ? FontWeight.w700 : FontWeight.w500, color: context.vInk, fontFeatures: const [FontFeature.tabularFigures()])))),
          ]),
        ),
      ));
      if (isOpen && hasKids) out.addAll(_rows(kids, depth + 1, key));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: _rows(widget.nodes, 0, 'r'));
  }
}

// Bottom-sheet picker with a search field that filters a long option list.
class _ScopeSearchSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onPick;
  const _ScopeSearchSheet({required this.title, required this.options, required this.selected, required this.onPick});
  @override
  State<_ScopeSearchSheet> createState() => _ScopeSearchSheetState();
}

class _ScopeSearchSheetState extends State<_ScopeSearchSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options.where((o) => o.toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: context.vRule, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Text('Pilih ${widget.title}', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w700, color: context.vInk)),
                const Spacer(),
                Text('${filtered.length}', style: TextStyle(fontSize: 11, color: context.vMute)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                style: TextStyle(fontSize: 13, color: context.vInk),
                decoration: InputDecoration(
                  hintText: 'Ketik untuk mencari...',
                  hintStyle: TextStyle(fontSize: 13, color: context.vMute),
                  prefixIcon: Icon(Icons.search, size: 18, color: context.vMute),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.vRule)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.vRule)),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text('Tidak ada hasil', style: TextStyle(fontSize: 12, color: context.vMute)))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(height: 1, color: context.vRule),
                      itemBuilder: (_, i) {
                        final o = filtered[i];
                        final sel = o == widget.selected;
                        return ListTile(
                          dense: true,
                          title: Text(o, style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, color: sel ? IOH.teal600 : context.vInk)),
                          trailing: sel ? const Icon(Icons.check, size: 18, color: IOH.teal600) : null,
                          onTap: () => widget.onPick(o),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
