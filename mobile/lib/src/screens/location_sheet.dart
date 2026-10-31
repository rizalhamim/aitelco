import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../widgets/data_table_view.dart';
import '../widgets/collapsible.dart';
import '../widgets/report_ui.dart';
import '../format/report_format.dart';
import 'map_page.dart';

class LocationFix {
  final double latitude, longitude, accuracy;
  final DateTime timestamp;
  const LocationFix(
      this.latitude, this.longitude, this.accuracy, this.timestamp);
}

Future<LocationFix?> getCurrentLocationFix(BuildContext context) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Aktifkan layanan lokasi (GPS) dulu.'),
          action: SnackBarAction(
              label: 'Pengaturan',
              onPressed: Geolocator.openLocationSettings)));
    }
    return null;
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Izin lokasi ditolak.'),
          action: SnackBarAction(
              label: 'Pengaturan', onPressed: Geolocator.openAppSettings)));
    }
    return null;
  }
  try {
    final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    if (!pos.latitude.isFinite ||
        !pos.longitude.isFinite ||
        pos.latitude.abs() > 90 ||
        pos.longitude.abs() > 180) {
      return null;
    }
    return LocationFix(
        pos.latitude, pos.longitude, pos.accuracy, pos.timestamp);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal ambil lokasi: $e')));
    }
    return null;
  }
}

Future<(double, double)?> getCurrentCoord(BuildContext context) async {
  final fix = await getCurrentLocationFix(context);
  return fix == null ? null : (fix.latitude, fix.longitude);
}

double? _toD(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

List<MapPoint> _points(List<Map<String, dynamic>> rows, String labelKey) {
  final out = <MapPoint>[];
  for (final r in rows) {
    final la = _toD(r['latitude']);
    final lo = _toD(r['longitude']);
    if (la == null ||
        lo == null ||
        !la.isFinite ||
        !lo.isFinite ||
        la.abs() > 90 ||
        lo.abs() > 180) {
      continue;
    }
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
    final siteRows = (sites?['rows'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final outletRows = (outlets?['rows'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final siteCols =
        (sites?['columns'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final outletCols =
        (outlets?['columns'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (prof != null) _kecProfile(context, prof),
      if (siteRows.isNotEmpty) ...[
        _mapButton(
            context,
            _en
                ? 'View ${siteRows.length} Sites on Map'
                : 'Lihat ${siteRows.length} Site di Peta',
            _points(siteRows, 'site_name'),
            IOH.red),
        Collapsible(
          title: _en ? 'Nearest Sites' : 'Site Terdekat',
          icon: Icons.cell_tower,
          accent: IOH.red,
          badge: '${siteRows.length}',
          child: DataTableView(columns: siteCols, rows: siteRows),
        ),
      ],
      if (outletRows.isNotEmpty) ...[
        _mapButton(
            context,
            _en
                ? 'View ${outletRows.length} Outlets on Map'
                : 'Lihat ${outletRows.length} Outlet di Peta',
            _points(outletRows, 'outlet_name'),
            IOH.teal),
        Collapsible(
          title: _en ? 'Nearest Outlets' : 'Outlet Terdekat',
          icon: Icons.store_outlined,
          accent: IOH.teal,
          badge: '${outletRows.length}',
          child: DataTableView(columns: outletCols, rows: outletRows),
        ),
      ],
      if (sites?['error'] != null || outlets?['error'] != null)
        Text(
            'Sebagian data lokasi belum tersedia: ${sites?['error'] ?? outlets?['error']}',
            style: TextStyle(color: context.vMute)),
    ]);
  }

  Widget _mapButton(
      BuildContext context, String label, List<MapPoint> pts, Color color) {
    if (pts.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.map_outlined, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MapPage(title: label, points: pts))),
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
      icon: Icons.location_city,
      accent: IOH.magenta,
      initiallyExpanded: true,
      child: Column(children: [
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 480 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.4
              ? 3
              : 2;
          final cardWidth =
              (constraints.maxWidth - 8 * (columns - 1)) / columns;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final it in items)
              Container(
                width: cardWidth,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.vPanel,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border(top: BorderSide(color: it[2] as Color, width: 3)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmt(it[0] as String, it[1]),
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: context.vInk)),
                      Text(it[0] as String,
                          style: TextStyle(
                              fontSize: 12,
                              color: context.vMute,
                              fontWeight: FontWeight.w600)),
                    ]),
              ),
          ]);
        }),
        Collapsible(
            title: _en ? 'All profile fields' : 'Seluruh detail profil',
            icon: Icons.list_alt,
            accent: IOH.teal,
            child: ReportAttributeTable(stackedBreakpoint: 320, attributes: [
              for (final e in p.entries)
                ReportAttribute(
                    label: e.key.replaceAll('_', ' '),
                    value: e.value?.toString() ?? kReportNotAvailable),
            ])),
      ]),
    );
  }

  String _fmt(String key, dynamic v) {
    if (v == null) return kReportNotAvailable;
    final n = _toD(v);
    if (n == null || !n.isFinite) return kReportNotAvailable;
    if (key == 'Revenue') {
      if (n.abs() >= 1e9) return 'Rp${(n / 1e9).toStringAsFixed(2)}M';
      if (n.abs() >= 1e6) return 'Rp${(n / 1e6).toStringAsFixed(1)}Jt';
    }
    return NumberFormat.decimalPattern('id').format(n.round());
  }
}
