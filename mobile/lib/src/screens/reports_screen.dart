import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../format/report_format.dart';
import '../services/report_cache_service.dart';
import '../theme.dart';
import '../widgets/catalog_report.dart';
import '../widgets/performance_visuals.dart';
import '../widgets/report_ui.dart';
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
  String _deckTab =
      'circle'; // circle | region | branch | microcluster | kabkota | kecamatan
  // Payloads are read straight from the cache, keyed by the current scope.
  // Holding them in fields let a tab keep painting data from a scope the user
  // had already moved away from.
  Map<String, dynamic>? _payload(String tab) =>
      _cache.peek(_cacheKeyForTab(tab));
  Map<String, dynamic>? get _data => _payload('snapshot');
  Map<String, dynamic>? get _comp => _payload('comprehensive');
  Map<String, dynamic>? get _drev => _payload('datarev');
  Map<String, dynamic>? get _prod => _payload('product');
  Map<String, dynamic>? get _bench => _payload('benchmark');
  Map<String, dynamic>? get _fwa => _payload('fwa');
  Map<String, dynamic>? get _internal => _payload('internal');
  Map<String, dynamic>? get _insight => _payload('insight');
  Map<String, dynamic>? get _ftth => _payload('ftth');
  bool _loading = false;
  String? _error;
  int _requestEpoch = 0;
  String _dataVer = '';
  final ReportCacheService _cache = ReportCacheService.I;
  final Set<String> _expandedSections = {};
  bool _expandAllSections = false;
  final Set<String> _drExpanded = {}; // expanded data-revenue channels
  String _slabScope = 'total'; // total | organic | digital | trade
  String _slabDetail = ''; // selected channel_detail within scope
  String _pdSlabScope = 'total'; // product-demand slab scope tab
  String _pdSlabDetail = ''; // product-demand channel detail within scope
  String _pdSlabDim = 'quota'; // quota | validity
  final Map<String, String> _catalogQueries = {};
  final Map<String, String> _catalogCategories = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final m = await ApiClient.reportMetrics();
      final cats =
          (m['categories'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) setState(() => _categories = cats);
    } catch (_) {}
    try {
      _dataVer = await ApiClient.reportDataVersion();
      ReportCacheService.I.invalidateIfVersionChanged(_dataVer);
    } catch (_) {}
    // Load only the selected report. Unopened tabs must not incur scans.
    _loadActiveReport();
  }

  // Re-check the server data marker; if it changed, drop the cache so the next
  // load pulls fresh data.
  Future<void> _refreshDataVersion() async {
    final v = await ApiClient.reportDataVersion();
    if (v.isNotEmpty) {
      _dataVer = v;
      ReportCacheService.I.invalidateIfVersionChanged(v);
    }
  }

  Future<void> _loadScopeOptions({VoidCallback? onUpdated}) async {
    if (_scopeType == 'all') {
      setState(() {
        _scopeOptions = [];
        _scopeValue = '';
      });
      onUpdated?.call();
      return;
    }
    try {
      final vals = _tab == 'ftth'
          ? await ApiClient.reportFtthScopeOptions(
              circle: _circle, level: _scopeType)
          : await ApiClient.reportScopeOptions(
              circle: _circle, level: _scopeType);
      if (mounted) {
        setState(() => _scopeOptions = vals);
        onUpdated?.call();
      }
    } catch (_) {}
  }

  String _cacheKeyForTab(String tab) {
    final ft =
        (_scopeType != 'all' && _scopeValue.isNotEmpty) ? _scopeType : 'all';
    final fv = _scopeType != 'all' ? _scopeValue : '';
    if (tab == 'snapshot') {
      return 'snap|$_dataVer|$_circle|$_metric|$ft|$fv';
    }
    if (tab == 'comprehensive') {
      return 'comp|$_dataVer|$_circle|$ft|$fv';
    }
    if (tab == 'datarev') {
      return 'drev|$_dataVer|$_circle|$_brand|$ft|$fv';
    }
    if (tab == 'benchmark') {
      return 'bench|$_dataVer|$_circle|$ft|$fv';
    }
    if (tab == 'fwa') {
      return 'fwa|$_dataVer|$_circle|$ft|$fv';
    }
    if (tab == 'internal') {
      return 'internal|$_dataVer|$_circle|$ft|$fv';
    }
    if (tab == 'insight') return 'ins|$_dataVer|$_circle|$ft|$fv';
    if (tab == 'ftth') return 'ftth|$_dataVer|$_circle|$ft|$fv';
    return 'prod|$_dataVer|$_circle|$_pdScope|$_brand|$ft|$fv';
  }

  /// Builds the request for [tab] under the current scope.
  Future<Map<String, dynamic>> _requestFor(String tab) {
    final ft =
        (_scopeType != 'all' && _scopeValue.isNotEmpty) ? _scopeType : 'all';
    final fv = (_scopeType != 'all') ? _scopeValue : '';
    switch (tab) {
      case 'snapshot':
        return ApiClient.reportSnapshot(
            metric: _metric, circle: _circle, filterType: ft, filterValue: fv);
      case 'comprehensive':
        return ApiClient.reportComprehensive(
            circle: _circle, filterType: ft, filterValue: fv);
      case 'datarev':
        return ApiClient.reportDataRevenue(
            circle: _circle, brand: _brand, filterType: ft, filterValue: fv);
      case 'benchmark':
        return ApiClient.reportNetworkBenchmark(
            circle: _circle, filterType: ft, filterValue: fv);
      case 'fwa':
        return ApiClient.reportFwa(
            circle: _circle, brand: _brand, filterType: ft, filterValue: fv);
      case 'internal':
        return ApiClient.reportInternalPerformance(
            circle: _circle, brand: _brand, filterType: ft, filterValue: fv);
      case 'insight':
        return ApiClient.reportMarketInsight(
            circle: _circle, filterType: ft, filterValue: fv);
      case 'ftth':
        return ApiClient.reportFtth(
            circle: _circle, filterType: ft, filterValue: fv);
      default:
        return ApiClient.reportProductDemand(
            circle: _circle,
            scope: _pdScope,
            brand: _brand,
            filterType: ft,
            filterValue: fv);
    }
  }

  Future<void> _load({bool force = false}) async {
    // My Coordinate: wait until a located level is picked (scope set).
    if (_mode == 'mycoord' && _scopeValue.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    if (force) {
      _cache.clear();
      await _refreshDataVersion();
      // tell the server to rebuild fresh too
      try {
        await ApiClient.reportCacheClear();
      } catch (_) {}
    }
    final key = _cacheKeyForTab(_tab);
    final requestedTab = _tab;
    final requestEpoch = ++_requestEpoch;

    // Previously visited tabs paint immediately from their scoped cache.
    final cached = _cache.peek(key);
    if (cached != null) {
      setState(() {
        _error = null;
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Join an in-flight request for this scoped key rather than duplicating it.
      final d = await _cache.fetch(key, () => _requestFor(requestedTab));
      if (!mounted ||
          requestEpoch != _requestEpoch ||
          requestedTab != _tab ||
          key != _cacheKeyForTab(requestedTab)) {
        return;
      }
      if (d['error'] != null) {
        setState(() => _error = d['error'].toString());
      } else {
        setState(() {});
      }
    } catch (e) {
      if (mounted && requestEpoch == _requestEpoch) {
        setState(() => _error = e.toString());
      }
    }
    if (mounted && requestEpoch == _requestEpoch) {
      setState(() => _loading = false);
    }
  }

  // ── number helpers ──
  double _div() => ((_data?['display']?['divisor']) as num?)?.toDouble() ?? 1;
  String _unit() =>
      (_data?['display']?['unit'] ?? _data?['metric']?['unit'] ?? '')
          .toString();

  String _fmt(dynamic v, {int dec = 1}) =>
      reportNumber(v, decimals: dec, divisor: _div());

  String _pct(dynamic v) => reportPercent(v, signed: true);

  String _var(dynamic v) => reportVariance(v, divisor: _div());

  @override
  Widget build(BuildContext context) {
    final reportContent = _reportContent();
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final contextExtent = textScale >= 1.6
        ? 112.0
        : textScale >= 1.3
            ? 84.0
            : 64.0;
    return Scaffold(
      backgroundColor: context.vPanel,
      appBar: AppBar(
        title: const Text('Performance Outlook'),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: IOH.teal500))
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _loadActiveReport(force: true),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: RefreshIndicator(
            color: IOH.teal500,
            onRefresh: () => _loadActiveReport(force: true),
            child: CustomScrollView(
              key: PageStorageKey<String>('reports:$_mode:$_tab'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  sliver: SliverToBoxAdapter(child: _topControls()),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedContextDelegate(
                    extent: contextExtent,
                    child: _contextStrip(),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return RepaintBoundary(
                          key: ValueKey('$_tab:$index'),
                          child: reportContent[index],
                        );
                      },
                      childCount: reportContent.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_tab != 'ftth') _brandBar(),
      ]),
    );
  }

  Widget _topControls() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tabs(),
      if (_mode != 'snapshot') ...[
        const SizedBox(height: 6),
        _subTabs(),
      ],
      if (_mode == 'mycoord') ...[
        const SizedBox(height: 10),
        _myCoordHeader(),
      ],
    ]);
  }

  Widget _contextStrip() {
    final scope = _scopeValue.isNotEmpty ? _scopeValue : _circle;
    final asOf = _dataAsOf();
    final tabLabel = _tab == 'snapshot'
        ? 'Daily Snapshot'
        : {
              'comprehensive': 'Comprehensive',
              'datarev': 'Data Revenue',
              'product': 'Product Demand',
              'benchmark': 'Network Benchmark',
              'fwa': 'FWA Summary',
              'internal': 'Internal Net Performance',
              'insight': 'Market Insight',
              'ftth': 'Indosat HiFi',
            }[_tab] ??
            _tab;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ReportContextBar(
        semanticLabel:
            'Konteks laporan $tabLabel, wilayah $scope${asOf == null ? '' : ', data per $asOf'}',
        values: [
          ReportContextValue(
            label: 'View',
            value:
                '$tabLabel · ${_activeBrandLabel()}${asOf == null ? '' : ' · Data $asOf'}',
            icon: Icons.analytics_outlined,
          ),
          ReportContextValue(
            label: 'Scope',
            value: scope,
            icon: Icons.location_on_outlined,
          ),
        ],
        onTap: _mode == 'mycoord' ? null : _openFiltersSheet,
        actionLabel: _activeFilterCount() == 0
            ? 'Filter'
            : 'Filter ${_activeFilterCount()}',
      ),
    );
  }

  List<Widget> _reportContent() {
    final out = <Widget>[];
    if (_error != null) {
      out.add(Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: IOH.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline, color: IOH.danger),
          const SizedBox(width: 10),
          Expanded(
              child: Text(_error!,
                  style: const TextStyle(color: IOH.danger, fontSize: 13))),
          TextButton(onPressed: _load, child: const Text('Coba lagi')),
        ]),
      ));
      out.add(const SizedBox(height: 12));
    }
    if (_mode == 'mycoord' && _scopeValue.isEmpty) {
      out.add(_panel(
        'My Coordinate',
        Text(
          'Tekan "Gunakan Lokasi Saya", lalu pilih level wilayah untuk menampilkan laporan.',
          style: TextStyle(color: context.vMute, fontSize: 12.5),
        ),
      ));
      return out;
    }
    if (!_hasCurrentData && _loading) {
      out.addAll(List.generate(
          3,
          (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _loadingSkeleton(index == 0 ? 150 : 110),
              )));
      return out;
    }
    if (_tab == 'snapshot' && _data != null) {
      final totals = _data!['totals'] as Map<String, dynamic>? ?? {};
      final up = (totals['trend'] ?? 'up') == 'up';
      out.add(_kpiTile(totals, up));
      out.add(const SizedBox(height: 12));
      out.add(Row(children: [
        Expanded(child: _chip('Best Area', _data!['best'], good: true)),
        const SizedBox(width: 10),
        Expanded(child: _chip('Worst Area', _data!['worst'], good: false)),
      ]));
      out.add(const SizedBox(height: 12));
      final buckets = _snapshotBuckets(
        _data!['slabs']?['kecamatan'] as Map<String, dynamic>?,
      );
      out.add(SnapshotDistribution100(
        title: 'Kecamatan Health',
        subtitle:
            '${(_data!['slabs']?['kecamatan']?['total']) ?? 0} kecamatan, komposisi growth dan decline',
        buckets: buckets,
      ));
      out.add(const SizedBox(height: 12));
      out.add(_detailPanel(
        'Detail Bucket Kecamatan',
        SnapshotMirroredBuckets(
          title: 'Growth vs Decline',
          subtitle: 'Jumlah absolut pada skala yang sama',
          buckets: buckets,
          padding: EdgeInsets.zero,
        ),
        sectionKey: 'snapshot-buckets',
        meta: '8 bucket, count dan share',
      ));
      out.add(const SizedBox(height: 12));
      out.addAll(_snapshotDeck());
      return out;
    }
    if (_hasCurrentData) {
      out.add(_decisionCockpit());
      out.add(const SizedBox(height: 12));
      out.add(_sectionToolbar());
      out.add(const SizedBox(height: 12));
      if (_tab == 'comprehensive') {
        for (final note in (_comp?['notes'] as List?) ?? const []) {
          out.add(Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Catatan: $note',
                  style: TextStyle(fontSize: 11, color: context.vMute))));
        }
        out.addAll(_comprehensiveSections());
      }
      if (_tab == 'datarev') out.addAll(_dataRevSections());
      if (_tab == 'product') out.addAll(_productSections());
      if (_tab == 'benchmark') out.addAll(_benchmarkSections());
      if (_tab == 'fwa') {
        out.add(_catalogReport(_fwa!, includeAllBrands: false));
      }
      if (_tab == 'internal') {
        out.add(_catalogReport(_internal!, includeAllBrands: true));
      }
      if (_tab == 'insight') out.addAll(_insightSections());
      if (_tab == 'ftth') out.addAll(_ftthSections());
    }
    return out;
  }

  /// True when the current tab and scope already hold a cached payload, so the
  /// screen paints content rather than a skeleton.
  bool get _hasCurrentData => _cache.contains(_cacheKeyForTab(_tab));

  Widget _loadingSkeleton(double height) {
    return ExcludeSemantics(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: context.vWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.vRule),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 120, height: 12, color: context.vPanel),
          const SizedBox(height: 18),
          Container(width: double.infinity, height: 22, color: context.vPanel),
          const SizedBox(height: 10),
          Container(width: 180, height: 12, color: context.vPanel),
        ]),
      ),
    );
  }

  List<SnapshotBucketDatum> _snapshotBuckets(Map<String, dynamic>? slabs) {
    int? count(String key) => (slabs?[key] as num?)?.toInt();
    return [
      SnapshotBucketDatum(
          label: '> 5%',
          declineCount: count('decline_gt5'),
          growthCount: count('growth_gt5')),
      SnapshotBucketDatum(
          label: '3% to 5%',
          declineCount: count('decline_3_5'),
          growthCount: count('growth_3_5')),
      SnapshotBucketDatum(
          label: '1% to 3%',
          declineCount: count('decline_1_3'),
          growthCount: count('growth_1_3')),
      SnapshotBucketDatum(
          label: '0% to 1%',
          declineCount: count('decline_0_1'),
          growthCount: count('growth_0_1')),
    ];
  }

  Widget _decisionCockpit() {
    final metrics = _summaryMetrics();
    final scope = _scopeValue.isNotEmpty ? _scopeValue : _circle;
    return Semantics(
      container: true,
      label:
          'Ringkasan keputusan untuk $scope, ${metrics.length} indikator utama',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              IOH.teal600,
              Color.lerp(IOH.teal600, const Color(0xFF073B4C), 0.72)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: IOH.teal600.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PERFORMANCE COCKPIT',
                      style: TextStyle(
                        color: Color(0xFFBFEDE8),
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      scope,
                      softWrap: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _activeBrandLabel(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          if (metrics.isEmpty)
            const Text(
                'Ringkasan belum tersedia. Detail lengkap tetap ada di bawah.',
                style: TextStyle(color: Colors.white70))
          else
            LayoutBuilder(builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final oneColumn = scale >= 1.6 || constraints.maxWidth < 310;
              final gap = 8.0;
              final cardWidth = oneColumn
                  ? constraints.maxWidth
                  : (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: metrics
                    .map((metric) => SizedBox(
                          width: cardWidth,
                          child: _summaryMetricCard(metric),
                        ))
                    .toList(),
              );
            }),
        ]),
      ),
    );
  }

  Widget _summaryMetricCard(_SummaryMetric metric) {
    final delta = metric.delta;
    final favorable = delta == null ? null : _isFavorable(metric.code, delta);
    final deltaColor = favorable == null
        ? Colors.white70
        : favorable
            ? const Color(0xFF8FF3C7)
            : const Color(0xFFFFB4B4);
    final deltaLabel = delta == null
        ? 'Perubahan N/A'
        : reportGrowth(delta, suffix: metric.deltaUnit);
    return Semantics(
      label: '${metric.label}, ${metric.value}, $deltaLabel',
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            metric.label,
            softWrap: true,
            style: const TextStyle(color: Color(0xFFD8F5F1), fontSize: 10.5),
          ),
          const SizedBox(height: 4),
          Text(
            metric.value,
            softWrap: true,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(deltaLabel,
              style: TextStyle(
                  color: deltaColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  /// Picks one actor out of a Market Insight panel, preferring [wanted].
  ///
  /// Falls back to any non-Industry actor so the card never silently shows
  /// industry totals under a brand label.
  Map<String, dynamic>? _insightActor(
      List<Map<String, dynamic>> actors, String wanted) {
    for (final candidate in actors) {
      if (candidate['actor']?.toString().toUpperCase() == wanted) {
        return candidate;
      }
    }
    for (final candidate in actors) {
      if (candidate['actor']?.toString().toUpperCase() != 'INDUSTRY') {
        return candidate;
      }
    }
    return actors.isEmpty ? null : actors.first;
  }

  /// The IOH row of the FB Market Share flat section, as a cockpit card.
  ///
  /// Market share is the headline competitive number, so it replaces net add
  /// on the Comprehensive cockpit. The MoM move comes from the Market Insight
  /// tab when that payload is already warm; Comprehensive itself only carries
  /// a single closed month.
  _SummaryMetric? _fbMarketShareMetric(List<Map<String, dynamic>> sections) {
    for (final section in sections) {
      if (section['layout'] != 'flat') continue;
      if (!(section['title']
              ?.toString()
              .toLowerCase()
              .contains('market share') ??
          false)) {
        continue;
      }
      final rows =
          (section['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final row in rows) {
        if (row['actor']?.toString().toUpperCase() != 'IOH') continue;
        final cells = (row['cells'] as List?) ?? [row['value']];
        if (cells.isEmpty) return null;
        return _SummaryMetric(
          code: 'fb_ms',
          label: 'FB MS (IOH)',
          value: reportPercent(cells.first, decimals: 2),
          delta: _insightIohGrowth('pct_ms'),
          deltaUnit: 'pp',
        );
      }
    }
    return null;
  }

  /// Latest MoM move for an IOH insight panel, or null when that tab is cold.
  double? _insightIohGrowth(String kind) {
    final panels =
        (_insight?['panels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final panel in panels) {
      if (panel['kind']?.toString() != kind) continue;
      final actors =
          (panel['actors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final actor = _insightActor(actors, 'IOH');
      final history =
          (actor?['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (history.isEmpty) return null;
      return (history.first['growth'] as num?)?.toDouble();
    }
    return null;
  }

  List<_SummaryMetric> _summaryMetrics() {
    if (_tab == 'comprehensive' || _tab == 'ftth') {
      final payload = _tab == 'ftth' ? _ftth : _comp;
      final sections =
          (payload?['sections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final all = <Map<String, dynamic>>[];
      for (final section in sections) {
        all.addAll(
            (section['metrics'] as List?)?.cast<Map<String, dynamic>>() ?? []);
      }
      // Comprehensive shows FB Market Share as its fourth card, so it needs
      // only three catalog metrics. FTTH has no market share and keeps four.
      final marketShare =
          _tab == 'ftth' ? null : _fbMarketShareMetric(sections);
      final slots = marketShare == null ? 4 : 3;
      final preferred = _tab == 'ftth'
          ? ['ftth_hp', 'ftth_pa_cum', 'ftth_tur', 'ftth_netadd']
          : ['rev_prepaid', 'ga_total', 'rgu_90d'];
      final byCode = {
        for (final metric in all) metric['code'].toString(): metric
      };
      final chosen = <Map<String, dynamic>>[];
      for (final code in preferred) {
        if (byCode[code] != null) chosen.add(byCode[code]!);
      }
      if (chosen.length < slots) {
        for (final metric in all) {
          if (chosen.length >= slots) break;
          if (!chosen.contains(metric)) chosen.add(metric);
        }
      }
      final cards = chosen.map((metric) {
        final brand = _tab == 'ftth' ? 'ioh' : _brand;
        final values = (metric[brand] as Map?)?.cast<String, dynamic>() ?? {};
        final unit = (metric['unit'] ?? '').toString();
        return _SummaryMetric(
          code: metric['code'].toString(),
          label: metric['name']?.toString() ?? metric['code'].toString(),
          value: _summaryNumber(values['mtd'], unit),
          delta: (values['growth_mom_pct'] as num?)?.toDouble(),
        );
      }).toList();
      if (marketShare != null) cards.add(marketShare);
      return cards;
    }
    if (_tab == 'datarev') {
      final chunks =
          (_drev?['chunks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final result = <_SummaryMetric>[];
      for (final chunk in chunks.take(3)) {
        final h = (chunk['headline'] as Map?)?.cast<String, dynamic>() ?? {};
        result.add(_SummaryMetric(
          code: 'revenue',
          label: chunk['name']?.toString() ?? 'Revenue',
          value: '${_mn(h[_brand])} IDR',
          delta: (h['growth_mom_pct'] as num?)?.toDouble(),
        ));
      }
      final ratio = (_drev?['ratios'] as Map?)?.cast<String, dynamic>() ?? {};
      result.add(_SummaryMetric(
        code: 'contribution',
        label: 'ATL Contribution',
        value: _summaryNumber(ratio['atl_pct'], '%'),
        delta: null,
      ));
      return result;
    }
    if (_tab == 'product') {
      final top =
          (_prod?['top_3'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      return top
          .take(4)
          .map((item) => _SummaryMetric(
                code: 'product',
                label:
                    '#${item['rank'] ?? ''} ${item['quota'] ?? ''} x ${item['validity'] ?? ''}',
                value: '${_mn(item['value'])} IDR',
                delta: null,
              ))
          .toList();
    }
    if (_tab == 'fwa') {
      return _catalogSummaryMetrics(
        _fwa,
        preferred: const [
          'fwa_rev_total_v2',
          'fwa_rgu90',
          'ga_fwa_all',
          'fwa_arpu_total',
        ],
      );
    }
    if (_tab == 'internal') {
      return _catalogSummaryMetrics(_internal);
    }
    if (_tab == 'benchmark') {
      final catalog = CatalogReportData.fromPayload(_bench);
      if (catalog.hasMetrics) return _catalogSummaryMetrics(_bench);
      final fb =
          (_bench?['fb_benchmark'] as List?)?.cast<Map<String, dynamic>>() ??
              [];
      final av =
          (_bench?['availability'] as List?)?.cast<Map<String, dynamic>>() ??
              [];
      final latestFb = fb.isEmpty ? <String, dynamic>{} : fb.first;
      final latestAv = av.isEmpty ? <String, dynamic>{} : av.first;
      return [
        _SummaryMetric(
            code: 'download',
            label: 'IM3 Download 4G',
            value: _summaryNumber(latestFb['dl_speed_im3_4g'], 'Mbps'),
            delta: null),
        _SummaryMetric(
            code: 'latency',
            label: 'IM3 Latency 4G',
            value: _summaryNumber(latestFb['latency_im3_4g'], 'ms'),
            delta: null),
        _SummaryMetric(
            code: 'signal',
            label: 'IM3 Signal 4G',
            value: _summaryNumber(latestFb['signal_im3_4g'], 'dBm'),
            delta: null),
        _SummaryMetric(
            code: 'availability',
            label: 'Average Availability 4G',
            value: _summaryNumber(latestAv['mean_avg_avail_pct_4g'], '%'),
            delta: null),
      ];
    }
    if (_tab == 'insight') {
      final panels =
          (_insight?['panels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final result = <_SummaryMetric>[];
      for (final panel in panels.take(4)) {
        final actors =
            (panel['actors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final actor = _insightActor(actors, 'IOH');
        final history =
            (actor?['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        // `months` and every `history` arrive newest first, so the current
        // month is the first entry, not the last.
        final latest = history.isEmpty ? <String, dynamic>{} : history.first;
        final isPct = panel['kind']?.toString().startsWith('pct') == true;
        result.add(_SummaryMetric(
          code: panel['kind']?.toString() ?? 'insight',
          label: '${panel['title'] ?? 'Insight'} (${actor?['actor'] ?? 'N/A'})',
          value: _summaryNumber(latest['value'], isPct ? '%' : ''),
          delta: (latest['growth'] as num?)?.toDouble(),
          deltaUnit: isPct ? 'pp' : '%',
        ));
      }
      return result;
    }
    return const [];
  }

  List<_SummaryMetric> _catalogSummaryMetrics(
    Map<String, dynamic>? payload, {
    List<String> preferred = const [],
  }) {
    final catalog = CatalogReportData.fromPayload(payload);
    final available =
        catalog.metrics.where((metric) => !metric.isHeader).toList();
    String? primaryColumn() {
      for (final column in catalog.columns) {
        if (column.toUpperCase() == 'MTD') return column;
      }
      final periods = catalog.columns
          .where((column) => RegExp(r'^\d{4}[-/]?\d{2}').hasMatch(column))
          .toList();
      if (periods.isNotEmpty) return periods.last;
      for (final column in catalog.columns.reversed) {
        final lower = column.toLowerCase();
        if (!lower.startsWith('rank ') &&
            !lower.contains('growth') &&
            !lower.contains('delta') &&
            !lower.contains('var')) {
          return column;
        }
      }
      return catalog.columns.isEmpty ? null : catalog.columns.last;
    }

    final primary = primaryColumn();
    final chosen = <CatalogReportMetric>[];
    for (final id in preferred) {
      for (final metric in available) {
        if (metric.id == id && !chosen.contains(metric)) chosen.add(metric);
      }
    }
    if (primary != null) {
      for (final metric in available) {
        if (chosen.length >= 4) break;
        if (!chosen.contains(metric) &&
            metric.valueFor(_brand.toUpperCase(), primary) != null) {
          chosen.add(metric);
        }
      }
    }
    for (final metric in available) {
      if (chosen.length >= 4) break;
      if (!chosen.contains(metric)) chosen.add(metric);
    }
    return chosen.map((metric) {
      final raw = primary == null
          ? null
          : metric.valueFor(_brand.toUpperCase(), primary);
      final formatted = metric.formatValue(raw, column: primary);
      final unit = metric.unit.trim();
      final value = raw == null ||
              unit.isEmpty ||
              formatted.endsWith('%') ||
              formatted.toLowerCase().endsWith(unit.toLowerCase())
          ? formatted
          : '$formatted $unit';
      dynamic deltaRaw;
      for (final column in catalog.columns) {
        if (column.toUpperCase() == 'VAR_PCT' ||
            column.toUpperCase().startsWith('GROWTH VS')) {
          deltaRaw = metric.valueFor(_brand.toUpperCase(), column);
          break;
        }
      }
      return _SummaryMetric(
        code: metric.id,
        label: metric.label,
        value: value,
        delta: (deltaRaw as num?)?.toDouble(),
      );
    }).toList();
  }

  /// Cockpit headline number. Percent stays a percent, everything else picks
  /// its own magnitude tier so revenue reads Mn or Bn as the value warrants.
  String _summaryNumber(dynamic value, String unit) {
    if (unit == '%') return reportPercent(value);
    return reportMagnitude(value, unit: unit, decimals: 1);
  }

  String _activeBrandLabel() {
    if (_tab == 'ftth') return 'FTTH';
    if (_tab == 'benchmark') {
      final catalog = CatalogReportData.fromPayload(_bench);
      if (catalog.hasMetrics) return 'ALL OPERATORS';
    }
    if (_tab == 'internal') {
      final catalog = CatalogReportData.fromPayload(_internal);
      final selected = _brand.toUpperCase();
      if (catalog.brands.any((brand) => brand.toUpperCase() == selected)) {
        return selected;
      }
      if (catalog.brands.isNotEmpty) return catalog.brands.join('/');
    }
    return _brand.toUpperCase();
  }

  /// Null means the metric carries no judgement, so the card shows a muted
  /// delta instead of green or red. Polarity itself lives in report_format so
  /// every screen agrees on what counts as an improvement.
  bool? _isFavorable(String code, double delta) {
    switch (reportPolarityFor(code)) {
      case ReportPolarity.neutral:
        return null;
      case ReportPolarity.lowerIsBetter:
        return delta <= 0;
      case ReportPolarity.higherIsBetter:
        return delta >= 0;
    }
  }

  Widget _sectionToolbar() {
    final titles = _sectionTitles();
    String? active;
    for (final title in titles) {
      if (_expandedSections.contains('$_tab|$title')) {
        active = title;
        break;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'DATA LENGKAP',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: IOH.teal600,
              letterSpacing: 0.7,
            ),
          ),
          Text(
            '${titles.length} bagian, seluruh konten tetap tersedia',
            style: TextStyle(fontSize: 10.5, color: context.vMute),
          ),
        ]),
      ),
      ReportChapterNavigator(
        chapters: [
          for (final title in titles)
            ReportChapterLink(id: title, label: title),
        ],
        activeId: _expandAllSections ? null : active,
        onSelected: (title) => setState(() {
          final key = '$_tab|$title';
          if (_expandedSections.contains(key)) {
            _expandedSections.remove(key);
          } else {
            _expandedSections.add(key);
          }
        }),
        onExpandAll: () => setState(() => _expandAllSections = true),
        onCollapseAll: () => setState(() {
          _expandAllSections = false;
          _expandedSections.clear();
        }),
      ),
    ]);
  }

  List<String> _sectionTitles() {
    if (_tab == 'comprehensive' || _tab == 'ftth') {
      final payload = _tab == 'ftth' ? _ftth : _comp;
      return ((payload?['sections'] as List?) ?? [])
          .map((item) => (item as Map)['title'].toString())
          .toList();
    }
    if (_tab == 'datarev') {
      final chunks = (_drev?['chunks'] as List?) ?? [];
      return [
        'Ratios',
        ...chunks.map((item) => (item as Map)['name'].toString()),
        'Price Slab Breakdown',
      ];
    }
    if (_tab == 'product') {
      return const [
        'Slab Breakdown',
        'Top 3 Products',
        'Revenue Heatmap',
        'Growth Heatmap'
      ];
    }
    if (_tab == 'benchmark') {
      final catalog = CatalogReportData.fromPayload(_bench);
      if (catalog.hasMetrics) {
        return catalog.sections.map((section) => section.title).toList();
      }
      return const ['Network Benchmark', 'Network Availability'];
    }
    if (_tab == 'fwa' || _tab == 'internal') {
      final catalog = CatalogReportData.fromPayload(
        _tab == 'fwa' ? _fwa : _internal,
      );
      return catalog.sections.map((section) => section.title).toList();
    }
    if (_tab == 'insight') {
      return ((_insight?['panels'] as List?) ?? [])
          .map((item) => (item as Map)['title'].toString())
          .toList();
    }
    return const [];
  }

  Widget _catalogReport(
    Map<String, dynamic> payload, {
    required bool includeAllBrands,
  }) {
    final catalog = CatalogReportData.fromPayload(payload);
    final storedCategory = _catalogCategories[_tab] ?? '';
    final activeCategory =
        catalog.categories.contains(storedCategory) ? storedCategory : '';
    return CatalogReportView(
      key: ValueKey('catalog:$_tab'),
      data: catalog,
      reportKey: _tab,
      selectedBrand: _brand.toUpperCase(),
      includeAllBrands: includeAllBrands,
      query: _catalogQueries[_tab] ?? '',
      category: activeCategory,
      onQueryChanged: (value) => setState(() {
        _catalogQueries[_tab] = value;
      }),
      onCategoryChanged: (value) => setState(() {
        _catalogCategories[_tab] = value;
      }),
      expandedSections: _expandedSections,
      expandAll: _expandAllSections,
      onExpansionChanged: (title, expanded) => setState(() {
        final key = '$_tab|$title';
        if (expanded) {
          _expandedSections.add(key);
        } else {
          _expandedSections.remove(key);
          if (_expandAllSections) _expandAllSections = false;
        }
      }),
    );
  }

  Widget _detailPanel(String title, Widget child,
      {String? sectionKey, String? meta}) {
    final key = '$_tab|${sectionKey ?? title}';
    final expanded = _expandAllSections || _expandedSections.contains(key);
    return ReportChapter(
      key: ValueKey(key),
      title: title,
      summary: meta ?? 'Buka untuk melihat data lengkap',
      badge: meta,
      expanded: expanded,
      onExpansionChanged: (next) => setState(() {
        if (next) {
          _expandedSections.add(key);
        } else {
          _expandedSections.remove(key);
          if (_expandAllSections) _expandAllSections = false;
        }
      }),
      child: child,
    );
  }

  Widget _myCoordHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: context.vWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.vRule)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ElevatedButton.icon(
            onPressed: _loading ? null : _locateMe,
            style: ElevatedButton.styleFrom(
                backgroundColor: IOH.teal500, foregroundColor: Colors.white),
            icon: const Icon(Icons.my_location, size: 16),
            label: Text(_loading && _mcLevels == null
                ? 'Mencari…'
                : 'Gunakan Lokasi Saya'),
          ),
        ]),
        if (_geoErr.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_geoErr,
                  style: const TextStyle(color: IOH.danger, fontSize: 12))),
        if (_mcLevels != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _mcLevels!.map((lv) {
                  final active = _mcPick == lv['level'];
                  final supported =
                      _supportsScope(_tab, lv['level']?.toString() ?? '');
                  return Semantics(
                    button: true,
                    selected: active,
                    enabled: supported,
                    label: '${lv['label']}: ${lv['name']}',
                    hint: supported
                        ? 'Pilih level wilayah'
                        : 'Level tidak didukung laporan ini',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: supported
                          ? () {
                              setState(() {
                                _mcPick = lv['level'].toString();
                                _scopeType = _mcPick;
                                _scopeValue =
                                    (lv['value'] ?? lv['name']).toString();
                              });
                              _loadActiveReport();
                            }
                          : null,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: active ? IOH.teal500 : context.vWhite,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: active ? IOH.teal500 : context.vRule)),
                        child: Text('${lv['label']}: ${lv['name']}',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? Colors.white
                                    : supported
                                        ? context.vMute
                                        : context.vRule)),
                      ),
                    ),
                  );
                }).toList()),
          ),
      ]),
    );
  }

  void _selectMode(String key) {
    if (_mode == key) return;
    setState(() => _mode = key);
    _loadActiveReport();
  }

  Widget _tabs() {
    return ReportSegmentedControl<String>(
      value: _mode,
      onChanged: _selectMode,
      semanticLabel: 'Mode Performance Outlook',
      items: const [
        ReportSegmentItem(
          value: 'mycoord',
          label: 'My Coordinate',
          icon: Icons.my_location_outlined,
        ),
        ReportSegmentItem(
          value: 'territory',
          label: 'Territory Wise',
          icon: Icons.table_chart_outlined,
        ),
        ReportSegmentItem(
          value: 'snapshot',
          label: 'Daily Snapshot',
          icon: Icons.dashboard_outlined,
        ),
      ],
    );
  }

  void _selectSubTab(String key) {
    if (_subTab == key) return;
    final crossing = (key == 'ftth') != (_subTab == 'ftth');
    setState(() {
      _subTab = key;
      if (crossing) {
        _scopeType = 'all';
        _scopeValue = '';
        _scopeOptions = [];
      } else if (!_supportsScope(key, _scopeType)) {
        Map<String, dynamic>? replacement;
        for (final level in _mcLevels ?? const <Map<String, dynamic>>[]) {
          final levelId = level['level']?.toString() ?? '';
          if (_supportsScope(key, levelId)) {
            replacement = level;
            break;
          }
        }
        if (replacement == null) {
          _scopeType = 'all';
          _scopeValue = '';
          _scopeOptions = [];
        } else {
          _scopeType = replacement['level'].toString();
          _scopeValue =
              (replacement['value'] ?? replacement['name']).toString();
          _mcPick = _scopeType;
        }
      }
    });
    // Cache hits paint instantly; this also re-warms after a scope repair.
    _loadActiveReport();
  }

  bool _supportsScope(String tab, String scope) {
    if (scope == 'all') return true;
    if (tab == 'internal' || tab == 'benchmark') {
      return const {'region', 'kabkota', 'kecamatan'}.contains(scope);
    }
    return true;
  }

  Widget _subTabs() {
    return ReportTabRail<String>(
      value: _subTab,
      onChanged: _selectSubTab,
      semanticLabel: 'Jenis Performance Outlook',
      items: const [
        ReportSegmentItem(value: 'comprehensive', label: 'Comprehensive'),
        ReportSegmentItem(value: 'fwa', label: 'FWA Summary'),
        ReportSegmentItem(value: 'ftth', label: 'Indosat HiFi (FTTH)'),
        ReportSegmentItem(value: 'datarev', label: 'Data Revenue'),
        ReportSegmentItem(value: 'product', label: 'Product Demand'),
        ReportSegmentItem(value: 'benchmark', label: 'Network Benchmark'),
        ReportSegmentItem(value: 'internal', label: 'Internal Net Performance'),
        ReportSegmentItem(value: 'insight', label: 'Market Insight'),
      ],
    );
  }

  Widget _brandBar() {
    return Container(
      decoration: BoxDecoration(
          color: context.vWhite,
          border: Border(top: BorderSide(color: context.vRule)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, -2))
          ]),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: ReportSegmentedControl<String>(
            value: _brand,
            equalWidth: true,
            style: ReportSegmentStyle.flat,
            semanticLabel: 'Brand laporan',
            onChanged: (brand) {
              setState(() => _brand = brand);
              // Brand is part of the cache key for several tabs, so re-warm.
              _loadActiveReport();
            },
            items: [
              for (final brand in const [Brands.ioh, Brands.im3, Brands.tri])
                ReportSegmentItem(
                  value: brand.key,
                  label: brand.label,
                  selectedColor: brand.color,
                  selectedForeground: brand.onColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _locateMe() async {
    setState(() {
      _loading = true;
      _geoErr = '';
      _mcLevels = null;
    });
    final coord = await getCurrentCoord(context);
    if (coord == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final d = await ApiClient.reportLocate(lat: coord.$1, lon: coord.$2);
      if (!mounted) return;
      if (d['error'] != null) {
        setState(() {
          _geoErr = d['error'].toString();
          _loading = false;
        });
      } else {
        final lvls = ((d['levels'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .where((x) => x['name'] != null)
            .toList();
        setState(() {
          if (d['circle'] != null) _circle = d['circle'].toString();
          _mcLevels = lvls;
          if (lvls.isNotEmpty) {
            _mcPick = lvls.first['level'].toString();
            _scopeType = _mcPick;
            _scopeValue =
                (lvls.first['value'] ?? lvls.first['name']).toString();
          }
        });
        if (lvls.isNotEmpty) {
          // Load only the active tab; cached tabs remain available.
          await _loadActiveReport();
        } else {
          if (mounted) setState(() => _loading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _geoErr = e.toString();
          _loading = false;
        });
      }
    }
  }

  // Fetch on demand so navigating one report never scans all other reports.
  Future<void> _loadActiveReport({bool force = false}) async {
    // My Coordinate has nothing to fetch until a level is picked.
    if (_mode == 'mycoord' && _scopeValue.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    await _load(force: force);
  }

  int _activeFilterCount() {
    var count = 0;
    if (_circle != 'ALL') count++;
    if (_scopeType != 'all') count++;
    if (_scopeValue.isNotEmpty) count++;
    if (_tab == 'snapshot' && _metric != 'rev_prepaid') count++;
    if (_tab == 'product' && _pdScope != 'total') count++;
    return count;
  }

  void _openFiltersSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.vWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _LiveReportFilterSheet(
        controlsBuilder: (refresh, openScopeSearch) => _controls(
          onRefresh: refresh,
          onScopeTap: openScopeSearch,
        ),
        options: () => _scopeOptions,
        selected: () => _scopeValue,
        scopeTitle: () => _scopeLabel(_scopeType),
        onScopePick: (value) {
          setState(() => _scopeValue = value);
          _loadActiveReport();
        },
      ),
    );
  }

  String? _dataAsOf() {
    Map<String, dynamic>? d;
    if (_tab == 'snapshot') d = _data;
    if (_tab == 'comprehensive') d = _comp;
    if (_tab == 'datarev') d = _drev;
    if (_tab == 'product') d = _prod;
    if (_tab == 'benchmark') d = _bench;
    if (_tab == 'fwa') d = _fwa;
    if (_tab == 'internal') d = _internal;
    if (_tab == 'insight') d = _insight;
    if (_tab == 'ftth') d = _ftth;
    final wrapped = d?['data'];
    final root = wrapped is Map
        ? wrapped.map((key, value) => MapEntry(key.toString(), value))
        : d;
    final scopeRaw = root?['scope'];
    final scope = scopeRaw is Map
        ? scopeRaw.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};
    final v = (scope['data_as_of'] ?? root?['data_as_of'])?.toString();
    return (v != null && v.isNotEmpty) ? v : null;
  }

  Widget _controls({VoidCallback? onRefresh, VoidCallback? onScopeTap}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_tab == 'snapshot') _dropMetric(onRefresh: onRefresh),
        _drop('Circle', _circle,
            {'ALL': 'All Circles', for (final c in _circles) c: c}, (v) {
          setState(() => _circle = v);
          onRefresh?.call();
          _loadScopeOptions(onUpdated: onRefresh);
          _loadActiveReport();
        }),
        if (_tab == 'snapshot' ||
            _tab == 'comprehensive' ||
            _tab == 'datarev' ||
            _tab == 'fwa' ||
            _tab == 'benchmark' ||
            _tab == 'internal')
          _drop('View', _scopeType, _scopeChoices(), (v) {
            setState(() {
              _scopeType = v;
              _scopeValue = '';
            });
            onRefresh?.call();
            _loadScopeOptions(onUpdated: onRefresh);
            if (v == 'all') _loadActiveReport();
          }),
        if (_tab == 'ftth')
          _drop('View', _scopeType, const {
            'all': 'Circle (all)',
            'ftth_region': 'Region',
            'ftth_province': 'Province',
            'ftth_kabkota': 'Kab/Kota',
            'ftth_kecamatan': 'Kecamatan',
          }, (v) {
            setState(() {
              _scopeType = v;
              _scopeValue = '';
            });
            onRefresh?.call();
            _loadScopeOptions(onUpdated: onRefresh);
            if (v == 'all') _loadActiveReport();
          }),
        if ((_tab == 'snapshot' ||
                _tab == 'comprehensive' ||
                _tab == 'datarev' ||
                _tab == 'fwa' ||
                _tab == 'benchmark' ||
                _tab == 'internal' ||
                _tab == 'ftth') &&
            _scopeType != 'all')
          _wrapDrop(
              _scopeLabel(_scopeType),
              SizedBox(
                width: 168,
                height: 30,
                child: InkWell(
                  onTap: _scopeOptions.isEmpty
                      ? null
                      : (onScopeTap ?? _openScopePicker),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                      _scopeValue.isEmpty ? 'Pilih wilayah' : _scopeValue,
                      style: TextStyle(
                          fontSize: 12,
                          color: _scopeValue.isEmpty
                              ? context.vMute
                              : context.vInk),
                      overflow: TextOverflow.ellipsis,
                    )),
                    Icon(Icons.search, size: 15, color: context.vMute),
                  ]),
                ),
              )),
        if (_tab == 'product')
          _drop('Scope', _pdScope, const {
            'total': 'Total',
            'organic': 'Organic',
            'digital': 'Digital',
            'trade': 'Trade'
          }, (v) {
            setState(() => _pdScope = v);
            onRefresh?.call();
            _load();
          }),
      ],
    );
  }

  String _scopeLabel(String k) =>
      const {
        'region': 'Region',
        'area': 'Area',
        'branch': 'Area',
        'microcluster': 'District',
        'district': 'District',
        'kabkota': 'Kab/Kota',
        'kecamatan': 'Kecamatan',
        'ftth_region': 'Region',
        'ftth_province': 'Province',
        'ftth_kabkota': 'Kab/Kota',
        'ftth_kecamatan': 'Kecamatan',
      }[k] ??
      k;

  Map<String, String> _scopeChoices() {
    if (_tab == 'internal' || _tab == 'benchmark') {
      return const {
        'all': 'Circle (all)',
        'region': 'Region',
        'area': 'Area',
        'district': 'District',
        'kabkota': 'Kab/Kota',
        'kecamatan': 'Kecamatan',
      };
    }
    return const {
      'all': 'Circle (all)',
      'region': 'Region',
      'area': 'Area',
      'district': 'District',
      'kabkota': 'Kab/Kota',
      'kecamatan': 'Kecamatan',
    };
  }

  Widget _dropMetric({VoidCallback? onRefresh}) {
    final items = <DropdownMenuItem<String>>[];
    for (final c in _categories) {
      for (final m in (c['metrics'] as List? ?? [])) {
        items.add(DropdownMenuItem(
            value: m['code'].toString(),
            child:
                Text(m['name'].toString(), overflow: TextOverflow.ellipsis)));
      }
    }
    if (items.isEmpty) {
      items.add(const DropdownMenuItem(
          value: 'rev_prepaid', child: Text('Revenue Prepaid')));
    }
    return _wrapDrop(
        'Metric',
        SizedBox(
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
              onRefresh?.call();
              _load();
            },
          ),
        ));
  }

  Widget _drop(String label, String value, Map<String, String> opts,
      ValueChanged<String> onCh) {
    return _wrapDrop(
        label,
        SizedBox(
          height: 30,
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            style: TextStyle(fontSize: 12, color: context.vInk),
            icon: Icon(Icons.arrow_drop_down, size: 18, color: context.vMute),
            underline: const SizedBox.shrink(),
            items: opts.entries
                .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: (v) {
              if (v != null) onCh(v);
            },
          ),
        ));
  }

  Widget _wrapDrop(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: IOH.teal600,
                letterSpacing: 0.6)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
              color: context.vWhite,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: context.vRule)),
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _ScopeSearchSheet(
        title: _scopeLabel(_scopeType),
        options: _scopeOptions,
        selected: _scopeValue,
        onPick: (v) {
          Navigator.pop(ctx);
          setState(() => _scopeValue = v);
          _loadActiveReport();
        },
      ),
    );
  }

  Widget _kpiTile(Map<String, dynamic> t, bool up) {
    final c = up ? IOH.teal600 : IOH.danger;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(12),
        border: const Border(top: BorderSide(color: IOH.teal500, width: 3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '${(_data!['metric']?['name'] ?? '').toString().toUpperCase()} · MTD',
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: IOH.teal600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: _fmt(t['mtd']),
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: context.vInk)),
                      TextSpan(
                          text: '  ${_unit()}',
                          style: TextStyle(fontSize: 13, color: context.vMute)),
                    ])),
                    const SizedBox(height: 4),
                    Text(
                        'IM3 ${_fmt(t['mtd_im3'])} · 3ID ${_fmt(t['mtd_3id'])}',
                        style: TextStyle(fontSize: 12, color: context.vMute)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${up ? '▲' : '▼'} ${_pct(t['pct_change'])}',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: c)),
                  const SizedBox(height: 2),
                  Text('${_var(t['abs_change'])} vs LMTD',
                      style: TextStyle(fontSize: 11.5, color: c)),
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: c, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: IOH.teal600,
                  letterSpacing: 0.6)),
          const SizedBox(height: 3),
          Text((m?['name'] ?? 'N/A').toString(),
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: context.vInk),
              softWrap: true),
          const SizedBox(height: 2),
          Text('${_var(m?['var'])} · ${_pct(m?['pct'])}',
              style: TextStyle(fontSize: 12, color: c)),
        ],
      ),
    );
  }

  Widget _panel(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.vRule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: IOH.teal600,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _brandTable(dynamic rowsData) {
    final rows = (rowsData as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (rows.isEmpty) {
      return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    }
    // Three brand bands share one row, so this keeps ReportAllDataTable
    // directly instead of ReportPeriodTable. Geometry and growth colouring
    // still come from the shared period constants.
    const bands = [Brands.ioh, Brands.im3, Brands.tri];
    final polarity = reportPolarityFor(_metric);

    num? growthOf(Map<String, dynamic> row, BrandIdentity band) =>
        (band.key == 'ioh' ? row['growth_pct'] : row['growth_pct_${band.key}'])
            as num?;

    return ReportAllDataTable<Map<String, dynamic>>(
      semanticLabel: 'Snapshot brand breakdown, ${rows.length} baris',
      rows: rows,
      layoutPolicy: ReportTableLayoutPolicy.horizontal,
      freezeFirstColumn: true,
      headerBackground: IOH.teal500,
      storageKey: 'snapshot-brand-$_metric-$_brand',
      columns: [
        ReportTableColumn(
          label: 'Name',
          width: ReportPeriodTable.dataColumnWidth * 2,
          emphasized: true,
          value: (row) => row['name'],
          secondaryValue: (row) => row['parent'],
        ),
        for (final band in bands) ...[
          ReportTableColumn(
              label: '${band.label} LLMTD',
              width: ReportPeriodTable.dataColumnWidth,
              numeric: true,
              value: (row) => _fmt(row['llmtd_${band.key}'])),
          ReportTableColumn(
              label: '${band.label} LMTD',
              width: ReportPeriodTable.dataColumnWidth,
              numeric: true,
              value: (row) => _fmt(row['lmtd_${band.key}'])),
          ReportTableColumn(
              label: '${band.label} MTD',
              width: ReportPeriodTable.dataColumnWidth,
              numeric: true,
              emphasized: true,
              value: (row) => _fmt(row['mtd_${band.key}'])),
          ReportTableColumn(
            label: '${band.label} Growth',
            semanticLabel: '${band.label} Growth MTD terhadap LMTD',
            width: ReportPeriodTable.growthColumnWidth,
            numeric: true,
            comparison: true,
            value: (row) => _pct(growthOf(row, band)),
            secondaryValue: (row) => _var(row['abs_growth_${band.key}']),
            signal: (row) => growthOf(row, band),
            polarity: polarity,
          ),
        ],
      ],
    );
  }

  // ── Snapshot full deck (sub-tabbed to keep the view short) ──

  String _fmtBy(String kind, dynamic v) {
    if (v == null) return kReportNotAvailable;
    if (kind == 'mn') return _mn(v);
    if (kind == 'pct') return reportPercent(v);
    return _num(v);
  }

  Widget _monthlyKVTable(
      List<Map<String, dynamic>> hist, List<List<String>> rowsDef) {
    final months = hist.map((h) => h['month_id'].toString()).toList();
    return ReportAllDataTable<List<String>>(
      semanticLabel: 'Monthly metric history',
      rows: rowsDef,
      layoutPolicy: ReportTableLayoutPolicy.horizontal,
      storageKey: 'monthly-history-${months.join('|')}',
      columns: [
        ReportTableColumn(label: 'Metric', width: 170, value: (row) => row[1]),
        for (var index = 0; index < months.length; index++)
          ReportTableColumn(
            label: months[index],
            numeric: true,
            value: (row) => _fmtBy(row[2], hist[index][row[0]]),
          ),
      ],
    );
  }

  List<Widget> _snapshotDeck() {
    final deck = _data!['deck'] as Map<String, dynamic>?;
    if (deck == null) return [];
    final counts = (deck['counts'] as Map<String, dynamic>?) ?? {};
    const sections = [
      ['circle', 'Circle'],
      ['region', 'Region'],
      ['branch', 'Area'],
      ['microcluster', 'District'],
      ['kabkota', 'Kab/Kota'],
      ['kecamatan', 'Kecamatan'],
    ];
    const fullLevels = ['circle', 'region', 'branch'];

    // sub-tab selector
    final tabRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
          children: sections.map((s) {
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
            child: Text(s[1],
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : context.vMute)),
          ),
        );
      }).toList()),
    );

    Widget content;
    final cnt = counts[_deckTab] ?? 0;
    if (fullLevels.contains(_deckTab)) {
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Brand Breakdown · $cnt total',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: IOH.teal600)),
        const SizedBox(height: 8),
        _brandTable((deck[_deckTab] as Map<String, dynamic>?)?['rows']),
      ]);
    } else {
      final set = deck[_deckTab] as Map<String, dynamic>?;
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$cnt total',
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: IOH.teal600)),
        const SizedBox(height: 8),
        Text('▼ Top 10 Decline',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: IOH.danger)),
        const SizedBox(height: 6),
        _brandTable(set?['decline']),
        const SizedBox(height: 16),
        Text('▲ Top 10 Growth',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: IOH.teal600)),
        const SizedBox(height: 6),
        _brandTable(set?['growth']),
      ]);
    }

    return [
      _panel(
          'Territory Breakdown',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            tabRow,
            const SizedBox(height: 12),
            content,
          ])),
    ];
  }

  // ── Comprehensive ──
  List<Widget> _comprehensiveSections([Map<String, dynamic>? payload]) {
    final src = payload ?? _comp;
    final sections =
        (src?['sections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final out = <Widget>[];
    String? lastGroup;
    for (final s in sections) {
      final group = s['group'] as String?;
      if (group != null && group != lastGroup) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(group.toUpperCase(),
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: context.vInk,
                  letterSpacing: 0.6)),
        ));
      }
      lastGroup = group;
      final layout = s['layout'];
      final title = s['title'].toString();
      final rowCount = layout == 'grid'
          ? ((s['metrics'] as List?)?.length ?? 0)
          : ((s['rows'] as List?)?.length ?? 0);
      final meta = layout == 'grid' ? '$rowCount metrik' : '$rowCount baris';
      if (layout == 'flat') {
        out.add(_detailPanel(
          '$title${s['month_used'] != null ? ' | ${s['month_used']}' : ''}',
          _flatTable(s),
          sectionKey: title,
          meta: meta,
        ));
      } else if (layout == 'ftth_counts') {
        out.add(_detailPanel(title, _ftthCountTable(s),
            sectionKey: title, meta: meta));
      } else if (layout == 'hierarchy') {
        out.add(_detailPanel(title, _ftthHierarchyTable(s),
            sectionKey: title, meta: meta));
      } else {
        final cum = s['cumulative_yoy'] == true;
        out.add(_detailPanel(
          '$title${cum ? ' | YTD/YoY' : ''}',
          _compTable(s, cum),
          sectionKey: title,
          meta: meta,
        ));
      }
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  Widget _flatTable(Map<String, dynamic> s) {
    final rows = (s['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final columns = (s['columns'] as List?)?.cast<String>() ?? ['Share %'];
    String fmtCell(dynamic v, int ci) =>
        ci == 0 ? reportPercent(v) : reportNumber(v);

    // Industry is the denominator and IOH is the group total of IM3 plus 3ID.
    // Both are reference rows, so both read bold.
    bool isReference(Map<String, dynamic> row) {
      if (row['aggregate'] == true) return true;
      return row['actor']?.toString().toUpperCase() == 'INDUSTRY';
    }

    Color? actorColor(Map<String, dynamic> row) =>
        Brands.colorOf(row['actor']?.toString());

    return ReportAllDataTable<Map<String, dynamic>>(
      semanticLabel: '${s['title'] ?? 'Report'} all data',
      rows: rows,
      layoutPolicy: ReportTableLayoutPolicy.horizontal,
      storageKey: 'flat-${s['title']}-${columns.join('|')}',
      columns: [
        ReportTableColumn(
          label: 'Operator',
          width: 110,
          value: (row) => row['actor'],
          textColorOf: actorColor,
          emphasizedOf: isReference,
        ),
        for (var index = 0; index < columns.length; index++)
          ReportTableColumn(
            label: columns[index],
            numeric: true,
            value: (row) {
              final cells = (row['cells'] as List?) ?? [row['value']];
              return index < cells.length ? cells[index] : null;
            },
            formatter: (value) => fmtCell(value, index),
            emphasizedOf: isReference,
          ),
      ],
    );
  }

  Widget _compTable(Map<String, dynamic> s, bool cum) {
    final metrics = (s['metrics'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (metrics.isEmpty) {
      return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    }
    final activeBrand = _tab == 'ftth' ? 'ioh' : _brand;

    String fmtComp(dynamic v, String unit) {
      if (v == null) return kReportNotAvailable;
      if (unit == '%') return _pct(v);
      if (unit == 'ratio') return reportNumber(v, decimals: 2);
      if (unit == 'GB') return reportNumber(v, decimals: 1);
      return reportNumber(v); // Rp
    }

    final rows = <ReportPeriodRow>[];
    for (final metric in metrics) {
      final values =
          (metric[activeBrand] as Map?)?.cast<String, dynamic>() ?? {};
      final unit = (metric['unit'] ?? '').toString();
      final isComputed = metric['computed'] == true;

      // Ratio and percent metrics carry their own unit and are never scaled.
      // Everything else shares one tier across all five periods, so a
      // YTD-heavy metric no longer picks a tier that only fits its MTD.
      final String unitLabel;
      final String Function(dynamic) number;
      final String Function(dynamic) variance;
      if (isComputed) {
        unitLabel = unit;
        number = (value) => fmtComp(value, unit);
        variance = (value) => value == null
            ? kReportNotAvailable
            : '${(value as num) >= 0 ? '\u25B2' : '\u25BC'} ${fmtComp(value.abs(), unit)}';
      } else {
        final peak = [
          values['mtd'],
          values['lmtd'],
          values['llmtd'],
          values['ytd'],
          values['lytd'],
        ]
            .map((x) => (x as num?)?.abs().toDouble() ?? 0)
            .fold<double>(0, (a, v) => a > v ? a : v);
        final tier = reportMagnitudeTier(peak, unit: unit);
        unitLabel = tier.label;
        number = (value) => reportScaled(value, tier.divisor);
        variance = (value) => reportVariance(value, divisor: tier.divisor);
      }

      rows.add(ReportPeriodRow(
        name: (metric['name'] ?? metric['code']).toString(),
        subtitle: unitLabel.isEmpty ? null : unitLabel,
        code: (metric['code'] ?? '').toString(),
        cells: {
          'llmtd': ReportPeriodCell(number(values['llmtd'])),
          'lmtd': ReportPeriodCell(number(values['lmtd'])),
          'mtd': ReportPeriodCell(number(values['mtd'])),
          'growthMom': ReportPeriodCell(
            _pct(values['growth_mom_pct']),
            secondaryText: variance(values['var_mom']),
            raw: values['growth_mom_pct'] as num?,
          ),
          'lytd': ReportPeriodCell(number(values['lytd'])),
          'ytd': ReportPeriodCell(number(values['ytd'])),
          'growthYoy': ReportPeriodCell(
            _pct(values['growth_yoy_pct']),
            secondaryText: variance(values['var_yoy']),
            raw: values['growth_yoy_pct'] as num?,
          ),
        },
      ));
    }

    return ReportPeriodTable(
      semanticLabel: '${s['title'] ?? 'Metrics'} complete period table',
      rows: rows,
      band: Brands.of(activeBrand),
      storageKey: 'comprehensive-${s['title']}-$activeBrand',
      nameLabel: 'Metric',
    );
  }

  // ── Data Revenue ──
  /// Adaptive magnitude: plain below a million, then Mn, then Bn. A small
  /// revenue must never render as `0,0 Bn`.
  String _mn(dynamic v) => reportMagnitude(v, decimals: 1, useThousand: false);

  String _num(dynamic v) => reportNumber(v);

  List<Widget> _dataRevSections() {
    final chunks =
        (_drev!['chunks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final slabs =
        (_drev!['price_slabs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final ratios = _drev!['ratios'] as Map<String, dynamic>?;
    final out = <Widget>[];

    // Ratios panel: channel mix + ATL/BTL
    if (ratios != null) {
      Widget chip(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(999)),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: fg)));
      final cp = (ratios['channel_pct'] as Map<String, dynamic>?) ?? {};
      final avb = ratios['atl_vs_btl'];
      out.add(_detailPanel(
          'Ratios | Channel Mix & ATL/BTL',
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in cp.entries)
              chip('${e.key}: ${_pct(e.value)}', const Color(0xFFEAF6F4),
                  IOH.teal600),
            chip('ATL: ${_pct(ratios['atl_pct'])}', context.vPanel,
                context.vInk),
            chip('BTL: ${_pct(ratios['btl_pct'])}', context.vPanel,
                context.vInk),
            chip(
                'ATL/BTL: ${avb == null ? kReportNotAvailable : '${reportNumber(avb, decimals: 2)}x'}',
                const Color(0xFFFDF3E2),
                const Color(0xFF9A6B00)),
          ]),
          sectionKey: 'Ratios',
          meta: '${cp.length + 3} indikator'));
      out.add(const SizedBox(height: 12));
    }

    for (final c in chunks) {
      final channels = (c['channels'] as List?)?.length ?? 0;
      out.add(_detailPanel(
        '${c['name']} (Mn IDR)',
        _drChunkTable(c),
        sectionKey: c['name'].toString(),
        meta: '$channels channel',
      ));
      out.add(const SizedBox(height: 12));
    }
    // price slabs with channel scope tabs and channel-detail chips
    out.add(_detailPanel(
      'Price Slab Breakdown (Mn IDR)',
      _slabPanel(slabs),
      sectionKey: 'Price Slab Breakdown',
      meta: '${slabs.length} slab',
    ));
    return out;
  }

  Widget _slabPanel(List<Map<String, dynamic>> fallbackSlabs) {
    final scopes =
        (_drev!['price_slab_scopes'] as Map?)?.cast<String, dynamic>();
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
        onTap: () => setState(() {
          _slabScope = k;
          _slabDetail = '';
        }),
        child: Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
              color: active ? IOH.teal500 : context.vWhite,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? IOH.teal500 : context.vRule)),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : context.vMute)),
        ),
      );
    }

    Widget chip(String label, String val) {
      final active = _slabDetail == val;
      return GestureDetector(
        onTap: () => setState(() => _slabDetail = val),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: active ? IOH.teal500 : context.vWhite,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? IOH.teal500 : context.vRule)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : context.vMute)),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: avail.map(scopeTab).toList())),
      if (detailNames.isNotEmpty) ...[
        const SizedBox(height: 8),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: chip('All ${(cur['label'] ?? '')}', '')),
              ...detailNames.map((dn) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: chip(dn, dn))),
            ])),
      ],
      const SizedBox(height: 10),
      _slabTable(slabs),
    ]);
  }

  // Price slab table: frozen Slab column plus full timeframe data columns.
  Widget _slabTable(List<Map<String, dynamic>> slabs,
      {String nameLabel = 'Slab', double nameW = 140.0}) {
    // Only MTD is stored per brand. The other timeframes are IOH totals, so
    // scale them by this slab's brand share to stay apple-to-apple.
    double brandValue(Map<String, dynamic> r) =>
        (r[_brand] as num?)?.toDouble() ?? 0;
    double brandShare(Map<String, dynamic> r) {
      final ioh = (r['ioh'] as num?)?.toDouble() ?? 0;
      return ioh == 0 ? 1 : brandValue(r) / ioh;
    }

    final rows = <ReportPeriodRow>[];
    for (final slab in slabs) {
      final factor = brandShare(slab);
      final mtd = brandValue(slab);
      final lmtd = ((slab['lmtd'] as num?)?.toDouble() ?? 0) * factor;
      final llmtd = ((slab['llmtd'] as num?)?.toDouble() ?? 0) * factor;
      final ytd = ((slab['ytd'] as num?)?.toDouble() ?? 0) * factor;
      final lytd = ((slab['lytd'] as num?)?.toDouble() ?? 0) * factor;
      final varMom = mtd - lmtd;
      final varYoy = ytd - lytd;
      final growthMom = lmtd != 0 ? varMom / lmtd * 100 : null;
      final growthYoy = lytd != 0 ? varYoy / lytd * 100 : null;
      rows.add(ReportPeriodRow(
        name: (slab['slab'] ?? '').toString(),
        code: 'rev_slab',
        cells: {
          'llmtd': ReportPeriodCell(_mn(llmtd)),
          'lmtd': ReportPeriodCell(_mn(lmtd)),
          'mtd': ReportPeriodCell(_mn(mtd)),
          'growthMom': ReportPeriodCell(
            _pct(growthMom),
            secondaryText: reportVarianceMagnitude(varMom, useThousand: false),
            raw: growthMom,
          ),
          'lytd': ReportPeriodCell(_mn(lytd)),
          'ytd': ReportPeriodCell(_mn(ytd)),
          'growthYoy': ReportPeriodCell(
            _pct(growthYoy),
            secondaryText: reportVarianceMagnitude(varYoy, useThousand: false),
            raw: growthYoy,
          ),
          'extra': ReportPeriodCell(_num(slab['hit'])),
        },
      ));
    }

    return ReportPeriodTable(
      semanticLabel: '$nameLabel complete period table',
      rows: rows,
      band: Brands.of(_brand),
      storageKey: 'slab-$nameLabel-$_brand',
      nameLabel: nameLabel,
      nameWidth: nameW,
      columns: const [
        ...ReportPeriodTable.fullPeriods,
        ReportPeriodColumn.extra,
      ],
      extraLabel: 'Hits',
    );
  }

  // Data Revenue chunk table: one shared period table with a TOTAL headline
  // row and expandable channel_detail rows.
  Widget _drChunkTable(Map<String, dynamic> c) {
    final channels =
        (c['channels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final headline = c['headline'] as Map<String, dynamic>;

    // Only MTD is stored per brand. The remaining timeframes are IOH totals,
    // so scale them by this channel's brand share to stay apple-to-apple.
    double brandValue(Map<String, dynamic> r) =>
        (r[_brand] as num?)?.toDouble() ?? 0;
    double brandShare(Map<String, dynamic> r) {
      final ioh = (r['ioh'] as num?)?.toDouble() ?? 0;
      return ioh == 0 ? 1 : brandValue(r) / ioh;
    }

    ReportPeriodRow buildRow(
      String label,
      Map<String, dynamic> values, {
      dynamic contribution,
      bool indented = false,
      bool headlineRow = false,
      String? expandKey,
      bool expanded = false,
    }) {
      final factor = brandShare(values);
      final mtd = brandValue(values);
      final lmtd = ((values['lmtd'] as num?)?.toDouble() ?? 0) * factor;
      final llmtd = ((values['llmtd'] as num?)?.toDouble() ?? 0) * factor;
      final ytd = ((values['ytd'] as num?)?.toDouble() ?? 0) * factor;
      final lytd = ((values['lytd'] as num?)?.toDouble() ?? 0) * factor;
      final varMom = mtd - lmtd;
      final varYoy = ytd - lytd;
      final growthMom = lmtd != 0 ? varMom / lmtd * 100 : null;
      final growthYoy = lytd != 0 ? varYoy / lytd * 100 : null;
      return ReportPeriodRow(
        name: label,
        code: 'rev_channel',
        indented: indented,
        headline: headlineRow,
        expandKey: expandKey,
        expanded: expanded,
        cells: {
          'llmtd': ReportPeriodCell(_mn(llmtd)),
          'lmtd': ReportPeriodCell(_mn(lmtd)),
          'mtd': ReportPeriodCell(_mn(mtd)),
          'growthMom': ReportPeriodCell(
            _pct(growthMom),
            secondaryText: reportVarianceMagnitude(varMom, useThousand: false),
            raw: growthMom,
          ),
          'lytd': ReportPeriodCell(_mn(lytd)),
          'ytd': ReportPeriodCell(_mn(ytd)),
          'growthYoy': ReportPeriodCell(
            _pct(growthYoy),
            secondaryText: reportVarianceMagnitude(varYoy, useThousand: false),
            raw: growthYoy,
          ),
          'extra': ReportPeriodCell(_pct(contribution)),
        },
      );
    }

    final rows = <ReportPeriodRow>[
      buildRow('TOTAL', headline, contribution: 100.0, headlineRow: true),
    ];
    for (final channel in channels) {
      final details =
          (channel['details'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final key = '${c['name']}|${channel['channel']}';
      final isOpen = _drExpanded.contains(key);
      rows.add(buildRow(
        (channel['channel'] ?? '').toString(),
        channel,
        contribution: channel['contrib_pct'],
        expandKey: details.isEmpty ? null : key,
        expanded: isOpen,
      ));
      if (!isOpen) continue;
      for (final detail in details) {
        rows.add(buildRow(
          (detail['detail'] ?? '').toString(),
          detail,
          contribution: detail['contrib_pct'],
          indented: true,
        ));
      }
    }

    return ReportPeriodTable(
      semanticLabel: '${c['name']} complete channel detail',
      rows: rows,
      band: Brands.of(_brand),
      storageKey: 'data-revenue-${c['name']}-$_brand',
      nameLabel: 'Channel',
      nameWidth: 180,
      columns: const [
        ...ReportPeriodTable.fullPeriods,
        ReportPeriodColumn.extra,
      ],
      extraLabel: 'Contrib %',
      onToggleRow: (key) => setState(() => _drExpanded.contains(key)
          ? _drExpanded.remove(key)
          : _drExpanded.add(key)),
    );
  }

  // ── Product Demand ──
  static const _rankBg = [
    Color(0xFFED1C24),
    Color(0xFFEC008C),
    Color(0xFFFFCB05)
  ];
  static const _rankFg = [Colors.white, Colors.white, Color(0xFF161616)];

  Widget _pill(String label, bool active, VoidCallback onTap,
          {bool small = false}) =>
      Semantics(
        button: true,
        selected: active,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            margin: small ? EdgeInsets.zero : const EdgeInsets.only(right: 6),
            padding: EdgeInsets.symmetric(
                vertical: small ? 5 : 6, horizontal: small ? 10 : 12),
            decoration: BoxDecoration(
                color: active ? IOH.teal500 : context.vWhite,
                borderRadius: BorderRadius.circular(999),
                border:
                    Border.all(color: active ? IOH.teal500 : context.vRule)),
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: small ? 10.5 : 12,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : context.vMute)),
          ),
        ),
      );

  Widget _pdSlabPanel(Map<String, dynamic> scopes) {
    const order = ['total', 'organic', 'digital', 'trade'];
    final avail = order.where((k) => scopes.containsKey(k)).toList();
    if (!avail.contains(_pdSlabScope)) _pdSlabScope = 'total';
    final cur = (scopes[_pdSlabScope] as Map?)?.cast<String, dynamic>() ?? {};
    final details = (cur['details'] as Map?)?.cast<String, dynamic>() ?? {};
    final detailNames = details.keys.toList()..sort();
    final dimSrc =
        (_pdSlabDetail.isNotEmpty && details.containsKey(_pdSlabDetail))
            ? (details[_pdSlabDetail] as Map).cast<String, dynamic>()
            : cur;
    final rows = ((_pdSlabDim == 'quota' ? dimSrc['quota'] : dimSrc['validity'])
                as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final tops =
        (dimSrc['top_products'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // channel scope tabs
      SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
              children: avail
                  .map((k) => _pill(
                      (scopes[k] as Map?)?['label']?.toString() ?? k,
                      _pdSlabScope == k,
                      () => setState(() {
                            _pdSlabScope = k;
                            _pdSlabDetail = '';
                          })))
                  .toList())),
      // channel detail chips
      if (detailNames.isNotEmpty) ...[
        const SizedBox(height: 8),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _pill(
                      'All ${(cur['label'] ?? '')}',
                      _pdSlabDetail == '',
                      () => setState(() => _pdSlabDetail = ''),
                      small: true)),
              ...detailNames.map((dn) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _pill(dn, _pdSlabDetail == dn,
                      () => setState(() => _pdSlabDetail = dn),
                      small: true))),
            ])),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: [
        _pill('Slab Kuota', _pdSlabDim == 'quota',
            () => setState(() => _pdSlabDim = 'quota'),
            small: true),
        _pill('Slab Masa Aktif', _pdSlabDim == 'validity',
            () => setState(() => _pdSlabDim = 'validity'),
            small: true),
      ]),
      const SizedBox(height: 10),
      _slabTable(rows),
      if (tops.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('TOP PRODUCTS · ${cur['label']}',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: IOH.teal600,
                letterSpacing: 0.4)),
        const SizedBox(height: 8),
        _slabTable(tops.map((p) => {...p, 'slab': p['product']}).toList(),
            nameLabel: 'Product', nameW: 170),
      ],
    ]);
  }

  List<Widget> _productSections() {
    final qLabels = (_prod!['quota_labels'] as List?)?.cast<String>() ?? [];
    final vLabels = (_prod!['validity_labels'] as List?)?.cast<String>() ?? [];
    final rev = (_prod!['revenue_matrix'] as List?)
            ?.map(
                (r) => (r as List).map((x) => (x as num?)?.toDouble()).toList())
            .toList() ??
        [];
    final growth = (_prod!['growth_matrix'] as List?)
            ?.map(
                (r) => (r as List).map((x) => (x as num?)?.toDouble()).toList())
            .toList() ??
        [];
    final top3 = (_prod!['top_3'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    double flatMax = 1;
    for (final r in rev) {
      for (final x in r) {
        if (x != null && x.abs() > flatMax) flatMax = x.abs();
      }
    }
    double gMax = 1;
    for (final r in growth) {
      for (final x in r) {
        final a = (x ?? 0).abs();
        if (a > gMax) gMax = a;
      }
    }

    int rankOf(String q, String v) =>
        top3.indexWhere((t) => t['quota'] == q && t['validity'] == v);

    final out = <Widget>[];
    // Slab tables (Data-Revenue style): channel scope tabs and quota/validity dim
    final ss = (_prod!['slab_scopes'] as Map?)?.cast<String, dynamic>();
    if (ss != null) {
      out.add(_detailPanel(
        'Slab Breakdown (Mn IDR)',
        _pdSlabPanel(ss),
        sectionKey: 'Slab Breakdown',
        meta: 'quota, validity, dan top products',
      ));
      out.add(const SizedBox(height: 12));
    }
    // legend
    out.add(_detailPanel(
        'Top 3 Products',
        Wrap(
            spacing: 8,
            runSpacing: 8,
            children: top3.map((t) {
              final r = (t['rank'] as num).toInt();
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: _rankBg[r - 1],
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                    '#$r ${t['quota']} x ${t['validity']} | ${_mn(t['value'])}',
                    style: TextStyle(
                        color: _rankFg[r - 1],
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              );
            }).toList()),
        sectionKey: 'Top 3 Products',
        meta: '${top3.length} ranked products'));
    out.add(const SizedBox(height: 12));

    // revenue heatmap
    Widget heatCell(int ri, int ci) {
      final val = rev[ri][ci];
      final rank = rankOf(qLabels[ri], vLabels[ci]);
      final alpha =
          val == null ? 0.0 : 0.1 + 0.8 * (val.abs() / flatMax).clamp(0.0, 1.0);
      final bg =
          rank >= 0 ? _rankBg[rank] : Color.fromRGBO(21, 166, 151, alpha);
      final fg =
          rank >= 0 ? _rankFg[rank] : (alpha > 0.55 ? Colors.white : IOH.ink);
      return Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        alignment: Alignment.center,
        color: bg,
        child: Text(val == null ? kReportNotAvailable : _mn(val),
            style: TextStyle(
                fontSize: 10,
                color: fg,
                fontFeatures: const [FontFeature.tabularFigures()])),
      );
    }

    out.add(_detailPanel(
        'Revenue Heatmap | Quota x Validity (Mn IDR)',
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(
                  width: 72,
                  child: Text('', style: TextStyle(color: context.vMute))),
              ...vLabels.map((v) => SizedBox(
                  width: 60,
                  child: Text(v,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9.5, color: context.vMute))))
            ]),
            ...qLabels.asMap().entries.map((e) => Row(children: [
                  SizedBox(
                      width: 72,
                      child: Text(e.value,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: context.vInk))),
                  ...vLabels.asMap().entries.map((c) => heatCell(e.key, c.key)),
                ])),
          ]),
        ),
        sectionKey: 'Revenue Heatmap',
        meta: '${qLabels.length} x ${vLabels.length} cells'));
    out.add(const SizedBox(height: 12));

    // growth heatmap
    Widget gCell(int ri, int ci) {
      final g = growth[ri][ci];
      Color bg = context.vWhite;
      if (g != null) {
        final a = (g.abs() / gMax).clamp(0.0, 1.0);
        bg = g >= 0
            ? Color.fromRGBO(14, 133, 121, a)
            : Color.fromRGBO(185, 28, 28, a);
      }
      return Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          alignment: Alignment.center,
          color: bg,
          child: Text(g == null ? 'N/A' : _pct(g),
              style: const TextStyle(fontSize: 9.5)));
    }

    out.add(_detailPanel(
        'Growth MoM% Heatmap',
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(
                  width: 72,
                  child: Text('', style: TextStyle(color: context.vMute))),
              ...vLabels.map((v) => SizedBox(
                  width: 56,
                  child: Text(v,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9.5, color: context.vMute))))
            ]),
            ...qLabels.asMap().entries.map((e) => Row(children: [
                  SizedBox(
                      width: 72,
                      child: Text(e.value,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: context.vInk))),
                  ...vLabels.asMap().entries.map((c) => gCell(e.key, c.key)),
                ])),
          ]),
        ),
        sectionKey: 'Growth Heatmap',
        meta: '${qLabels.length} x ${vLabels.length} cells'));
    return out;
  }

  // ── Network Benchmark ──
  List<Widget> _benchmarkSections() {
    final catalog = CatalogReportData.fromPayload(_bench);
    if (catalog.hasMetrics) {
      return [_catalogReport(_bench!, includeAllBrands: true)];
    }
    final fb =
        (_bench!['fb_benchmark'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final av =
        (_bench!['availability'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final out = <Widget>[];

    if (fb.isNotEmpty) {
      out.add(_detailPanel(
        'Network Benchmark (FB) | 3 Bulan Terakhir',
        _fbBenchmarkTable(fb),
        sectionKey: 'Network Benchmark',
        meta: '${fb.length} bulan, 5 operator, 3 unit metrik',
      ));
      out.add(const SizedBox(height: 12));
    }
    if (av.isNotEmpty) {
      out.add(_detailPanel(
        'Network Availability | 3 Bulan Terakhir',
        _availTable(av),
        sectionKey: 'Network Availability',
        meta: '${av.length} bulan, 10 metrik',
      ));
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  /// XL and SF are one commercial operator. The backend already merges them
  /// sample-weighted into `*_xlsmart_4g`; this falls back to a sample-weighted
  /// merge on the client when talking to an older backend.
  num? _xlsmartValue(Map<String, dynamic> row, String measure) {
    final merged = row['${measure}_xlsmart_4g'];
    if (merged is num) return merged;
    num weighted = 0;
    num samples = 0;
    for (final member in const ['xl', 'sf']) {
      final value = row['${measure}_${member}_4g'];
      final sample = row['sample_${member}_4g'];
      if (value is! num) continue;
      final weight = sample is num ? sample : 1;
      weighted += value * weight;
      samples += weight;
    }
    return samples == 0 ? null : weighted / samples;
  }

  Widget _fbBenchmarkTable(List<Map<String, dynamic>> fb) {
    final ops = [
      ['im3', Brands.im3],
      ['tri', Brands.tri],
      ['tsel', Brands.tsel],
      ['xlsmart', Brands.xlsmart],
    ];
    final nameW = 64.0, colW = 52.0;
    final nameCol =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: nameW,
          height: 28,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Bulan',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.vMute))),
      Container(
          width: nameW,
          height: 22,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8)),
      ...fb.asMap().entries.map((e) => Container(
          width: nameW,
          height: 36,
          color: e.key.isOdd ? context.vZebra : context.vWhite,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(e.value['month_prefix'].toString(),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.vInk)))),
    ]);

    Widget head(String t, Color bg, Color fg) => Container(
        width: colW,
        height: 28,
        color: bg,
        alignment: Alignment.center,
        child: Text(t,
            style: TextStyle(
                color: fg,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 10)));
    Widget subH(String t, Color bg, Color fg) => Container(
        width: colW,
        height: 22,
        color: bg.withValues(alpha: 0.85),
        alignment: Alignment.center,
        child: Text(t, style: TextStyle(color: fg, fontSize: 9)));
    Widget cell(dynamic v, {bool bold = false, Color? bg}) => Container(
        width: colW,
        height: 36,
        color: bg,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(v == null ? 'N/A' : reportNumber(v, decimals: 1),
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: context.vInk,
                fontFeatures: const [FontFeature.tabularFigures()])));

    num? read(Map<String, dynamic> row, String key, String measure) {
      if (key == 'xlsmart') return _xlsmartValue(row, measure);
      final value = row['${measure}_${key}_4g'];
      return value is num ? value : null;
    }

    final dataCols =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (final op in ops)
          head((op[1] as BrandIdentity).label, (op[1] as BrandIdentity).color,
              (op[1] as BrandIdentity).onColor)
      ]),
      Row(children: [
        for (final op in ops) ...[
          subH('DL', (op[1] as BrandIdentity).color,
              (op[1] as BrandIdentity).onColor),
          subH('Lat', (op[1] as BrandIdentity).color,
              (op[1] as BrandIdentity).onColor),
          subH('Sig', (op[1] as BrandIdentity).color,
              (op[1] as BrandIdentity).onColor),
        ]
      ]),
      ...fb.asMap().entries.map((e) {
        final r = e.value;
        final bg = e.key.isOdd ? context.vZebra : context.vWhite;
        return Row(children: [
          for (final op in ops) ...[
            cell(read(r, op[0] as String, 'dl_speed'), bg: bg),
            cell(read(r, op[0] as String, 'latency'), bg: bg),
            cell(read(r, op[0] as String, 'signal'), bg: bg),
          ],
        ]);
      }),
    ]);

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }

  Widget _availTable(List<Map<String, dynamic>> av) {
    final keys = [
      'mean_avg_avail_pct_2g',
      'mean_avg_avail_pct_4g',
      'mean_avg_avail_pct_5g',
      'min_avail_pct_2g',
      'min_avail_pct_4g',
      'min_avail_pct_5g',
      'sites_below_sla99_4g',
      'sites_below_sla95_4g',
      'total_down_day_events_4g',
      'total_downtime_hrs_4g'
    ];
    final labels = [
      'Avg Avail 2G%',
      'Avg Avail 4G%',
      'Avg Avail 5G%',
      'Min 2G%',
      'Min 4G%',
      'Min 5G%',
      'SLA 99%',
      'SLA 95%',
      'Down Events 4G',
      'Downtime 4G (hrs)'
    ];
    return _monthlyKVTable(av, [
      for (var i = 0; i < keys.length; i++) [keys[i], labels[i], 'num']
    ]);
  }

  // ── Market Insight ──
  List<Widget> _insightSections() {
    final panels =
        (_insight!['panels'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final out = <Widget>[];
    for (final p in panels) {
      final title = p['title']?.toString() ?? '';
      final actors = (p['actors'] as List?)?.length ?? 0;
      final months = (p['months'] as List?)?.length ?? 0;
      out.add(_detailPanel(
        title,
        _insightTable(p),
        sectionKey: title,
        meta: '$actors aktor, $months bulan',
      ));
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  // ── FTTH ──
  List<Widget> _ftthSections() {
    final executive =
        (_ftth?['executive_summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final sections =
        (_ftth?['sections'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final metrics = <Map<String, dynamic>>[];
    for (final section in sections) {
      metrics.addAll(
          (section['metrics'] as List?)?.cast<Map<String, dynamic>>() ?? []);
    }
    Map<String, dynamic>? byCode(String code) {
      for (final metric in metrics) {
        if (metric['code'] == code) return metric;
      }
      return null;
    }

    num? mtd(String code) {
      final values = (byCode(code)?['ioh'] as Map?)?.cast<String, dynamic>();
      return values?['mtd'] as num?;
    }

    final out = <Widget>[
      if (executive['available'] == true)
        _catalogReport(executive, includeAllBrands: true),
      if (executive['available'] == true) const SizedBox(height: 12),
      if (executive['available'] == false &&
          executive['unavailable_reason'] != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: context.vSubtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.vRule),
          ),
          child: Text(executive['unavailable_reason'].toString(),
              style: TextStyle(fontSize: 11, color: context.vMute)),
        ),
      if (executive['available'] == false &&
          executive['unavailable_reason'] != null)
        const SizedBox(height: 12),
      PerformanceStageBars(
        title: 'FTTH Stage Values',
        subtitle:
            'SO, SA, dan PA ditampilkan sebagai nilai stage independen, tanpa conversion buatan UI',
        unitLabel: 'Orders',
        stages: [
          PerformanceStageDatum(
              label: 'Service Order (SO)', value: mtd('ftth_so')),
          PerformanceStageDatum(
              label: 'Service Active (SA)', value: mtd('ftth_sa')),
          PerformanceStageDatum(
              label: 'Permanent Active (PA)', value: mtd('ftth_pa')),
        ],
        valueFormatter: (value) => reportNumber(value),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6DF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF0D796)),
        ),
        child:
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, size: 19, color: Color(0xFF805C00)),
          SizedBox(width: 8),
          Expanded(
              child: Text(
            'Low TUR site cutoff 20% adalah klasifikasi site, bukan target atau SLA.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF604500)),
          )),
        ]),
      ),
      const SizedBox(height: 12),
    ];
    out.addAll(_comprehensiveSections(_ftth));
    return out;
  }

  String _intFmt(dynamic v) => reportNumber(v);

  Widget _ftthCountTable(Map<String, dynamic> s) {
    final rows = (s['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final columns = (s['columns'] as List?)?.cast<String>() ?? ['Count'];
    if (rows.isEmpty) {
      return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    }
    return ReportAllDataTable<Map<String, dynamic>>(
      semanticLabel: '${s['title'] ?? 'FTTH'} all rows',
      rows: rows,
      layoutPolicy: ReportTableLayoutPolicy.horizontal,
      storageKey: 'ftth-count-${s['title']}-${columns.join('|')}',
      columns: [
        ReportTableColumn(
          label: 'Item',
          width: 180,
          value: (row) => row['label'] ?? row['actor'],
        ),
        for (var index = 0; index < columns.length; index++)
          ReportTableColumn(
            label: columns[index],
            numeric: true,
            value: (row) {
              final cells = (row['cells'] as List?) ?? [row['value']];
              return index < cells.length ? cells[index] : null;
            },
            formatter: _intFmt,
          ),
      ],
    );
  }

  Widget _ftthHierarchyTable(Map<String, dynamic> s) {
    final rows = (s['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final columns =
        (s['columns'] as List?)?.cast<String>() ?? ['SO', 'SA', 'PA'];
    if (rows.isEmpty) {
      return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Ketuk baris untuk drilldown · urut MTD',
          style: TextStyle(fontSize: 10, color: context.vMute)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
            child: Text('SM / TL / AE',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: context.vMute))),
        ...columns.map((c) => SizedBox(
            width: 56,
            child: Text(c,
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: IOH.teal600)))),
      ]),
      const SizedBox(height: 4),
      _FtthHierTree(nodes: rows, columns: columns),
    ]);
  }

  /// Industry and the IOH aggregate are the two reference rows in a panel.
  bool _isEmphasizedActor(Map<String, dynamic> actor) {
    final name = actor['actor']?.toString().toUpperCase();
    return name == 'INDUSTRY' || name == 'IOH';
  }

  Widget _insightTable(Map<String, dynamic> p) {
    final actors = (p['actors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final months = (p['months'] as List?)?.cast<String>() ?? [];
    if (actors.isEmpty || months.isEmpty) {
      return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    }

    final kind = p['kind'].toString();
    final isPct = kind.startsWith('pct');
    // A churn panel reads the opposite way to a gross add panel, so polarity
    // comes from the panel title rather than the sign alone.
    final polarity = reportPolarityFor(p['title']?.toString() ?? '');
    final colW = 84.0;
    final nameW = 110.0;

    final nameCol =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: nameW,
          height: 34,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Operator',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.vMute))),
      for (var i = 0; i < actors.length; i++)
        Container(
            width: nameW,
            height: 42,
            color: i.isOdd ? context.vZebra : context.vWhite,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Text(actors[i]['actor'].toString(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: _isEmphasizedActor(actors[i])
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: Brands.colorOf(actors[i]['actor']?.toString())))),
    ]);

    Widget head(String t) => Container(
        width: colW,
        height: 34,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: context.vMute)));

    final dataCols =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [for (final m in months) head(m)]),
      for (var i = 0; i < actors.length; i++)
        Container(
            color: i.isOdd ? context.vZebra : context.vWhite,
            height: 42,
            child: Row(children: [
              for (final h in (actors[i]['history'] as List)
                  .cast<Map<String, dynamic>>())
                Container(
                  width: colW,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  alignment: Alignment.centerRight,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            h['value'] == null
                                ? kReportNotAvailable
                                : (isPct
                                    ? _pct(h['value'])
                                    : reportNumber(h['value'])),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: _isEmphasizedActor(actors[i])
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: context.vInk,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                        if (h['growth'] != null)
                          Text(
                              reportGrowth(h['growth'],
                                  suffix: isPct ? 'pp' : '%'),
                              style: TextStyle(
                                  fontSize: 9,
                                  color: reportGrowthColor(context, h['growth'],
                                          polarity: polarity) ??
                                      context.vMute)),
                      ]),
                ),
            ])),
    ]);

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }
}

class _SummaryMetric {
  final String code;
  final String label;
  final String value;
  final double? delta;
  final String deltaUnit;

  const _SummaryMetric({
    required this.code,
    required this.label,
    required this.value,
    required this.delta,
    this.deltaUnit = '%',
  });
}

class _PinnedContextDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double extent;

  const _PinnedContextDelegate({required this.child, required this.extent});

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: context.vPanel.withValues(alpha: 0.96),
      child: Align(alignment: Alignment.topCenter, child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedContextDelegate oldDelegate) {
    return oldDelegate.extent != extent || oldDelegate.child != child;
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

  String _intFmt(dynamic v) => reportNumber(v);

  List<Widget> _rows(
      List<Map<String, dynamic>> nodes, int depth, String prefix) {
    final out = <Widget>[];
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final key = '$prefix/$i';
      final kids = (n['children'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final hasKids = kids.isNotEmpty;
      final isOpen = _open.contains(key);
      final cells = (n['cells'] as List?) ?? [];
      final bg = depth == 0
          ? context.vWhite
          : depth == 1
              ? context.vZebra
              : context.vPanel;
      out.add(GestureDetector(
        onTap: hasKids
            ? () => setState(() {
                  isOpen ? _open.remove(key) : _open.add(key);
                })
            : null,
        child: Container(
          color: bg,
          padding: EdgeInsets.only(left: 4 + depth * 16, top: 7, bottom: 7),
          child: Row(children: [
            Expanded(
                child: Text(
              '${hasKids ? (isOpen ? '▾ ' : '▸ ') : depth > 0 ? '• ' : ''}${n['label'] ?? ''}',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: depth == 0
                      ? FontWeight.w700
                      : depth == 1
                          ? FontWeight.w600
                          : FontWeight.w400,
                  color: context.vInk),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )),
            ...List.generate(
                widget.columns.length,
                (ci) => SizedBox(
                    width: 56,
                    child: Text(_intFmt(ci < cells.length ? cells[ci] : null),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: ci == widget.columns.length - 1
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: context.vInk,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])))),
          ]),
        ),
      ));
      if (isOpen && hasKids) out.addAll(_rows(kids, depth + 1, key));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _rows(widget.nodes, 0, 'r'));
  }
}

typedef _ReportControlsBuilder = Widget Function(
  VoidCallback refresh,
  VoidCallback openScopeSearch,
);

class _LiveReportFilterSheet extends StatefulWidget {
  final _ReportControlsBuilder controlsBuilder;
  final List<String> Function() options;
  final String Function() selected;
  final String Function() scopeTitle;
  final ValueChanged<String> onScopePick;

  const _LiveReportFilterSheet({
    required this.controlsBuilder,
    required this.options,
    required this.selected,
    required this.scopeTitle,
    required this.onScopePick,
  });

  @override
  State<_LiveReportFilterSheet> createState() => _LiveReportFilterSheetState();
}

class _LiveReportFilterSheetState extends State<_LiveReportFilterSheet> {
  bool _searchScope = false;
  String _query = '';

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options();
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? options
        : options.where((item) => item.toLowerCase().contains(query)).toList();
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.vRule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
              child: Row(
                children: [
                  if (_searchScope)
                    IconButton(
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      tooltip: 'Kembali ke filter',
                      onPressed: () => setState(() {
                        _searchScope = false;
                        _query = '';
                      }),
                      icon: const Icon(Icons.arrow_back),
                    ),
                  Expanded(
                    child: Text(
                      _searchScope
                          ? 'Pilih ${widget.scopeTitle()}'
                          : 'Filter Performance Outlook',
                      softWrap: true,
                      style: TextStyle(
                        color: context.vInk,
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: context.vRule),
            if (!_searchScope)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: widget.controlsBuilder(
                      _refresh,
                      () => setState(() => _searchScope = true),
                    ),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: TextField(
                  autofocus: true,
                  style: TextStyle(fontSize: 13, color: context.vInk),
                  decoration: InputDecoration(
                    hintText: 'Ketik untuk mencari...',
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: context.vMute),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Tidak ada hasil',
                          style: TextStyle(color: context.vMute),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: context.vRule),
                        itemBuilder: (context, index) {
                          final option = filtered[index];
                          final active = option == widget.selected();
                          return ListTile(
                            minVerticalPadding: 8,
                            title: Text(
                              option,
                              softWrap: true,
                              style: TextStyle(
                                color: active ? IOH.teal600 : context.vInk,
                                fontSize: 13,
                                fontWeight:
                                    active ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                            trailing: active
                                ? const Icon(Icons.check,
                                    color: IOH.teal600, size: 18)
                                : null,
                            onTap: () {
                              widget.onScopePick(option);
                              setState(() {
                                _searchScope = false;
                                _query = '';
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Bottom-sheet picker with a search field that filters a long option list.
class _ScopeSearchSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onPick;
  const _ScopeSearchSheet(
      {required this.title,
      required this.options,
      required this.selected,
      required this.onPick});
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
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            const SizedBox(height: 10),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: context.vRule,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Text('Pilih ${widget.title}',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.vInk)),
                const Spacer(),
                Text('${filtered.length}',
                    style: TextStyle(fontSize: 11, color: context.vMute)),
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
                  prefixIcon:
                      Icon(Icons.search, size: 18, color: context.vMute),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.vRule)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.vRule)),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('Tidak ada hasil',
                          style: TextStyle(fontSize: 12, color: context.vMute)))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: context.vRule),
                      itemBuilder: (_, i) {
                        final o = filtered[i];
                        final sel = o == widget.selected;
                        return ListTile(
                          dense: true,
                          title: Text(o,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      sel ? FontWeight.w700 : FontWeight.w400,
                                  color: sel ? IOH.teal600 : context.vInk)),
                          trailing: sel
                              ? const Icon(Icons.check,
                                  size: 18, color: IOH.teal600)
                              : null,
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
