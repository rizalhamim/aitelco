import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../theme.dart';
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

  static const _metricLabels = {
    'rev_prepaid': 'Revenue Prepaid', 'rev_vsd': 'Revenue VSD', 'rev_nonvsd': 'Revenue Non-VSD',
    'rev_data': 'Revenue Data', 'rev_voice': 'Revenue Voice', 'rev_sms': 'Revenue SMS',
    'rev_trade': 'Revenue Trade', 'rev_organic': 'Revenue Organic', 'rev_nontrade': 'Revenue Non-Trade',
    'rev_acquisition_m0': 'Revenue Acq M0', 'subs_rgu_90d': 'RGU 90D', 'subs_rgu_30d': 'RGU 30D',
    'subs_gross_add': 'Gross Add', 'net_add_90d': 'Net Add 90D', 'net_add_30d': 'Net Add 30D',
    'gross_churn_90d': 'Gross Churn 90D', 'gross_churn_30d': 'Gross Churn 30D', 'churn_back_90d': 'Churn Back 90D',
    'subs_net_churn_90d': 'Net Churn 90D', 'subs_vlr_30d': 'VLR 30D', 'subs_avg_vlr_daily': 'VLR Daily',
    'datauu': 'Data Users', 'datauu30d': 'Data Users 30D', 'usg_data_gb': 'Usage Data (GB)',
    'usg_og_voice_min': 'Usage Voice (Min)', 'usg_og_sms_cnt': 'Usage SMS', 'ga_m1s': 'GA M1S', 'ga_m2s': 'GA M2S',
    'ga_p1m': 'GA P1M', 'ga_p2m': 'GA P2M', 'subs_hvc': 'HVC Subs', 'subs_hvc_stay': 'HVC Stay',
    'subs_hvc_in': 'HVC In', 'subs_hvc_out': 'HVC Out',
  };
  static const _brandColors = {'ioh': Color(0xFF15A697), 'im3': Color(0xFFF5A623), '3id': Color(0xFFEB008B)};
  bool _isRev(String c) => c.startsWith('rev_') || c == 'usg_data_gb';

  String _mn(dynamic v) {
    if (v == null) return '—';
    final n = (v as num).toDouble();
    if (n.abs() >= 1e6) return '${NumberFormat('#,##0.0', 'id').format(n / 1e6)} Mn';
    return NumberFormat('#,##0', 'id').format(n);
  }

  String _num(dynamic v) => v == null ? '—' : NumberFormat('#,##0', 'id').format((v as num).toDouble());

  Future<void> _locate() async {
    setState(() { _err = ''; _list = []; _loadingList = true; });
    final c = await getCurrentCoord(context);
    if (c == null) { if (mounted) setState(() => _loadingList = false); return; }
    try {
      final sites = await ApiClient.siteNearest(c.$1, c.$2);
      if (mounted) setState(() => _list = sites);
    } catch (e) { if (mounted) setState(() => _err = e.toString()); }
    if (mounted) setState(() => _loadingList = false);
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) { setState(() => _list = []); return; }
    setState(() => _loadingList = true);
    try {
      final sites = await ApiClient.siteSearch(q.trim());
      if (mounted) setState(() => _list = sites);
    } catch (_) {}
    if (mounted) setState(() => _loadingList = false);
  }

  Future<void> _open(String sid) async {
    setState(() { _selected = sid; });
    final hit = _cache['$sid|$_brand'];
    if (hit != null) { setState(() { _detail = hit; _loadingDetail = false; }); }
    else { setState(() { _loadingDetail = true; _detail = null; }); }
    try {
      // Fetch the active brand first, then prefetch the others into cache.
      final order = <String>[_brand, ...['ioh', 'im3', '3id'].where((b) => b != _brand)];
      for (final b in order) {
        final key = '$sid|$b';
        if (_cache.containsKey(key)) { if (b == _brand && mounted) setState(() { _detail = _cache[key]; _loadingDetail = false; }); continue; }
        final d = await ApiClient.siteDetail(sid, brand: b);
        _cache[key] = d;
        if (b == _brand && mounted) setState(() { _detail = d; _loadingDetail = false; });
      }
    } catch (e) { if (mounted) setState(() { _detail = {'error': e.toString()}; _loadingDetail = false; }); }
  }

  void _selectBrand(String b) {
    setState(() => _brand = b);
    final hit = _cache['$_selected|$b'];
    if (hit != null) { setState(() => _detail = hit); }     // instant
    else { _open(_selected); }
  }

  @override
  void dispose() { _searchCtl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.vPanel,
      appBar: AppBar(title: const Text('Site Performance')),
      body: _detail != null || _loadingDetail
          ? _detailView()
          : ListView(padding: const EdgeInsets.all(16), children: [
              _modeToggle(),
              const SizedBox(height: 12),
              if (_mode == 'coordinate')
                ElevatedButton.icon(
                  onPressed: _loadingList ? null : _locate,
                  style: ElevatedButton.styleFrom(backgroundColor: IOH.teal500, foregroundColor: Colors.white),
                  icon: const Icon(Icons.my_location, size: 18),
                  label: Text(_loadingList ? 'Mencari…' : 'Gunakan Lokasi Saya'),
                )
              else
                TextField(
                  controller: _searchCtl,
                  onChanged: _search,
                  decoration: InputDecoration(
                    hintText: 'Masukkan Site ID atau Site Name…',
                    prefixIcon: const Icon(Icons.search),
                    filled: true, fillColor: context.vWhite,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.vRule)),
                  ),
                ),
              if (_err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err, style: const TextStyle(color: IOH.danger, fontSize: 12))),
              const SizedBox(height: 12),
              if (_loadingList) const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: IOH.teal500)))
              else ..._list.map((s) => _siteCard(s)),
            ]),
    );
  }

  Widget _modeToggle() {
    Widget seg(String key, String label, IconData ic) => Expanded(child: GestureDetector(
      onTap: () => setState(() { _mode = key; _list = []; _detail = null; _selected = ''; }),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _mode == key ? IOH.teal500 : context.vWhite, borderRadius: BorderRadius.circular(999), border: Border.all(color: _mode == key ? IOH.teal500 : context.vRule)),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ic, size: 15, color: _mode == key ? Colors.white : context.vMute),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: 12.5, color: _mode == key ? Colors.white : context.vMute)),
        ]),
      ),
    ));
    return Row(children: [seg('coordinate', 'Coordinate', Icons.place_outlined), seg('search', 'Site Search', Icons.search)]);
  }

  Widget _siteCard(Map<String, dynamic> s) {
    final active = _selected == s['site_id'];
    return GestureDetector(
      onTap: () => _open(s['site_id'].toString()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: active ? IOH.teal500.withValues(alpha: 0.1) : context.vWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: active ? IOH.teal500 : context.vRule)),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((s['site_name'] ?? s['site_id'] ?? '').toString(), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.vInk)),
            Text('${s['site_id']}${s['distance_km'] != null ? ' · ${s['distance_km']} km' : ''} · ${s['branch'] ?? ''}', style: TextStyle(fontSize: 11, color: context.vMute)),
          ])),
          Icon(Icons.chevron_right, color: context.vMute),
        ]),
      ),
    );
  }

  // ── Detail ──
  Widget _detailView() {
    if (_loadingDetail) return const Center(child: CircularProgressIndicator(color: IOH.teal500));
    final d = _detail!;
    if (d['error'] != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(d['error'].toString(), style: const TextStyle(color: IOH.danger))));
    }
    final a = (d['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
    final fn = (d['funnel'] as Map?)?.cast<String, dynamic>() ?? {};
    String str(dynamic v) => (v == null || v == '') ? '—' : v.toString();

    return ListView(padding: const EdgeInsets.all(16), children: [
      // back to list
      GestureDetector(onTap: () => setState(() { _detail = null; _selected = ''; }),
        child: Row(children: [Icon(Icons.arrow_back, size: 18, color: IOH.teal600), const SizedBox(width: 6), Text('Kembali ke daftar', style: TextStyle(color: IOH.teal600, fontWeight: FontWeight.w600))])),
      const SizedBox(height: 12),
      // header
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: context.vWhite, borderRadius: BorderRadius.circular(16), border: const Border(top: BorderSide(color: IOH.teal500, width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(str(a['site_name']), style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 18, color: context.vInk)),
          Text(str(a['site_id']), style: TextStyle(fontSize: 12, color: context.vMute)),
          const SizedBox(height: 6),
          Text('${str(a['site_type'])} · ${str(a['category'])} · ${str(a['kecamatan'])}, ${str(a['kabupaten'])}', style: TextStyle(fontSize: 12, color: context.vMute)),
          Text('Branch ${str(a['branch'])} · MC ${str(a['micro_cluster'])} · Region ${str(a['region'])} · Bulan ${str(d['month_id'])}', style: TextStyle(fontSize: 11, color: context.vMute)),
        ]),
      ),
      const SizedBox(height: 12),
      // brand + view tabs
      _tabsRow(),
      const SizedBox(height: 12),
      if (_view == 'fullmonth') ...[
        _panel('Revenue · Full Month', _monthlyTable((d['history'] as List?)?.cast<Map<String, dynamic>>() ?? [], const ['rev_prepaid', 'rev_vsd', 'rev_nonvsd', 'rev_data', 'rev_voice', 'rev_sms', 'rev_trade', 'rev_organic', 'rev_nontrade', 'rev_acquisition_m0'])),
        const SizedBox(height: 12),
        _panel('Subscriber & Usage · Full Month', _monthlyTable((d['history'] as List?)?.cast<Map<String, dynamic>>() ?? [], const ['subs_rgu_90d', 'subs_rgu_30d', 'subs_gross_add', 'net_add_90d', 'net_add_30d', 'gross_churn_90d', 'gross_churn_30d', 'churn_back_90d', 'subs_net_churn_90d', 'subs_vlr_30d', 'subs_avg_vlr_daily', 'datauu', 'datauu30d', 'subs_hvc', 'subs_hvc_stay', 'subs_hvc_in', 'subs_hvc_out', 'usg_data_gb', 'usg_og_voice_min', 'usg_og_sms_cnt'])),
        const SizedBox(height: 12),
        if (((d['channel_history'] as List?) ?? []).isNotEmpty)
          _panel('Revenue by Channel · Full Month', _monthlyChannelTable((d['channel_history'] as List?)?.cast<Map<String, dynamic>>() ?? [])),
        const SizedBox(height: 12),
        if (d['network']?['history'] != null)
          _panel('Network (Data UU · Traffic · Device) · Full Month', _monthlyKVTable((d['network']['history'] as List).cast<Map<String, dynamic>>(), const [
            ['data_uu30_all', 'Data UU (All)', 'num'], ['data_uu30_dev_2g', 'Data UU Dev 2G', 'num'], ['data_uu30_dev_4g', 'Data UU Dev 4G', 'num'], ['data_uu30_dev_5g', 'Data UU Dev 5G', 'num'],
            ['traffic_2g', 'Traffic 2G', 'num'], ['traffic_4g', 'Traffic 4G', 'num'], ['traffic_5g', 'Traffic 5G', 'num'], ['traffic_total', 'Traffic Total', 'num'],
            ['dev_all', 'Device Total', 'num'], ['dev5g_total', 'Device 5G', 'num'], ['dev5g_with_traffic', 'Device 5G w/ Traffic', 'num'],
            ['dev5g_pct', 'Device 5G % vs Total', 'pct'], ['dev5g_traffic_pct', 'Dev 5G w/Traffic % vs Dev 5G', 'pct']
          ])),
        const SizedBox(height: 12),
        if (d['availability']?['history'] != null)
          _panel('Availability · Full Month', _monthlyKVTable((d['availability']['history'] as List).cast<Map<String, dynamic>>(), const [
            ['avg_avail_pct_2g', 'Availability 2G %', 'pct'], ['avg_avail_pct_4g', 'Availability 4G %', 'pct'], ['avg_avail_pct_5g', 'Availability 5G %', 'pct'],
            ['days_down_2g', 'Days Down 2G', 'num'], ['days_down_4g', 'Days Down 4G', 'num'], ['days_down_5g', 'Days Down 5G', 'num']
          ])),
        const SizedBox(height: 12),
        if (d['fwa']?['history'] != null)
          _panel('FWA · Full Month', _monthlyKVTable((d['fwa']['history'] as List).cast<Map<String, dynamic>>(), const [
            ['rev_fwa_total', 'Revenue FWA Total', 'mn'], ['rev_fwa_pack', 'Revenue FWA Pack', 'mn'], ['rev_fwa_sim', 'Revenue FWA SIM', 'mn'], ['rev_fwa_regular', 'Revenue FWA Regular', 'mn'], ['rev_fwa_non_broadband', 'Revenue FWA Non-BB', 'mn'],
            ['fwa_rgu90', 'FWA RGU 90D', 'num'], ['fwa_rgu_ga', 'FWA Gross Add', 'num'], ['fwa_grosschurn90', 'FWA Gross Churn 90D', 'num'], ['fwa_churnback90', 'FWA Churn Back 90D', 'num'], ['fwa_net_add_90_closing', 'FWA Net Add 90D', 'num'],
            ['fwa_pack_hits', 'FWA Pack Hits', 'num'], ['vlr_fwa_less_90d', 'VLR FWA <90D', 'num'], ['vlr_fwa_91_180d', 'VLR FWA 91-180D', 'num'], ['vlr_fwa_above_181d', 'VLR FWA >181D', 'num']
          ])),
      ]
      else ...[
        _panel('Revenue (LMTD · MTD · Growth)', _metricTable(d, const ['rev_prepaid', 'rev_vsd', 'rev_nonvsd', 'rev_data', 'rev_voice', 'rev_sms', 'rev_trade', 'rev_organic', 'rev_nontrade', 'rev_acquisition_m0'])),
        const SizedBox(height: 12),
        _panel('Subscriber & Usage (LMTD · MTD · Growth)', _metricTable(d, const ['subs_rgu_90d', 'subs_rgu_30d', 'subs_gross_add', 'net_add_90d', 'net_add_30d', 'gross_churn_90d', 'gross_churn_30d', 'churn_back_90d', 'subs_net_churn_90d', 'subs_vlr_30d', 'subs_avg_vlr_daily', 'datauu', 'datauu30d', 'subs_hvc', 'subs_hvc_stay', 'subs_hvc_in', 'subs_hvc_out', 'usg_data_gb', 'usg_og_voice_min', 'usg_og_sms_cnt'])),
        const SizedBox(height: 12),
        if (((d['ga_channels'] as List?) ?? []).isNotEmpty)
          _panel('Acquisition by Channel (GA)', _list2((d['ga_channels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
              (g) => ['${g['channel']}', '${_num(g['ga'])}${g['pct'] != null ? ' · ${NumberFormat('#,##0.0', 'id').format((g['pct'] as num).toDouble())}%' : ''}'])),
        if (((d['ga_channels'] as List?) ?? []).isNotEmpty) const SizedBox(height: 12),
        _panel('Acquisition Funnel', Row(children: [
          for (final e in [['M1S', fn['m1s']], ['M2S', fn['m2s']], ['P1M', fn['p1m']], ['P2M', fn['p2m']], ['GA', fn['gross_add']]])
            Expanded(child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: context.vZebra, borderRadius: BorderRadius.circular(10)),
              child: Column(children: [
                Text(_num(e[1]), style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16, color: context.vInk)),
                Text(e[0].toString(), style: TextStyle(fontSize: 10, color: context.vMute)),
              ]),
            )),
        ])),
        const SizedBox(height: 12),
        if (d['network']?['mtd'] != null)
          _panel('Network · Data UU · Traffic · Device (LMTD · MTD · Growth)', _kvLmtdTable((d['network'] as Map).cast<String, dynamic>(), const [
            ['data_uu30_all', 'Data UU (All)', 'num'], ['data_uu30_dev_2g', 'Data UU Dev 2G', 'num'], ['data_uu30_dev_4g', 'Data UU Dev 4G', 'num'], ['data_uu30_dev_5g', 'Data UU Dev 5G', 'num'],
            ['traffic_2g', 'Traffic 2G', 'num'], ['traffic_4g', 'Traffic 4G', 'num'], ['traffic_5g', 'Traffic 5G', 'num'], ['traffic_total', 'Traffic Total', 'num'],
            ['dev_all', 'Device Total', 'num'], ['dev5g_total', 'Device 5G', 'num'], ['dev5g_with_traffic', 'Device 5G w/ Traffic', 'num'],
            ['dev5g_pct', 'Device 5G % vs Total', 'pct'], ['dev5g_traffic_pct', 'Dev 5G w/Traffic % vs Dev 5G', 'pct']
          ])),
        if (d['network']?['mtd'] != null) const SizedBox(height: 12),
        if (d['availability']?['mtd'] != null)
          _panel('Availability (LMTD · MTD · Growth)', _kvLmtdTable((d['availability'] as Map).cast<String, dynamic>(), const [
            ['avg_avail_pct_2g', 'Availability 2G %', 'pct'], ['avg_avail_pct_4g', 'Availability 4G %', 'pct'], ['avg_avail_pct_5g', 'Availability 5G %', 'pct'],
            ['days_down_2g', 'Days Down 2G', 'num'], ['days_down_4g', 'Days Down 4G', 'num'], ['days_down_5g', 'Days Down 5G', 'num']
          ])),
        if (d['availability']?['mtd'] != null) const SizedBox(height: 12),
        if (d['fwa']?['mtd'] != null)
          _panel('FWA Performance (LMTD · MTD · Growth)', _kvLmtdTable((d['fwa'] as Map).cast<String, dynamic>(), const [
            ['rev_fwa_total', 'Revenue FWA Total', 'mn'], ['rev_fwa_pack', 'Revenue FWA Pack', 'mn'], ['rev_fwa_sim', 'Revenue FWA SIM', 'mn'], ['rev_fwa_regular', 'Revenue FWA Regular', 'mn'], ['rev_fwa_non_broadband', 'Revenue FWA Non-BB', 'mn'],
            ['fwa_rgu90', 'FWA RGU 90D', 'num'], ['fwa_rgu_ga', 'FWA Gross Add', 'num'], ['fwa_grosschurn90', 'FWA Gross Churn 90D', 'num'], ['fwa_churnback90', 'FWA Churn Back 90D', 'num'], ['fwa_net_add_90_closing', 'FWA Net Add 90D', 'num'],
            ['fwa_pack_hits', 'FWA Pack Hits', 'num'], ['vlr_fwa_less_90d', 'VLR FWA <90D', 'num'], ['vlr_fwa_91_180d', 'VLR FWA 91-180D', 'num'], ['vlr_fwa_above_181d', 'VLR FWA >181D', 'num']
          ])),
        if (d['fwa']?['mtd'] != null) const SizedBox(height: 12),
        _panel('Revenue by Channel (LMTD · MTD · Growth)', _channelMetricTable((d['channel_metrics'] as List?)?.cast<Map<String, dynamic>>() ?? [])),
        const SizedBox(height: 12),
        _panel('Revenue by Channel · Monthly', _channelHistoryTable((d['channel_history'] as List?)?.cast<Map<String, dynamic>>() ?? [])),
        const SizedBox(height: 12),
        _panel('Channel Detail', _list2((d['channels'] as List?)?.cast<Map<String, dynamic>>() ?? [],
            (c) => ['${c['channel']} · ${c['detail']}', _mn(c['revenue'])])),
        const SizedBox(height: 12),
        _panel('Top Products', _list2((d['top_products'] as List?)?.cast<Map<String, dynamic>>() ?? [],
            (t) => ['${t['product']}', '${_mn(t['revenue'])} · ${_num(t['hit'])} hit'])),
        const SizedBox(height: 12),
        _panel('Price Slab', _list2((d['price_slabs'] as List?)?.cast<Map<String, dynamic>>() ?? [],
            (s) => [s['slab'].toString(), '${_mn(s['revenue'])} · ${_num(s['hit'])} hit'])),
        const SizedBox(height: 12),
        _panel('Slab Kuota', _list2((d['quota_slabs'] as List?)?.cast<Map<String, dynamic>>() ?? [],
            (s) => [s['slab'].toString(), _mn(s['revenue'])])),
        const SizedBox(height: 12),
        _panel('Slab Masa Aktif', _list2((d['validity_slabs'] as List?)?.cast<Map<String, dynamic>>() ?? [],
            (s) => [s['slab'].toString(), _mn(s['revenue'])])),
      ],
      const SizedBox(height: 24),
    ]);
  }

  Widget _tabsRow() {
    Widget pill(String label, bool active, Color bg, Color fg, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        decoration: BoxDecoration(color: active ? bg : context.vWhite, borderRadius: BorderRadius.circular(999), border: Border.all(color: active ? bg : context.vRule)),
        child: Text(label, style: TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: active ? fg : context.vMute)),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (final b in const ['ioh', 'im3', '3id'])
          pill(b.toUpperCase(), _brand == b, _brandColors[b]!, b == 'im3' ? const Color(0xFF161616) : Colors.white,
              () { if (_brand != b) _selectBrand(b); }),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        pill('Snapshot (MTD)', _view == 'snapshot', IOH.teal500, Colors.white, () => setState(() => _view = 'snapshot')),
        pill('Full Month', _view == 'fullmonth', IOH.teal500, Colors.white, () => setState(() => _view = 'fullmonth')),
      ]),
    ]);
  }

  String _fmtBy(String kind, dynamic v) {
    if (v == null) return '—';
    if (kind == 'mn') return _mn(v);
    if (kind == 'pct') return '${NumberFormat('#,##0.0', 'id').format((v as num).toDouble())}%';
    return _num(v);
  }

  Widget _kvLmtdTable(Map<String, dynamic> data, List<List<String>> rowsDef) {
    final mtd = (data['mtd'] as Map?)?.cast<String, dynamic>() ?? {};
    final lmtd = (data['lmtd'] as Map?)?.cast<String, dynamic>() ?? {};
    Color sg(num? g) => (g ?? 0) >= 0 ? IOH.teal600 : IOH.danger;
    final rows = <Widget>[
      Container(color: context.vWhite, padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
        Expanded(flex: 4, child: Text('Metric', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
        Expanded(flex: 3, child: Text('LMTD', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
        Expanded(flex: 3, child: Text('MTD', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
        Expanded(flex: 3, child: Text('Growth', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
      ])),
    ];
    for (var i = 0; i < rowsDef.length; i++) {
      final code = rowsDef[i][0], label = rowsDef[i][1], kind = rowsDef[i][2];
      final m = mtd[code] as num?, l = lmtd[code] as num?;
      num? g;
      if (m != null && l != null) {
        g = (kind == 'pct') ? (m - l) : (l != 0 ? (m - l) / l * 100 : null);
      }
      rows.add(Container(color: i.isOdd ? context.vZebra : context.vWhite, padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
        Expanded(flex: 4, child: Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: context.vInk))),
        Expanded(flex: 3, child: Text(_fmtBy(kind, l), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: context.vInk))),
        Expanded(flex: 3, child: Text(_fmtBy(kind, m), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.vInk))),
        Expanded(flex: 3, child: Text(g == null ? '—' : '${g >= 0 ? '▲' : '▼'} ${NumberFormat('#,##0.0', 'id').format(g.abs())}${kind == 'pct' ? 'pp' : '%'}', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: sg(g)))),
      ])));
    }
    return Column(children: rows);
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
    Widget cell(String t, {bool head = false, bool bold = false}) => Container(width: colW, height: head ? headH : rowH, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t, style: TextStyle(fontSize: head ? 10 : 11, fontWeight: head ? FontWeight.w700 : (bold ? FontWeight.w700 : FontWeight.w400), color: head ? context.vMute : context.vInk, fontFeatures: const [FontFeature.tabularFigures()])));
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

  Widget _metricTable(Map<String, dynamic> d, List<String> codes) {
    final metrics = (d['metrics'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final byCode = {for (final m in metrics) m['code'].toString(): m};
    Color sg(num? g) => (g ?? 0) >= 0 ? IOH.teal600 : IOH.danger;
    String fmt(String code, dynamic v) => _isRev(code) ? _mn(v) : _num(v);
    final rows = <Widget>[
      Container(
        color: context.vWhite, padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(flex: 4, child: Text('Metric', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
          Expanded(flex: 3, child: Text('LMTD', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
          Expanded(flex: 3, child: Text('MTD', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
          Expanded(flex: 3, child: Text('Growth', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
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
          Expanded(flex: 4, child: Text(_metricLabels[codes[i]] ?? codes[i], style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: context.vInk))),
          Expanded(flex: 3, child: Text(fmt(codes[i], m['lmtd']), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: context.vInk))),
          Expanded(flex: 3, child: Text(fmt(codes[i], m['mtd']), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.vInk))),
          Expanded(flex: 3, child: Text(g == null ? '—' : '${g >= 0 ? '▲' : '▼'} ${NumberFormat('#,##0.0', 'id').format(g.abs())}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: sg(g)))),
        ]),
      ));
    }
    return Column(children: rows);
  }

  Widget _panel(String title, Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: context.vWhite, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title.toUpperCase(), style: TextStyle(fontFamily: 'Poppins', fontSize: 10.5, fontWeight: FontWeight.w700, color: IOH.teal600, letterSpacing: 0.5)),
      const SizedBox(height: 10), child,
    ]),
  );

  Widget _channelMetricTable(List<Map<String, dynamic>> rows) {
    Color sg(num? g) => (g ?? 0) >= 0 ? IOH.teal600 : IOH.danger;
    final widgets = <Widget>[
      Container(color: context.vWhite, padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
        Expanded(flex: 4, child: Text('Channel', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
        Expanded(flex: 3, child: Text('LMTD', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
        Expanded(flex: 3, child: Text('MTD', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
        Expanded(flex: 3, child: Text('Growth', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
      ])),
    ];
    for (var i = 0; i < rows.length; i++) {
      final c = rows[i];
      final g = c['growth'] as num?;
      widgets.add(Container(color: i.isOdd ? context.vZebra : context.vWhite, padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
        Expanded(flex: 4, child: Text((c['channel'] ?? '').toString(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.vInk))),
        Expanded(flex: 3, child: Text(_mn(c['lmtd']), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: context.vInk))),
        Expanded(flex: 3, child: Text(_mn(c['mtd']), textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.vInk))),
        Expanded(flex: 3, child: Text(g == null ? '—' : '${g >= 0 ? '▲' : '▼'} ${NumberFormat('#,##0.0', 'id').format(g.abs())}%', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: sg(g)))),
      ])));
    }
    return Column(children: widgets);
  }

  Widget _channelHistoryTable(List<Map<String, dynamic>> hist) {
    Widget cell(String t, {bool head = false, double w = 90}) => SizedBox(width: w, child: Text(t, textAlign: TextAlign.right, style: TextStyle(fontSize: head ? 9.5 : 11, fontWeight: head ? FontWeight.w700 : FontWeight.w400, color: head ? context.vMute : context.vInk, fontFeatures: const [FontFeature.tabularFigures()])));
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [SizedBox(width: 64, child: Text('Bulan', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: context.vMute))), cell('Organic', head: true), cell('Digital', head: true), cell('MOBO Trade', head: true, w: 96)]),
      ...hist.asMap().entries.map((e) {
        final h = e.value;
        return Container(color: e.key.isOdd ? context.vZebra : context.vWhite, padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
          SizedBox(width: 64, child: Text(h['month_id'].toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.vInk))),
          cell(_mn(h['ORGANIC'])), cell(_mn(h['DIGITAL DISTRIBUTION'])), cell(_mn(h['MOBO TRADE']), w: 96),
        ]));
      }),
    ]));
  }

  Widget _list2(List<Map<String, dynamic>> rows, List<String> Function(Map<String, dynamic>) map) => Column(
    children: rows.asMap().entries.map((e) {
      final kv = map(e.value);
      return Container(
        color: e.key.isOdd ? context.vZebra : context.vWhite,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(children: [
          Expanded(child: Text(kv[0], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: context.vInk), overflow: TextOverflow.ellipsis)),
          Text(kv[1], textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.vInk)),
        ]),
      );
    }).toList(),
  );

  // Full-month table: frozen metric column + scrollable month columns (mirrors MTD).
  Widget _monthlyTable(List<Map<String, dynamic>> hist, List<String> codes) {
    const nameW = 140.0, headH = 28.0, rowH = 34.0, colW = 84.0;
    final months = hist.map((h) => h['month_id'].toString()).toList();
    final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: nameW, height: headH, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Metric', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
      for (var i = 0; i < codes.length; i++)
        Container(width: nameW, height: rowH, color: i.isOdd ? context.vZebra : context.vWhite,
            padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.centerLeft,
            child: Text(_metricLabels[codes[i]] ?? codes[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: context.vInk), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
    Widget cell(String t, {bool head = false, bool bold = false}) => Container(width: colW, height: head ? headH : rowH, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t, style: TextStyle(fontSize: head ? 10 : 11, fontWeight: head ? FontWeight.w700 : (bold ? FontWeight.w700 : FontWeight.w400), color: head ? context.vMute : context.vInk, fontFeatures: const [FontFeature.tabularFigures()])));
    final dataCols = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [for (final m in months) cell(m, head: true)]),
      for (var i = 0; i < codes.length; i++)
        Container(color: i.isOdd ? context.vZebra : context.vWhite, child: Row(children: [
          for (final h in hist) cell(_isRev(codes[i]) ? _mn(h[codes[i]]) : _num(h[codes[i]])),
        ])),
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }

  Widget _monthlyChannelTable(List<Map<String, dynamic>> hist) {
    const nameW = 120.0, headH = 28.0, rowH = 34.0, colW = 84.0;
    final months = hist.map((h) => h['month_id'].toString()).toList();
    const rows = [['ORGANIC', 'Organic'], ['DIGITAL DISTRIBUTION', 'Digital'], ['MOBO TRADE', 'MOBO Trade']];
    final nameCol = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: nameW, height: headH, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('Channel', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute))),
      for (var i = 0; i < rows.length; i++)
        Container(width: nameW, height: rowH, color: i.isOdd ? context.vZebra : context.vWhite, padding: const EdgeInsets.symmetric(horizontal: 8), alignment: Alignment.centerLeft,
            child: Text(rows[i][1], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.vInk))),
    ]);
    Widget cell(String t, {bool head = false}) => Container(width: colW, height: head ? headH : rowH, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(t, style: TextStyle(fontSize: head ? 10 : 11, fontWeight: head ? FontWeight.w700 : FontWeight.w400, color: head ? context.vMute : context.vInk, fontFeatures: const [FontFeature.tabularFigures()])));
    final dataCols = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [for (final m in months) cell(m, head: true)]),
      for (var i = 0; i < rows.length; i++)
        Container(color: i.isOdd ? context.vZebra : context.vWhite, child: Row(children: [for (final h in hist) cell(_mn(h[rows[i][0]]))])),
    ]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      nameCol,
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: dataCols)),
    ]);
  }

}
