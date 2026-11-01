// 05 Peta Agent (Peta tab): Kab. Garut choropleth of payload MoM, the 14 critical
// sites, the uploaded SHP area and the chat sheet after the area question must
// match the Android mockup. Geometry and metric values are the web fixture's
// (frontend/tools/visual/map-fixture*.mjs/json), generated with the same formulas.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/screens/map_screen.dart';
import 'package:bizplan_java_agent/src/ui/v2.dart';

import 'harness.dart';

double _hash(String s) {
  var h = 2166136261;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
  }
  return (h % 1000) / 1000;
}

double _fx(double v, int d) => double.parse(v.toStringAsFixed(d));

const _urb = {'Garut Kota': 1.0, 'Tarogong Kidul': 1.0, 'Tarogong Kaler': .8, 'Karangpawitan': .8, 'Banyuresmi': .6, 'Cilawu': .6, 'Leles': .5, 'Kadungora': .5, 'Cibatu': .5, 'Bayongbong': .5, 'Wanaraja': .45, 'Samarang': .4, 'Malangbong': .45};
const _lbl = ['Garut Kota', 'Tarogong Kidul', 'Tarogong Kaler', 'Karangpawitan', 'Banyuresmi', 'Cilawu', 'Bayongbong', 'Leles', 'Wanaraja', 'Samarang', 'Cibatu', 'Kadungora', 'Sucinaraja', 'Pasirwangi', 'Cisurupan', 'Sukawening', 'Malangbong', 'Cikajang', 'Leuwigoong', 'Bl. Limbangan'];

Map<String, dynamic> mockupMap() {
  final g = jsonDecode(File('../frontend/tools/visual/map-fixture-geo.json').readAsStringSync()) as Map<String, dynamic>;
  double ur(String n) => _urb[n] ?? .15;
  String status(double v) => v <= -10 ? 'kritis' : v <= -6 ? 'waspada' : 'normal';
  final sites = (g['sites'] as List).cast<Map<String, dynamic>>();
  final units = [
    for (final k in (g['kec'] as List).cast<Map<String, dynamic>>())
      () {
        final n = k['n'] as String, v = (k['v'] as num).toDouble();
        return {
          'n': n, 'd': k['d'], 'cx': k['cx'], 'cy': k['cy'], 'sites': k['sites'], 'status': status(v), 'label': _lbl.contains(n),
          'crit': sites.where((s) => s['crit'] == true && s['k'] == n).length,
          'm': {
            'payload_mom': v,
            'revenue_mom': _fx(v * .45 + (_hash('${n}r') - .5) * 3, 1),
            'availability': _fx(99.05 + _hash('${n}a') * .85 - (v < -10 ? .4 : 0), 2),
            'rev_site': (105 + ur(n) * 120 + _hash('${n}p') * 40).roundToDouble() * 1e6,
            'rgu_site': _fx(.8 + ur(n) * 1.4 + _hash('${n}g') * .4, 2) * 1e3,
            'vlr_site': _fx(1.1 + ur(n) * 1.8 + _hash('${n}v') * .5, 2) * 1e3,
            'market_share': _fx(30 + ur(n) * 14 + _hash('${n}m') * 8, 1),
            'subs': (8 + ur(n) * 80 + _hash('${n}s') * 10).roundToDouble() * 1e3,
            'gross_add': (250 + ur(n) * 1900 + _hash('${n}ga') * 300).roundToDouble(),
            'fwa_pen': _fx(.6 + ur(n) * 3.2 + _hash('${n}f'), 1),
          },
        };
      }(),
  ];
  var ci = 0, ni = 0;
  final outSites = [
    for (final p in sites)
      () {
        final crit = p['crit'] == true;
        final id = crit ? 'GRT-0${400 + ci * 7}' : 'GRT-${1001 + ni}';
        final i = crit ? ci++ : ni++;
        final pm = crit ? -(10.6 + (i == 10 ? 6 : _hash(id) * 4)) : _fx((_hash(id) - .6) * 12, 1);
        return {
          'id': id, 'name': null, 'k': p['k'], 'kab': 'Garut', 'x': p['x'], 'y': p['y'], 'lat': -7.2, 'lon': 107.9, 'crit': crit,
          'status': crit ? 'kritis' : status(pm), 'payload_mom': _fx(pm, 1), 'revenue_mom': _fx(pm * .55, 1), 'availability': 99.4,
        };
      }(),
  ];
  Map<String, dynamic> met(String key, String cat, String name, String short, String kind, String unit, int d, {String? pre, double? scale}) =>
      {'key': key, 'cat': cat, 'name': name, 'short': short, 'kind': kind, 'unit': unit, 'd': d, if (pre != null) 'pre': pre, if (scale != null) 'scale': scale, 'available': true};
  return {
    'scope': {'level': 'kabupaten', 'kabupaten': 'GARUT', 'name': 'Kab. Garut', 'province': 'West Java', 'region': ''},
    'frame': {'w': 748, 'h': 824},
    'month_label': 'Okt 2026', 'month_short': 'Okt', 'unit_level': 'kecamatan',
    'units': units, 'sites': outSites, 'sites_without_coord': 0,
    'neighbors': g['nb'], 'outline': g['outline'],
    'metrics': [
      met('payload_mom', 'perf', 'Payload MoM', 'Payload MoM', 'div', '%', 1),
      met('revenue_mom', 'perf', 'Revenue MoM', 'Rev. MoM', 'div', '%', 1),
      met('availability', 'perf', 'Availability', 'Availability', 'seq', '%', 2),
      met('rev_site', 'prod', 'Revenue / site', 'Rev/site', 'seq', ' jt', 0, pre: 'Rp ', scale: 1e6),
      met('rgu_site', 'prod', 'RGU 90D / site', 'RGU 90D/site', 'seq', ' rb', 2, scale: 1e3),
      met('vlr_site', 'prod', 'VLR / site', 'VLR/site', 'seq', ' rb', 2, scale: 1e3),
      met('market_share', 'prof', 'Market share', 'Market share', 'seq', '%', 1),
      met('subs', 'prof', 'Pelanggan aktif', 'Pelanggan', 'seq', ' rb', 0, scale: 1e3),
      met('gross_add', 'prof', 'Gross add', 'Gross add', 'seq', '', 0),
      met('fwa_pen', 'prof', 'Penetrasi FWA', 'Penetrasi FWA', 'seq', '%', 1),
    ],
    'source': {'kind': 'dump'},
    '_upload': g['upload'],
  };
}

List<Map<String, dynamic>> mockupMessages(Map<String, dynamic> data) {
  final crit = [for (final s in data['sites'] as List) if ((s as Map)['crit'] == true) s['id']];
  final file = {'name': 'area_ekspansi_q1.zip', 'label': 'area_ekspansi_q1.shp', 'kind': 'SHP', 'desc': 'Shapefile', 'size_kb': 48, 'count': '1 poligon'};
  return [
    {'role': 'user', 'text': 'Tampilkan payload MoM per kecamatan di Garut, tandai site yang turun lebih dari 10%'},
    {
      'role': 'agent', 'time': '05.42',
      'text': 'Payload Kab. Garut turun **9,1% MoM**. Paling dalam di **Tarogong Kidul (−14,2%)** dan **Garut Kota (−12,2%)**. Dua layer saya tambahkan ke peta:',
      'layers': [
        {'kind': 'chor', 'metric': 'payload_mom', 'label': 'Choropleth 42 kecamatan'},
        {'kind': 'sites', 'metric': 'payload_mom', 'threshold': -10, 'label': '14 site turun > 10%'},
      ],
      'stats': [], 'actions': [], 'site_ids': crit, 'focus': [418.79, 177.69, 565.51, 398.21],
    },
    {'role': 'user', 'text': 'Berapa site dan revenue di area ini?', 'file': file},
    {
      'role': 'agent', 'time': '05.43',
      'text': 'Area seluas **55,5 km²** ini mencakup Garut Kota, Tarogong Kidul, dan sebagian Karangpawitan.',
      'text_short': 'Area **55,5 km²**: Garut Kota, Tarogong Kidul, sebagian Karangpawitan.',
      'layers': [],
      'stats': [
        {'label': 'Site di area', 'short': 'Site', 'value': '17', 'sub': '5 kritis', 'tone': 'down'},
        {'label': 'Revenue Okt', 'short': 'Revenue', 'value': 'Rp 4,6 M', 'sub': '▼ 6,2% MoM', 'tone': 'down'},
        {'label': 'Payload Okt', 'short': 'Payload', 'value': '392 TB', 'sub': '▼ 12,6% MoM', 'tone': 'down'},
      ],
      'actions': ['sites', 'geojson', 'png'], 'site_ids': List.generate(17, (i) => 'GRT-${1001 + i}'),
      'focus': [390.93, 217.46, 607.07, 391.42],
      'suggestions': ['Site productivity per kecamatan', 'Profile Kec. Tarogong Kidul', 'Revenue MoM di area ini'],
      'suggestions_short': ['Site productivity', 'Profile area', 'Revenue MoM'],
    },
  ];
}

void main() {
  setUp(() => AuthState.user = {'username': 'rizal', 'full_name': 'Rizal Hamim', 'role': 'admin'});

  testWidgets('map', (t) async {
    final data = mockupMap();
    final shape = {
      'name': 'area_ekspansi_q1.zip', 'label': 'area_ekspansi_q1.shp', 'kind': 'SHP', 'desc': 'Shapefile', 'size_kb': 48, 'count': '1 poligon',
      'area_km2': 55.5, 'd': data['_upload'], 'rings': [], 'points': [],
    };
    await matchMockup(
      t,
      name: 'map',
      mockup: 'design/mockup-v2/05-peta-agent/png/Android - Peta Agent@2x.png',
      precache: const ['assets/icon_circle.png'],
      screen: V2Scope(
        alerts: 3,
        openAlerts: ([q]) async {},
        child: Scaffold(
          backgroundColor: V2.bg,
          body: MapScreen(preview: data, previewShape: shape, previewMessages: mockupMessages(data)),
          bottomNavigationBar: V2BottomNav(index: 3, onTap: (_) {}),
        ),
      ),
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('map', Rect.fromLTWH(0, 96, frameW, 256)),
        Region('sheet', Rect.fromLTWH(0, 352, frameW, 392)),
        Region('nav', Rect.fromLTWH(0, 744, frameW, 81)),
      ],
    );
  });
}
