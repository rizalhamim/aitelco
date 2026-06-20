import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../widgets/data_table_view.dart';
import '../widgets/collapsible.dart';
import 'map_page.dart';

Future<(double, double)?> getCurrentCoord(BuildContext context) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aktifkan layanan lokasi (GPS) dulu.')));
    return null;
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Izin lokasi ditolak.')));
    return null;
  }
  try {
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    return (pos.latitude, pos.longitude);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal ambil lokasi: $e')));
    return null;
  }
}

double? _toD(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

List<MapPoint> _points(List<Map<String, dynamic>> rows, String labelKey) {
  final out = <MapPoint>[];
  for (final r in rows) {
    final la = _toD(r['latitude']); final lo = _toD(r['longitude']);
    if (la == null || lo == null) continue;
    out.add(MapPoint(la, lo, (r[labelKey] ?? 'Titik').toString(), r));
  }
  return out;
}

class LocationResultView extends StatelessWidget {
  final Map<String, dynamic> data;
  final String lang;
  const LocationResultView({super.key, required this.data, required this.lang});
  bool get _en => lang == 'en';

  @override
  Widget build(BuildContext context) {
    final prof = data['kec_profile'] as Map<String, dynamic>?;
    final sites = data['sites'] as Map<String, dynamic>?;
    final outlets = data['outlets'] as Map<String, dynamic>?;
    final siteRows = (sites?['rows'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    final outletRows = (outlets?['rows'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    final siteCols = (sites?['columns'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final outletCols = (outlets?['columns'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (prof != null) _kecProfile(context, prof),
      if (siteRows.isNotEmpty) ...[
        _mapButton(context, _en ? 'View 10 Sites on Map' : 'Lihat 10 Site di Peta', _points(siteRows, 'site_name'), IOH.red),
        Collapsible(
          title: _en ? '10 Nearest Sites' : '10 Site Terdekat',
          icon: Icons.cell_tower, accent: IOH.red, badge: '${siteRows.length}',
          child: DataTableView(columns: siteCols, rows: siteRows),
        ),
      ],
      if (outletRows.isNotEmpty) ...[
        _mapButton(context, _en ? 'View 10 Outlets on Map' : 'Lihat 10 Outlet di Peta', _points(outletRows, 'outlet_name'), IOH.teal),
        Collapsible(
          title: _en ? '10 Nearest Outlets' : '10 Outlet Terdekat',
          icon: Icons.store_outlined, accent: IOH.teal, badge: '${outletRows.length}',
          child: DataTableView(columns: outletCols, rows: outletRows),
        ),
      ],
    ]);
  }

  Widget _mapButton(BuildContext context, String label, List<MapPoint> pts, Color color) {
    if (pts.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color, side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.map_outlined, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MapPage(title: label, points: pts))),
      ),
    );
  }

  Widget _kecProfile(BuildContext context, Map<String, dynamic> p) {
    final items = [
      [_en ? 'Total Site' : 'Jumlah Site', p['total_site'], IOH.magenta],
      ['Addressable', p['addressable_site'], IOH.teal],
      [_en ? 'Outlet' : 'Jumlah Outlet', p['total_outlet'], IOH.yellow],
      ['Revenue', p['revenue_prepaid'], IOH.red],
      ['RGU 90d', p['rgu_90d'], IOH.pink],
      ['Gross Add', p['gross_add'], IOH.teal],
      ['Net Add 90d', p['net_add_90d'], IOH.magenta],
      ['HVC Subs', p['subs_hvc'], IOH.yellow],
    ];
    return Collapsible(
      title: _en ? 'Kecamatan Profile' : 'Profil Kecamatan',
      icon: Icons.location_city, accent: IOH.magenta, initiallyExpanded: true,
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final it in items)
          Container(
            width: 104,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.vPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border(top: BorderSide(color: it[2] as Color, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_fmt(it[0] as String, it[1]), style: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: context.vInk)),
              Text((it[0] as String).toUpperCase(), style: TextStyle(fontSize: 9, color: context.vMute, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }

  String _fmt(String key, dynamic v) {
    if (v == null) return '—';
    final n = v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0;
    if (key == 'Revenue') {
      if (n.abs() >= 1e9) return 'Rp${(n / 1e9).toStringAsFixed(2)}M';
      if (n.abs() >= 1e6) return 'Rp${(n / 1e6).toStringAsFixed(1)}Jt';
    }
    return NumberFormat.decimalPattern('id').format(n.round());
  }
}
