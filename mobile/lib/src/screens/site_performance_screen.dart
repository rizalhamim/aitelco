import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../format/report_format.dart';
import '../theme.dart';
import '../widgets/report_ui.dart';
import 'location_sheet.dart' show getCurrentCoord;

class SitePerformanceScreen extends StatefulWidget {
  const SitePerformanceScreen({super.key});
  @override
  State<SitePerformanceScreen> createState() => _SitePerformanceScreenState();
}

class _SitePerformanceScreenState extends State<SitePerformanceScreen> {
  String _mode = 'coordinate'; // coordinate | search
  final _searchCtl = TextEditingController();
  List<Map<String, dynamic>> _list = [];
  bool _loadingList = false;
  Map<String, dynamic>? _detail;
  bool _loadingDetail = false;
  String _selected = '';
  String _brand = 'ioh'; // ioh | im3 | 3id
  String _view = 'snapshot'; // snapshot | fullmonth
  String _err = '';
  final _cache = <String, Map<String, dynamic>>{}; // 'siteId|brand' -> detail
  final _expandedChapters = <String>{'commercial'};
  Timer? _searchDebounce;
  int _listRequestGeneration = 0;
  int _detailRequestGeneration = 0;

  static const _metricLabels = {
    'rev_prepaid': 'Revenue Prepaid',
    'rev_vsd': 'Revenue VSD',
    'rev_nonvsd': 'Revenue Non-VSD',
    'rev_data': 'Revenue Data',
    'rev_voice': 'Revenue Voice',
    'rev_sms': 'Revenue SMS',
    'rev_trade': 'Revenue Trade',
    'rev_organic': 'Revenue Organic',
    'rev_nontrade': 'Revenue Non-Trade',
    'rev_acquisition_m0': 'Revenue Acq M0',
    'subs_rgu_90d': 'RGU 90D',
    'subs_rgu_30d': 'RGU 30D',
    'subs_gross_add': 'Gross Add',
    'net_add_90d': 'Net Add 90D',
    'net_add_30d': 'Net Add 30D',
    'gross_churn_90d': 'Gross Churn 90D',
    'gross_churn_30d': 'Gross Churn 30D',
    'churn_back_90d': 'Churn Back 90D',
    'subs_net_churn_90d': 'Net Churn 90D',
    'subs_vlr_30d': 'VLR 30D',
    'subs_avg_vlr_daily': 'VLR Daily',
    'datauu': 'Data Users',
    'datauu30d': 'Data Users 30D',
    'usg_data_gb': 'Usage Data (GB)',
    'usg_og_voice_min': 'Usage Voice (Min)',
    'usg_og_sms_cnt': 'Usage SMS',
    'ga_m1s': 'GA M1S',
    'ga_m2s': 'GA M2S',
    'ga_p1m': 'GA P1M',
    'ga_p2m': 'GA P2M',
    'subs_hvc': 'HVC Subs',
    'subs_hvc_stay': 'HVC Stay',
    'subs_hvc_in': 'HVC In',
    'subs_hvc_out': 'HVC Out',
  };
  static const List<List<String>> _networkRows = [
    ['data_uu30_all', 'Data UU (All)', 'num'],
    ['data_uu30_dev_2g', 'Data UU Dev 2G', 'num'],
    ['data_uu30_dev_4g', 'Data UU Dev 4G', 'num'],
    ['data_uu30_dev_5g', 'Data UU Dev 5G', 'num'],
    ['data_uu30_traffic_2g', 'Data UU Traffic 2G', 'num'],
    ['data_uu30_traffic_4g', 'Data UU Traffic 4G', 'num'],
    ['data_uu30_traffic_5g', 'Data UU Traffic 5G', 'num'],
    ['traffic_2g', 'Traffic 2G', 'num'],
    ['traffic_4g', 'Traffic 4G', 'num'],
    ['traffic_5g', 'Traffic 5G', 'num'],
    ['traffic_total', 'Traffic Total', 'num'],
    ['dev_all', 'Device Total', 'num'],
    ['dev5g_total', 'Device 5G', 'num'],
    ['dev5g_with_traffic', 'Device 5G w/ Traffic', 'num'],
    ['dev5g_pct', 'Device 5G % vs Total', 'pct'],
    ['dev5g_traffic_pct', 'Dev 5G w/Traffic % vs Dev 5G', 'pct'],
  ];
  static const List<List<String>> _availabilityRows = [
    ['avg_avail_pct_2g', 'Availability 2G %', 'pct'],
    ['avg_avail_pct_4g', 'Availability 4G %', 'pct'],
    ['avg_avail_pct_5g', 'Availability 5G %', 'pct'],
    ['days_down_2g', 'Days Down 2G', 'num'],
    ['days_down_4g', 'Days Down 4G', 'num'],
    ['days_down_5g', 'Days Down 5G', 'num'],
  ];
  static const List<List<String>> _fwaRows = [
    ['rev_fwa_total', 'Revenue FWA Total', 'mn'],
    ['rev_fwa_pack', 'Revenue FWA Pack', 'mn'],
    ['rev_fwa_sim', 'Revenue FWA SIM', 'mn'],
    ['rev_fwa_regular', 'Revenue FWA Regular', 'mn'],
    ['rev_fwa_non_broadband', 'Revenue FWA Non-BB', 'mn'],
    ['fwa_rgu90', 'FWA RGU 90D', 'num'],
    ['fwa_rgu_ga', 'FWA Gross Add', 'num'],
    ['fwa_grosschurn90', 'FWA Gross Churn 90D', 'num'],
    ['fwa_churnback90', 'FWA Churn Back 90D', 'num'],
    ['fwa_net_add_90_closing', 'FWA Net Add 90D', 'num'],
    ['fwa_pack_hits', 'FWA Pack Hits', 'num'],
    ['vlr_fwa_less_90d', 'VLR FWA <90D', 'num'],
    ['vlr_fwa_91_180d', 'VLR FWA 91-180D', 'num'],
    ['vlr_fwa_above_181d', 'VLR FWA >181D', 'num'],
  ];
  bool _isRev(String c) => c.startsWith('rev_') || c == 'usg_data_gb';

  /// Adaptive magnitude for money-like values: plain below a million, then Mn,
  /// then Bn. A small revenue must never be shown as `0,0 Bn`.
  String _mn(dynamic v) => reportMagnitude(v, decimals: 1, useThousand: false);

  String _num(dynamic v) => reportNumber(v);

  @override
  void initState() {
    super.initState();
    // Deep-link: when opened from Map Query with a site_id argument, auto-open it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      String? sid;
      if (args is String) {
        sid = args;
      } else if (args is Map && args['site_id'] != null) {
        sid = args['site_id'].toString();
      }
      if (sid != null && sid.isNotEmpty) {
        setState(() {
          _mode = 'search';
          _searchCtl.text = sid!;
        });
        _open(sid);
      }
    });
  }

  Future<void> _locate() async {
    _searchDebounce?.cancel();
    final requestGeneration = ++_listRequestGeneration;
    setState(() {
      _err = '';
      _list = [];
      _loadingList = true;
    });
    final c = await getCurrentCoord(context);
    if (c == null) {
      if (mounted && requestGeneration == _listRequestGeneration) {
        setState(() => _loadingList = false);
      }
      return;
    }
    try {
      final sites = await ApiClient.siteNearest(c.$1, c.$2);
      if (mounted && requestGeneration == _listRequestGeneration) {
        setState(() => _list = sites);
      }
    } catch (e) {
      if (mounted && requestGeneration == _listRequestGeneration) {
        setState(() => _err = e.toString());
      }
    }
    if (mounted && requestGeneration == _listRequestGeneration) {
      setState(() => _loadingList = false);
    }
  }

  Future<void> _search(String q) async {
    final requestGeneration = _listRequestGeneration;
    if (q.trim().length < 2) {
      if (mounted && requestGeneration == _listRequestGeneration) {
        setState(() {
          _list = [];
          _loadingList = false;
        });
      }
      return;
    }
    try {
      final sites = await ApiClient.siteSearch(q.trim());
      if (mounted && requestGeneration == _listRequestGeneration) {
        setState(() {
          _list = sites;
          _err = '';
        });
      }
    } catch (e) {
      if (mounted && requestGeneration == _listRequestGeneration) {
        setState(() => _err = e.toString());
      }
    }
    if (mounted && requestGeneration == _listRequestGeneration) {
      setState(() => _loadingList = false);
    }
  }

  void _queueSearch(String q) {
    _searchDebounce?.cancel();
    ++_listRequestGeneration;
    final clean = q.trim();
    if (clean.length < 2) {
      setState(() {
        _list = [];
        _loadingList = false;
        _err = '';
      });
      return;
    }
    setState(() {
      _loadingList = true;
      _err = '';
    });
    _searchDebounce =
        Timer(const Duration(milliseconds: 350), () => _search(clean));
  }

  Future<void> _open(String sid) async {
    final requestGeneration = ++_detailRequestGeneration;
    final requestedBrand = _brand;
    final siteChanged = _selected != sid;
    setState(() {
      _selected = sid;
      if (siteChanged) {
        _expandedChapters
          ..clear()
          ..add('commercial');
      }
    });
    final hit = _cache['$sid|$requestedBrand'];
    if (hit != null) {
      setState(() {
        _detail = hit;
        _loadingDetail = false;
      });
    } else {
      setState(() {
        _loadingDetail = true;
        _detail = null;
      });
    }
    // Fetch the active brand first, then prefetch the others into cache.
    final order = <String>[
      requestedBrand,
      ...['ioh', 'im3', '3id'].where((b) => b != requestedBrand)
    ];
    for (final b in order) {
      final key = '$sid|$b';
      if (_cache.containsKey(key)) {
        if (b == requestedBrand &&
            mounted &&
            requestGeneration == _detailRequestGeneration &&
            _selected == sid &&
            _brand == requestedBrand) {
          setState(() {
            _detail = _cache[key];
            _loadingDetail = false;
          });
        }
        continue;
      }
      try {
        final d = await ApiClient.siteDetail(sid, brand: b);
        _cache[key] = d;
        if (b == requestedBrand &&
            mounted &&
            requestGeneration == _detailRequestGeneration &&
            _selected == sid &&
            _brand == requestedBrand) {
          setState(() {
            _detail = d;
            _loadingDetail = false;
          });
        }
      } catch (e) {
        if (b == requestedBrand &&
            mounted &&
            requestGeneration == _detailRequestGeneration &&
            _selected == sid &&
            _brand == requestedBrand) {
          setState(() {
            _detail = {'error': e.toString()};
            _loadingDetail = false;
          });
        }
      }
    }
  }

  void _selectBrand(String b) {
    setState(() => _brand = b);
    final hit = _cache['$_selected|$b'];
    if (hit != null) {
      ++_detailRequestGeneration;
      setState(() {
        _detail = hit;
        _loadingDetail = false;
      });
    } else {
      _open(_selected);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vPanel,
      appBar: AppBar(title: const Text('Site Performance')),
      body: _detail != null || _loadingDetail
          ? Column(children: [
              _siteContextBar(),
              Expanded(child: _detailView()),
            ])
          : ListView(padding: const EdgeInsets.all(12), children: [
              _modeToggle(),
              const SizedBox(height: 8),
              if (_mode == 'coordinate')
                ElevatedButton.icon(
                  onPressed: _loadingList ? null : _locate,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: IOH.teal500,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.my_location, size: 18),
                  label:
                      Text(_loadingList ? 'Mencari…' : 'Gunakan Lokasi Saya'),
                )
              else
                TextField(
                  controller: _searchCtl,
                  onChanged: _queueSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Masukkan Site ID atau Site Name…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    filled: true,
                    fillColor: context.vWhite,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.vRule)),
                  ),
                ),
              if (_err.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_err,
                        style:
                            const TextStyle(color: IOH.danger, fontSize: 12))),
              const SizedBox(height: 12),
              if (_loadingList)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(color: IOH.teal500)))
              else
                ..._list.map((s) => _siteCard(s)),
            ]),
    );
  }

  Widget _siteContextBar() {
    final attrs =
        (_detail?['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
    final siteName = (attrs['site_name'] ?? _selected).toString();
    final siteId = (attrs['site_id'] ?? _selected).toString();
    final month = _detail?['month_id']?.toString();
    return Material(
      color: context.vWhite,
      elevation: 1,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: Row(children: [
            Semantics(
              button: true,
              label: 'Kembali ke daftar site',
              child: IconButton(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () {
                  ++_detailRequestGeneration;
                  setState(() {
                    _detail = null;
                    _loadingDetail = false;
                    _selected = '';
                  });
                },
                icon: const Icon(Icons.arrow_back, color: IOH.teal600),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(siteName,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.vInk),
                    maxLines: 2),
                Text(
                    '$siteId · ${_brand.toUpperCase()}${month == null ? '' : ' · $month'} · ${_view == 'snapshot' ? 'Snapshot MTD' : 'Full Month'}',
                    style: TextStyle(fontSize: 10.5, color: context.vMute),
                    maxLines: 2),
              ],
            )),
          ]),
        ),
      ),
    );
  }

  Widget _modeToggle() {
    return ReportSegmentedControl<String>(
      value: _mode,
      equalWidth: true,
      semanticLabel: 'Mode pencarian site',
      onChanged: _selectSiteMode,
      items: const [
        ReportSegmentItem(
          value: 'coordinate',
          label: 'Coordinate',
          icon: Icons.place_outlined,
        ),
        ReportSegmentItem(
          value: 'search',
          label: 'Site Search',
          icon: Icons.search,
        ),
      ],
    );
  }

  void _selectSiteMode(String key) {
    if (_mode == key) return;
    _searchDebounce?.cancel();
    ++_listRequestGeneration;
    ++_detailRequestGeneration;
    setState(() {
      _mode = key;
      _list = [];
      _detail = null;
      _selected = '';
      _err = '';
    });
  }

  Widget _siteCard(Map<String, dynamic> s) {
    final active = _selected == s['site_id'];
    final title = (s['site_name'] ?? s['site_id'] ?? '').toString();
    final detail =
        '${s['site_id']}${s['distance_km'] != null ? ' · ${s['distance_km']} km' : ''} · ${s['branch'] ?? ''}';
    return Semantics(
      button: true,
      selected: active,
      label: '$title, $detail',
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: active ? IOH.teal500.withValues(alpha: 0.1) : context.vWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: active ? IOH.teal500 : context.vRule)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(s['site_id'].toString()),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: context.vInk)),
                      Text(detail,
                          style: TextStyle(fontSize: 11, color: context.vMute)),
                      if ((s['kecamatan'] ?? '').toString().isNotEmpty)
                        Text(
                            '${s['kecamatan']}${(s['kabupaten'] ?? '').toString().isEmpty ? '' : ', ${s['kabupaten']}'}',
                            style: TextStyle(
                                fontSize: 10.5, color: context.vMute)),
                    ])),
                Icon(Icons.chevron_right, color: context.vMute),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Detail ──
  Widget _detailView() {
    if (_loadingDetail) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        const LinearProgressIndicator(color: IOH.teal500),
        const SizedBox(height: 18),
        Text('Memuat diagnostic site $_selected…',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.vInk)),
        const SizedBox(height: 6),
        Text('Menyiapkan revenue, subscriber, network, channel, dan portfolio.',
            style: TextStyle(fontSize: 12, color: context.vMute)),
      ]);
    }
    final d = _detail!;
    if (d['error'] != null) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        Icon(Icons.error_outline,
            size: 40, color: IOH.danger.withValues(alpha: 0.85)),
        const SizedBox(height: 12),
        Text('Detail site belum dapat dimuat',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: context.vInk)),
        const SizedBox(height: 6),
        Text(d['error'].toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: IOH.danger)),
        const SizedBox(height: 16),
        Center(
            child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                    onPressed: () => _open(_selected),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba lagi')))),
      ]);
    }
    final a = (d['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
    final fn = (d['funnel'] as Map?)?.cast<String, dynamic>() ?? {};
    String str(dynamic v) => (v == null || v == '') ? 'N/A' : v.toString();
    final hasGa = ((d['ga_channels'] as List?) ?? []).isNotEmpty;
    final hasNetwork = d['network']?['mtd'] != null;
    final hasAvailability = d['availability']?['mtd'] != null;
    final hasFwa = d['fwa']?['mtd'] != null;
    final fwaSummary =
        (d['fwa_summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final hasFwaSummary = fwaSummary['available'] == true;
    final hasChannelHistory =
        ((d['channel_history'] as List?) ?? []).isNotEmpty;

    return ListView(padding: const EdgeInsets.all(12), children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: context.vWhite,
            borderRadius: BorderRadius.circular(12),
            border:
                const Border(top: BorderSide(color: IOH.teal500, width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(str(a['site_name']),
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: context.vInk)),
          Text(str(a['site_id']),
              style: TextStyle(fontSize: 12, color: context.vMute)),
          const SizedBox(height: 6),
          Text(
              '${str(a['site_type'])} · ${str(a['category'])} · ${str(a['kecamatan'])}, ${str(a['kabupaten'])}',
              style: TextStyle(fontSize: 12, color: context.vMute)),
          Text(
              'Branch ${str(a['branch'])} · MC ${str(a['micro_cluster'])} · Region ${str(a['region'])} · Bulan ${str(d['month_id'])}',
              style: TextStyle(fontSize: 11, color: context.vMute)),
        ]),
      ),
      const SizedBox(height: 8),
      // brand + view tabs
      _tabsRow(),
      const SizedBox(height: 8),
      _diagnosticSummary(d),
      const SizedBox(height: 8),
      _chapterControls(),
      const SizedBox(height: 8),
      if (_view == 'fullmonth') ...[
        _chapter(
            'commercial',
            'Commercial Trends',
            'Revenue, subscriber, usage, dan channel untuk bulan penuh',
            () => [
                  _panel(
                      'Revenue · Full Month',
                      _monthlyTable(
                          (d['history'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [],
                          const [
                            'rev_prepaid',
                            'rev_vsd',
                            'rev_nonvsd',
                            'rev_data',
                            'rev_voice',
                            'rev_sms',
                            'rev_trade',
                            'rev_organic',
                            'rev_nontrade',
                            'rev_acquisition_m0'
                          ])),
                  const SizedBox(height: 12),
                  _panel(
                      'Subscriber & Usage · Full Month',
                      _monthlyTable(
                          (d['history'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [],
                          const [
                            'subs_rgu_90d',
                            'subs_rgu_30d',
                            'subs_gross_add',
                            'net_add_90d',
                            'net_add_30d',
                            'gross_churn_90d',
                            'gross_churn_30d',
                            'churn_back_90d',
                            'subs_net_churn_90d',
                            'subs_vlr_30d',
                            'subs_avg_vlr_daily',
                            'datauu',
                            'datauu30d',
                            'subs_hvc',
                            'subs_hvc_stay',
                            'subs_hvc_in',
                            'subs_hvc_out',
                            'usg_data_gb',
                            'usg_og_voice_min',
                            'usg_og_sms_cnt'
                          ])),
                  if (hasChannelHistory) const SizedBox(height: 12),
                  if (hasChannelHistory)
                    _panel(
                        'Revenue by Channel · Full Month',
                        _monthlyChannelTable((d['channel_history'] as List)
                            .cast<Map<String, dynamic>>())),
                ]),
        const SizedBox(height: 10),
        _chapter(
            'network',
            'Network & FWA',
            'Network, availability, dan FWA dalam histori bulan penuh',
            () => [
                  if (d['network']?['history'] != null)
                    _panel(
                        'Network (Data UU · Traffic · Device) · Full Month',
                        _monthlyKVTable(
                            (d['network']['history'] as List)
                                .cast<Map<String, dynamic>>(),
                            _networkRows)),
                  if (d['network']?['history'] != null &&
                      d['availability']?['history'] != null)
                    const SizedBox(height: 12),
                  if (d['availability']?['history'] != null)
                    _panel(
                        'Availability · Full Month',
                        _monthlyKVTable(
                            (d['availability']['history'] as List)
                                .cast<Map<String, dynamic>>(),
                            _availabilityRows)),
                  if (d['fwa']?['history'] != null) const SizedBox(height: 12),
                  if (hasFwaSummary)
                    _panel('FWA Complete · 64 Metrics · Full Month',
                        _fwaSummaryHistory(fwaSummary)),
                  if (hasFwaSummary && d['fwa']?['history'] != null)
                    const SizedBox(height: 12),
                  if (d['fwa']?['history'] != null)
                    _panel(
                        'FWA Legacy · Full Month',
                        _monthlyKVTable(
                            (d['fwa']['history'] as List)
                                .cast<Map<String, dynamic>>(),
                            _fwaRows)),
                ]),
      ] else ...[
        _chapter(
            'commercial',
            'Commercial Performance',
            'Revenue, subscriber, acquisition, dan retention',
            () => [
                  _panel(
                      'Revenue (LMTD · MTD · Growth)',
                      _metricTable(d, const [
                        'rev_prepaid',
                        'rev_vsd',
                        'rev_nonvsd',
                        'rev_data',
                        'rev_voice',
                        'rev_sms',
                        'rev_trade',
                        'rev_organic',
                        'rev_nontrade',
                        'rev_acquisition_m0'
                      ])),
                  const SizedBox(height: 12),
                  _panel(
                      'Subscriber & Usage (LMTD · MTD · Growth)',
                      _metricTable(d, const [
                        'subs_rgu_90d',
                        'subs_rgu_30d',
                        'subs_gross_add',
                        'net_add_90d',
                        'net_add_30d',
                        'gross_churn_90d',
                        'gross_churn_30d',
                        'churn_back_90d',
                        'subs_net_churn_90d',
                        'subs_vlr_30d',
                        'subs_avg_vlr_daily',
                        'datauu',
                        'datauu30d',
                        'subs_hvc',
                        'subs_hvc_stay',
                        'subs_hvc_in',
                        'subs_hvc_out',
                        'usg_data_gb',
                        'usg_og_voice_min',
                        'usg_og_sms_cnt'
                      ])),
                  if (hasGa) const SizedBox(height: 12),
                  if (hasGa)
                    _panel(
                        'Acquisition by Channel (GA)',
                        _gaChannelBars((d['ga_channels'] as List)
                            .cast<Map<String, dynamic>>())),
                  const SizedBox(height: 12),
                  _panel('Acquisition Stage Counts', _stageBars(fn)),
                ]),
        const SizedBox(height: 10),
        _chapter(
            'network',
            'Network & FWA',
            'Network, availability, dan FWA dengan polaritas metric',
            () => [
                  if (hasNetwork)
                    _panel(
                        'Network · Data UU · Traffic · Device (LMTD · MTD · Growth)',
                        _kvLmtdTable(
                            (d['network'] as Map).cast<String, dynamic>(),
                            _networkRows)),
                  if (hasNetwork && hasAvailability) const SizedBox(height: 12),
                  if (hasAvailability)
                    _panel(
                        'Availability (LMTD · MTD · Growth)',
                        _kvLmtdTable(
                            (d['availability'] as Map).cast<String, dynamic>(),
                            _availabilityRows)),
                  if (hasFwaSummary) const SizedBox(height: 12),
                  if (hasFwaSummary)
                    _panel('FWA Complete · MTD · LMTD · LYTD',
                        _fwaSummarySnapshot(fwaSummary)),
                  if (hasFwa) const SizedBox(height: 12),
                  if (hasFwa)
                    _panel(
                        'FWA Legacy (LMTD · MTD · Growth)',
                        _kvLmtdTable((d['fwa'] as Map).cast<String, dynamic>(),
                            _fwaRows)),
                ]),
        const SizedBox(height: 10),
        _chapter(
            'portfolio',
            'Revenue Mix & Portfolio',
            'Channel, product, price, quota, dan masa aktif',
            () => [
                  _panel(
                      'Revenue by Channel (LMTD · MTD · Growth)',
                      _channelMetricTable((d['channel_metrics'] as List?)
                              ?.cast<Map<String, dynamic>>() ??
                          [])),
                  const SizedBox(height: 12),
                  _panel(
                      'Revenue by Channel · Monthly',
                      _channelHistoryTable((d['channel_history'] as List?)
                              ?.cast<Map<String, dynamic>>() ??
                          [])),
                  const SizedBox(height: 12),
                  _panel(
                      'Channel Detail',
                      _list2(
                          (d['channels'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [],
                          (c) => [
                                '${c['channel']} · ${c['detail']}',
                                _mn(c['revenue'])
                              ])),
                  const SizedBox(height: 12),
                  _panel(
                      'Top Products',
                      _list2(
                          (d['top_products'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [],
                          (t) => [
                                '${t['product']}${(t['family'] ?? '').toString().isEmpty ? '' : ' · ${t['family']}'}',
                                '${_mn(t['revenue'])} · ${_num(t['hit'])} hit'
                              ])),
                  const SizedBox(height: 12),
                  _panel(
                      'Price Slab',
                      _list2(
                          (d['price_slabs'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [],
                          (s) => [
                                s['slab'].toString(),
                                '${_mn(s['revenue'])} · ${_num(s['hit'])} hit'
                              ])),
                  const SizedBox(height: 12),
                  _panel(
                      'Slab Kuota',
                      _list2(
                          (d['quota_slabs'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [],
                          (s) => [s['slab'].toString(), _mn(s['revenue'])])),
                  const SizedBox(height: 12),
                  _panel(
                      'Slab Masa Aktif',
                      _list2(
                          (d['validity_slabs'] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              [],
                          (s) => [s['slab'].toString(), _mn(s['revenue'])])),
                ]),
      ],
      const SizedBox(height: 10),
      _chapter(
          'attributes',
          'Complete Site Attributes',
          '${a.length} backend fields, all reachable',
          () => [_attributesTable(a)]),
      const SizedBox(height: 24),
    ]);
  }

  Widget _diagnosticSummary(Map<String, dynamic> d) {
    final metrics = (d['metrics'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final byCode = {for (final m in metrics) m['code'].toString(): m};
    const codes = [
      'rev_prepaid',
      'subs_rgu_90d',
      'subs_gross_add',
      'gross_churn_90d'
    ];
    final cards = [
      for (final code in codes)
        if (byCode[code] != null) _summaryMetricCard(code, byCode[code]!)
    ];
    final history = (d['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return _panel(
        'Diagnostic Overview',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CURRENT MTD SNAPSHOT',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: context.vMute)),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final oneColumn = constraints.maxWidth < 320 || textScale >= 1.6;
            final cardWidth = oneColumn
                ? constraints.maxWidth
                : (constraints.maxWidth - 8) / 2;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final card in cards) SizedBox(width: cardWidth, child: card)
            ]);
          }),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: context.vRule),
            const SizedBox(height: 12),
            Text('REVENUE PREPAID · CLOSED MONTHS',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: context.vMute)),
            const SizedBox(height: 4),
            Text(
                'Skala bar dimulai dari 0. Bulan MTD aktif tidak dicampur ke histori full month.',
                style: TextStyle(fontSize: 10.5, color: context.vMute)),
            const SizedBox(height: 10),
            _revenueHistoryBars(history),
          ],
        ]));
  }

  Widget _summaryMetricCard(String code, Map<String, dynamic> metric) {
    final growth = metric['growth'] as num?;
    final inverse =
        RegExp(r'churn|days_down|downtime|latency', caseSensitive: false)
            .hasMatch(code);
    final favorable = growth == null || growth == 0
        ? null
        : (inverse ? growth < 0 : growth > 0);
    final color = favorable == null
        ? context.vMute
        : favorable
            ? IOH.teal600
            : IOH.danger;
    final value = _isRev(code) ? _mn(metric['mtd']) : _num(metric['mtd']);
    final prior = _isRev(code) ? _mn(metric['lmtd']) : _num(metric['lmtd']);
    final growthText = growth == null
        ? 'Comparison unavailable'
        : reportGrowth(growth);
    final semantic =
        '${_metricLabels[code] ?? code}, MTD $value, LMTD $prior, $growthText${favorable == null ? '' : favorable ? ', favorable' : ', unfavorable'}';
    return Semantics(
      label: semantic,
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: context.vSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: color, width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_metricLabels[code] ?? code,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.vMute)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.vInk)),
          const SizedBox(height: 3),
          Text('$growthText · LMTD $prior',
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  Widget _revenueHistoryBars(List<Map<String, dynamic>> history) {
    final values =
        history.map((h) => (h['rev_prepaid'] as num?)?.toDouble()).toList();
    final finite =
        values.whereType<double>().where((v) => v.isFinite && v >= 0).toList();
    if (finite.isEmpty) {
      return Text('Tidak ada histori revenue.',
          style: TextStyle(color: context.vMute));
    }
    final peak = finite.fold<double>(0, math.max);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    final cellWidth = 76.0 * textScale;
    final semantics = history.asMap().entries.map((e) {
      final value = values[e.key];
      return '${e.value['month_id']}: ${value == null ? 'tidak tersedia' : _mn(value)}';
    }).join(', ');
    return Semantics(
      label: 'Revenue Prepaid per closed month. $semantics',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < history.length; i++)
            SizedBox(
              width: cellWidth,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(values[i] == null ? 'N/A' : _mn(values[i]),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: context.vInk)),
                const SizedBox(height: 4),
                SizedBox(
                    height: 74,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: values[i] == null
                          ? Container(
                              width: 22, height: 4, color: context.vRule)
                          : Container(
                              width: 28,
                              height: peak <= 0
                                  ? 2
                                  : math
                                      .max(2.0, 74.0 * values[i]! / peak)
                                      .toDouble(),
                              decoration: const BoxDecoration(
                                  color: IOH.teal500,
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(5))),
                            ),
                    )),
                const SizedBox(height: 5),
                Text(history[i]['month_id'].toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9.5, color: context.vMute)),
              ]),
            ),
        ]),
      ),
    );
  }

  List<String> get _chapterIds => _view == 'fullmonth'
      ? const ['commercial', 'network', 'attributes']
      : const ['commercial', 'network', 'portfolio', 'attributes'];

  Widget _chapterControls() {
    final labels = _view == 'fullmonth'
        ? const {
            'commercial': 'Commercial Trends',
            'network': 'Network & FWA',
            'attributes': 'Complete Site Attributes',
          }
        : const {
            'commercial': 'Commercial MTD',
            'network': 'Network & FWA',
            'portfolio': 'Revenue Mix & Portfolio',
            'attributes': 'Complete Site Attributes',
          };
    String? active;
    for (final id in _chapterIds) {
      if (_expandedChapters.contains(id)) {
        active = id;
        break;
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text('DETAIL CHAPTERS · SEMUA FIELD TETAP TERSEDIA',
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: context.vMute)),
      ),
      ReportChapterNavigator(
        chapters: [
          for (final id in _chapterIds)
            ReportChapterLink(
              id: id,
              label: labels[id] ?? id,
              icon: _chapterIcon(id),
            ),
        ],
        activeId: active,
        onSelected: (id) => setState(() => _expandedChapters.add(id)),
        onExpandAll: () =>
            setState(() => _expandedChapters.addAll(_chapterIds)),
        onCollapseAll: () => setState(_expandedChapters.clear),
      ),
    ]);
  }

  Widget _chapter(String id, String title, String subtitle,
      List<Widget> Function() contentBuilder) {
    final open = _expandedChapters.contains(id);
    return ReportChapter(
      key: PageStorageKey<String>('site:$_selected:$_view:$id'),
      title: title,
      summary: subtitle,
      icon: _chapterIcon(id),
      expanded: open,
      onExpansionChanged: (next) => setState(() {
        if (next) {
          _expandedChapters.add(id);
        } else {
          _expandedChapters.remove(id);
        }
      }),
      contentBuilder: (context) {
        final content = contentBuilder();
        if (content.isEmpty) {
          return Text('Tidak ada data untuk chapter ini.',
              style: TextStyle(color: context.vMute));
        }
        return Column(children: content);
      },
    );
  }

  IconData _chapterIcon(String id) => switch (id) {
        'commercial' => Icons.insights_outlined,
        'network' => Icons.cell_tower_outlined,
        'portfolio' => Icons.account_tree_outlined,
        _ => Icons.info_outline,
      };

  Widget _gaChannelBars(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Text('Tidak ada data.', style: TextStyle(color: context.vMute));
    }
    final maxValue = rows
        .map((r) => (r['ga'] as num?)?.toDouble() ?? 0)
        .fold<double>(0, math.max);
    return Column(children: [
      for (final row in rows)
        Semantics(
          label:
              '${row['channel']}, ${_num(row['ga'])}, ${row['pct'] == null ? 'share tidak tersedia' : '${reportNumber(row['pct'], decimals: 1)} persen'}',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Text((row['channel'] ?? '').toString(),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: context.vInk))),
                Text(
                    '${_num(row['ga'])}${row['pct'] == null ? '' : ' · ${reportPercent(row['pct'])}'}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.vInk)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 9,
                  color: context.vPanel,
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                      widthFactor: maxValue <= 0
                          ? 0
                          : (((row['ga'] as num?)?.toDouble() ?? 0) / maxValue)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                      child: Container(color: IOH.teal500)),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _stageBars(Map<String, dynamic> funnel) {
    final stages = <List<dynamic>>[
      ['M1S', funnel['m1s']],
      ['M2S', funnel['m2s']],
      ['P1M', funnel['p1m']],
      ['P2M', funnel['p2m']],
      ['GA', funnel['gross_add']],
    ];
    final values = stages.map((e) => (e[1] as num?)?.toDouble()).toList();
    final peak = values
        .whereType<double>()
        .where((v) => v >= 0)
        .fold<double>(0, math.max);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          'Stage counts memakai skala yang sama. Tidak ada conversion yang disimpulkan.',
          style: TextStyle(fontSize: 10.5, color: context.vMute)),
      const SizedBox(height: 8),
      for (var i = 0; i < stages.length; i++)
        Semantics(
          label:
              '${stages[i][0]}, ${values[i] == null ? 'tidak tersedia' : _num(values[i])}',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(
                  width: 42,
                  child: Text(stages[i][0].toString(),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.vInk))),
              Expanded(
                  child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 12,
                  color: context.vPanel,
                  alignment: Alignment.centerLeft,
                  child: values[i] == null
                      ? null
                      : FractionallySizedBox(
                          widthFactor: peak <= 0
                              ? 0
                              : (values[i]! / peak).clamp(0.0, 1.0).toDouble(),
                          child: Container(color: IOH.teal500)),
                ),
              )),
              const SizedBox(width: 10),
              SizedBox(
                  width: 76,
                  child: Text(values[i] == null ? 'N/A' : _num(values[i]),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: context.vInk))),
            ]),
          ),
        ),
    ]);
  }

  Widget _attributesTable(Map<String, dynamic> attributes) {
    String label(String key) => key
        .split('_')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
    return ReportAttributeTable(
      emptyLabel: 'Tidak ada atribut site.',
      attributes: [
        for (final entry in attributes.entries)
          ReportAttribute(
            label: label(entry.key),
            sublabel: entry.key,
            value: entry.value == null || entry.value.toString().isEmpty
                ? 'Tidak tersedia'
                : entry.value.toString(),
          ),
      ],
    );
  }

  Widget _tabsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.vRule),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ReportSegmentedControl<String>(
              value: _brand,
              style: ReportSegmentStyle.flat,
              scrollable: false,
              semanticLabel: 'Brand site',
              onChanged: _selectBrand,
              items: const [
                ReportSegmentItem(
                  value: 'ioh',
                  label: 'IOH',
                  selectedColor: Color(0xFF15A697),
                ),
                ReportSegmentItem(
                  value: 'im3',
                  label: 'IM3',
                  selectedColor: Color(0xFFF5A623),
                  selectedForeground: Color(0xFF6A4100),
                ),
                ReportSegmentItem(
                  value: '3id',
                  label: '3ID',
                  selectedColor: Color(0xFFEB008B),
                ),
              ],
            ),
            Container(
              width: 1,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: context.vRule,
            ),
            ReportSegmentedControl<String>(
              value: _view,
              scrollable: false,
              semanticLabel: 'Periode site',
              onChanged: (view) => setState(() => _view = view),
              items: const [
                ReportSegmentItem(value: 'snapshot', label: 'Snapshot (MTD)'),
                ReportSegmentItem(value: 'fullmonth', label: 'Full Month'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtBy(String kind, dynamic v) {
    if (v == null) return kReportNotAvailable;
    if (kind == 'mn') return _mn(v);
    if (kind == 'pct') {
      return reportPercent(v);
    }
    return _num(v);
  }

  Color _deltaColor(String code, num? delta) {
    if (delta == null || delta == 0) return context.vMute;
    // Polarity lives in report_format so every screen agrees on what is good.
    return reportGrowthColor(context, delta,
            polarity: reportPolarityFor(code)) ??
        context.vMute;
  }

  Widget _wideComparisonTable(List<Widget> rows) {
    return LayoutBuilder(builder: (context, constraints) {
      final textScale =
          MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
      final tableWidth =
          math.max(constraints.maxWidth, 520.0 * textScale).toDouble();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: tableWidth, child: Column(children: rows)),
      );
    });
  }

  String _fmtFwa(dynamic value, String format) {
    if (value == null) return 'N/A';
    final number = value is num ? value : num.tryParse(value.toString());
    if (number == null) return value.toString();
    switch (format) {
      case 'idr':
        return _mn(number);
      case 'pct':
        return reportPercent(number);
      case 'gb':
        return '${reportNumber(number, decimals: 1)} GB';
      default:
        return _num(number);
    }
  }

  Widget _fwaSummarySnapshot(Map<String, dynamic> summary) {
    final categories =
        (summary['categories'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (categories.isEmpty) {
      return Text('Data FWA complete belum tersedia.',
          style: TextStyle(color: context.vMute));
    }
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(9),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: context.vSubtle,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: context.vRule),
        ),
        child: Text(
          'Periode ${summary['month_id'] ?? 'N/A'}. Rasio IOH dihitung setelah agregasi IM3 dan 3ID. Buka kategori untuk melihat semua parameter.',
          style: TextStyle(fontSize: 10.5, color: context.vMute),
        ),
      ),
      for (final category in categories)
        _fwaCategory(
          name: (category['name'] ?? 'Metrics').toString(),
          rows: (category['rows'] as List?)?.cast<Map<String, dynamic>>() ?? [],
        ),
    ]);
  }

  Widget _fwaCategory({
    required String name,
    required List<Map<String, dynamic>> rows,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey<String>('site-fwa:$_selected:$_brand:$name'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        initiallyExpanded: name == 'Derived Ratios',
        maintainState: true,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(name,
            style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.vInk)),
        subtitle: Text('${rows.length} metrics',
            style: TextStyle(fontSize: 10, color: context.vMute)),
        children: [_fwaComparisonRows(rows)],
      ),
    );
  }

  Widget _fwaComparisonRows(List<Map<String, dynamic>> data) {
    Widget headerCell(String value, int flex,
            {TextAlign align = TextAlign.right}) =>
        Expanded(
          flex: flex,
          child: Text(value,
              textAlign: align,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: context.vMute)),
        );
    final rows = <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: Row(children: [
          headerCell('Metric', 5, align: TextAlign.left),
          headerCell('LMTD', 3),
          headerCell('MTD', 3),
          headerCell('Growth', 3),
          headerCell('YoY', 3),
        ]),
      ),
    ];
    for (var i = 0; i < data.length; i++) {
      final item = data[i];
      final code = (item['code'] ?? '').toString();
      final format = (item['format'] ?? 'num0').toString();
      final growth = item['growth'] as num?;
      final yoy = item['yoy'] as num?;
      Widget valueCell(String text, int flex,
              {Color? color, bool strong = false}) =>
          Expanded(
            flex: flex,
            child: Text(text,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                    color: color ?? context.vInk,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          );
      rows.add(Semantics(
        label:
            '${item['label']}, MTD ${_fmtFwa(item['mtd'], format)}, LMTD ${_fmtFwa(item['lmtd'], format)}, growth ${growth == null ? 'tidak tersedia' : '${growth.toStringAsFixed(1)} persen'}, year on year ${yoy == null ? 'tidak tersedia' : '${yoy.toStringAsFixed(1)} persen'}',
        child: Container(
          color: i.isOdd ? context.vZebra : context.vWhite,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 5,
              child: Text((item['label'] ?? code).toString(),
                  style: TextStyle(fontSize: 10.5, color: context.vInk)),
            ),
            valueCell(_fmtFwa(item['lmtd'], format), 3),
            valueCell(_fmtFwa(item['mtd'], format), 3, strong: true),
            valueCell(
              growth == null
                  ? 'N/A'
                  : '${growth >= 0 ? '▲' : '▼'} ${growth.abs().toStringAsFixed(1)}%',
              3,
              color: _deltaColor(code, growth),
            ),
            valueCell(
              yoy == null
                  ? 'N/A'
                  : '${yoy >= 0 ? '▲' : '▼'} ${yoy.abs().toStringAsFixed(1)}%',
              3,
              color: _deltaColor(code, yoy),
            ),
          ]),
        ),
      ));
    }
    return _wideComparisonTable(rows);
  }

  Widget _fwaSummaryHistory(Map<String, dynamic> summary) {
    final categories =
        (summary['categories'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final history =
        (summary['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (categories.isEmpty || history.isEmpty) {
      return Text('Histori FWA bulan penuh belum tersedia.',
          style: TextStyle(color: context.vMute));
    }
    return Column(children: [
      for (final category in categories)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey<String>(
                'site-fwa-history:$_selected:$_brand:${category['name']}'),
            tilePadding: const EdgeInsets.symmetric(horizontal: 8),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            maintainState: true,
            dense: true,
            visualDensity: VisualDensity.compact,
            title: Text((category['name'] ?? 'Metrics').toString(),
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.vInk)),
            subtitle: Text(
                '${((category['rows'] as List?) ?? []).length} metrics · ${history.length} closed months',
                style: TextStyle(fontSize: 10, color: context.vMute)),
            children: [
              _monthlyKVTable(
                history,
                [
                  for (final item
                      in ((category['rows'] as List?) ?? []).cast<Map>())
                    [
                      (item['code'] ?? '').toString(),
                      (item['label'] ?? item['code'] ?? '').toString(),
                      switch ((item['format'] ?? 'num0').toString()) {
                        'idr' => 'mn',
                        'pct' => 'pct',
                        _ => 'num',
                      },
                    ],
                ],
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _kvLmtdTable(Map<String, dynamic> data, List<List<String>> rowsDef) {
    final mtd = (data['mtd'] as Map?)?.cast<String, dynamic>() ?? {};
    final lmtd = (data['lmtd'] as Map?)?.cast<String, dynamic>() ?? {};
    final rows = <Widget>[
      Container(
          color: context.vWhite,
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(
                flex: 4,
                child: Text('Metric',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.vMute))),
            Expanded(
                flex: 3,
                child: Text('LMTD',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.vMute))),
            Expanded(
                flex: 3,
                child: Text('MTD',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.vMute))),
            Expanded(
                flex: 3,
                child: Text('Growth',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.vMute))),
          ])),
    ];
    for (var i = 0; i < rowsDef.length; i++) {
      final code = rowsDef[i][0], label = rowsDef[i][1], kind = rowsDef[i][2];
      final m = mtd[code] as num?, l = lmtd[code] as num?;
      num? g;
      if (m != null && l != null) {
        g = (kind == 'pct') ? (m - l) : (l != 0 ? (m - l) / l * 100 : null);
      }
      rows.add(Container(
          color: i.isOdd ? context.vZebra : context.vWhite,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
                flex: 4,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: context.vInk))),
            Expanded(
                flex: 3,
                child: Text(_fmtBy(kind, l),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11.5, color: context.vInk))),
            Expanded(
                flex: 3,
                child: Text(_fmtBy(kind, m),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.vInk))),
            Expanded(
                flex: 3,
                child: Text(
                    g == null
                        ? 'N/A'
                        : reportGrowth(g, suffix: kind == 'pct' ? 'pp' : '%'),
                    textAlign: TextAlign.right,
                    style:
                        TextStyle(fontSize: 11, color: _deltaColor(code, g)))),
          ])));
    }
    return _wideComparisonTable(rows);
  }

  Widget _monthlyKVTable(
      List<Map<String, dynamic>> hist, List<List<String>> rowsDef) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final nameW = 140.0 * textScale.clamp(1.0, 1.5);
    final headH = 28.0 * textScale;
    final rowH = 38.0 * textScale;
    final colW = 84.0 * textScale.clamp(1.0, 1.6);
    final months = hist.map((h) => h['month_id'].toString()).toList();
    final nameCol =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: nameW,
          height: headH,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Metric',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.vMute))),
      for (var i = 0; i < rowsDef.length; i++)
        Container(
            width: nameW,
            height: rowH,
            color: i.isOdd ? context.vZebra : context.vWhite,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Text(rowsDef[i][1],
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: context.vInk))),
    ]);
    Widget cell(String t, {bool head = false, bool bold = false}) => Container(
        width: colW,
        height: head ? headH : rowH,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: head ? 10 : 11,
                fontWeight: head
                    ? FontWeight.w700
                    : (bold ? FontWeight.w700 : FontWeight.w400),
                color: head ? context.vMute : context.vInk,
                fontFeatures: const [FontFeature.tabularFigures()])));
    final dataCols =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [for (final m in months) cell(m, head: true)]),
      for (var i = 0; i < rowsDef.length; i++)
        Container(
            color: i.isOdd ? context.vZebra : context.vWhite,
            child: Row(children: [
              for (final h in hist)
                cell(_fmtBy(rowsDef[i][2], h[rowsDef[i][0]])),
            ])),
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }

  Widget _metricTable(Map<String, dynamic> d, List<String> codes) {
    final metrics = (d['metrics'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final byCode = {for (final m in metrics) m['code'].toString(): m};
    String fmt(String code, dynamic v) => _isRev(code) ? _mn(v) : _num(v);
    final rows = <Widget>[
      Container(
        color: context.vWhite,
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
              flex: 4,
              child: Text('Metric',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: context.vMute))),
          Expanded(
              flex: 3,
              child: Text('LMTD',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: context.vMute))),
          Expanded(
              flex: 3,
              child: Text('MTD',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: context.vMute))),
          Expanded(
              flex: 3,
              child: Text('Growth',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: context.vMute))),
        ]),
      ),
    ];
    for (var i = 0; i < codes.length; i++) {
      final m = byCode[codes[i]];
      if (m == null) continue;
      final g = m['growth'] as num?;
      rows.add(Container(
        color: i.isOdd ? context.vZebra : context.vWhite,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
              flex: 4,
              child: Text(_metricLabels[codes[i]] ?? codes[i],
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: context.vInk))),
          Expanded(
              flex: 3,
              child: Text(fmt(codes[i], m['lmtd']),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11.5, color: context.vInk))),
          Expanded(
              flex: 3,
              child: Text(fmt(codes[i], m['mtd']),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: context.vInk))),
          Expanded(
              flex: 3,
              child: Text(
                  g == null
                      ? 'N/A'
                      : reportGrowth(g),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 11, color: _deltaColor(codes[i], g)))),
        ]),
      ));
    }
    return _wideComparisonTable(rows);
  }

  Widget _panel(String title, Widget child) =>
      ReportPanel(title: title, child: child);

  Widget _channelMetricTable(List<Map<String, dynamic>> rows) {
    Color sg(num? g) => (g ?? 0) >= 0 ? IOH.teal600 : IOH.danger;
    final widgets = <Widget>[
      Container(
          color: context.vWhite,
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(
                flex: 4,
                child: Text('Channel',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.vMute))),
            Expanded(
                flex: 3,
                child: Text('LMTD',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.vMute))),
            Expanded(
                flex: 3,
                child: Text('MTD',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.vMute))),
            Expanded(
                flex: 3,
                child: Text('Growth',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.vMute))),
          ])),
    ];
    for (var i = 0; i < rows.length; i++) {
      final c = rows[i];
      final g = c['growth'] as num?;
      widgets.add(Container(
          color: i.isOdd ? context.vZebra : context.vWhite,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
                flex: 4,
                child: Text((c['channel'] ?? '').toString(),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: context.vInk))),
            Expanded(
                flex: 3,
                child: Text(_mn(c['lmtd']),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11.5, color: context.vInk))),
            Expanded(
                flex: 3,
                child: Text(_mn(c['mtd']),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: context.vInk))),
            Expanded(
                flex: 3,
                child: Text(
                    g == null
                        ? 'N/A'
                        : reportGrowth(g),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: sg(g)))),
          ])));
    }
    return _wideComparisonTable(widgets);
  }

  Widget _channelHistoryTable(List<Map<String, dynamic>> hist) {
    Widget cell(String t, {bool head = false, double w = 90}) => SizedBox(
        width: w,
        child: Text(t,
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: head ? 9.5 : 11,
                fontWeight: head ? FontWeight.w700 : FontWeight.w400,
                color: head ? context.vMute : context.vInk,
                fontFeatures: const [FontFeature.tabularFigures()])));
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            SizedBox(
                width: 64,
                child: Text('Bulan',
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: context.vMute))),
            cell('Organic', head: true),
            cell('Digital', head: true),
            cell('MOBO Trade', head: true, w: 96)
          ]),
          ...hist.asMap().entries.map((e) {
            final h = e.value;
            return Container(
                color: e.key.isOdd ? context.vZebra : context.vWhite,
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  SizedBox(
                      width: 64,
                      child: Text(h['month_id'].toString(),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.vInk))),
                  cell(_mn(h['ORGANIC'])),
                  cell(_mn(h['DIGITAL DISTRIBUTION'])),
                  cell(_mn(h['MOBO TRADE']), w: 96),
                ]));
          }),
        ]));
  }

  Widget _list2(List<Map<String, dynamic>> rows,
          List<String> Function(Map<String, dynamic>) map) =>
      Column(
        children: rows.asMap().entries.map((e) {
          final kv = map(e.value);
          return Container(
            color: e.key.isOdd ? context.vZebra : context.vWhite,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(children: [
              Expanded(
                  flex: 6,
                  child: Text(kv[0],
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.vInk))),
              const SizedBox(width: 10),
              Flexible(
                  flex: 4,
                  child: Text(kv[1],
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: context.vInk))),
            ]),
          );
        }).toList(),
      );

  // Full-month table: frozen metric column + scrollable month columns (mirrors MTD).
  Widget _monthlyTable(List<Map<String, dynamic>> hist, List<String> codes) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final nameW = 140.0 * textScale.clamp(1.0, 1.5);
    final headH = 28.0 * textScale;
    final rowH = 38.0 * textScale;
    final colW = 84.0 * textScale.clamp(1.0, 1.6);
    final months = hist.map((h) => h['month_id'].toString()).toList();
    final nameCol =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: nameW,
          height: headH,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Metric',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.vMute))),
      for (var i = 0; i < codes.length; i++)
        Container(
            width: nameW,
            height: rowH,
            color: i.isOdd ? context.vZebra : context.vWhite,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Text(_metricLabels[codes[i]] ?? codes[i],
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: context.vInk))),
    ]);
    Widget cell(String t, {bool head = false, bool bold = false}) => Container(
        width: colW,
        height: head ? headH : rowH,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: head ? 10 : 11,
                fontWeight: head
                    ? FontWeight.w700
                    : (bold ? FontWeight.w700 : FontWeight.w400),
                color: head ? context.vMute : context.vInk,
                fontFeatures: const [FontFeature.tabularFigures()])));
    final dataCols =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [for (final m in months) cell(m, head: true)]),
      for (var i = 0; i < codes.length; i++)
        Container(
            color: i.isOdd ? context.vZebra : context.vWhite,
            child: Row(children: [
              for (final h in hist)
                cell(_isRev(codes[i]) ? _mn(h[codes[i]]) : _num(h[codes[i]])),
            ])),
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }

  Widget _monthlyChannelTable(List<Map<String, dynamic>> hist) {
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final nameW = 120.0 * textScale.clamp(1.0, 1.5);
    final headH = 28.0 * textScale;
    final rowH = 38.0 * textScale;
    final colW = 84.0 * textScale.clamp(1.0, 1.6);
    final months = hist.map((h) => h['month_id'].toString()).toList();
    const rows = [
      ['ORGANIC', 'Organic'],
      ['DIGITAL DISTRIBUTION', 'Digital'],
      ['MOBO TRADE', 'MOBO Trade']
    ];
    final nameCol =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: nameW,
          height: headH,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Channel',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: context.vMute))),
      for (var i = 0; i < rows.length; i++)
        Container(
            width: nameW,
            height: rowH,
            color: i.isOdd ? context.vZebra : context.vWhite,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Text(rows[i][1],
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.vInk))),
    ]);
    Widget cell(String t, {bool head = false}) => Container(
        width: colW,
        height: head ? headH : rowH,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: head ? 10 : 11,
                fontWeight: head ? FontWeight.w700 : FontWeight.w400,
                color: head ? context.vMute : context.vInk,
                fontFeatures: const [FontFeature.tabularFigures()])));
    final dataCols =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [for (final m in months) cell(m, head: true)]),
      for (var i = 0; i < rows.length; i++)
        Container(
            color: i.isOdd ? context.vZebra : context.vWhite,
            child: Row(
                children: [for (final h in hist) cell(_mn(h[rows[i][0]]))])),
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }
}
