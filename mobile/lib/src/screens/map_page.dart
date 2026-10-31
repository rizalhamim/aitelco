import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../format/report_format.dart';
import '../theme.dart';
import '../widgets/report_ui.dart';

class MapPoint {
  final double lat, lon;
  final String label;
  final Map<String, dynamic> info;
  MapPoint(this.lat, this.lon, this.label, this.info);
}

/// Full-screen map page with markers, tooltips, satellite/street toggle.
class MapPage extends StatefulWidget {
  final String title;
  final List<MapPoint> points;
  const MapPage({super.key, required this.title, required this.points});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  bool _satellite = true;
  int _selected = 0;
  final _mapController = MapController();
  List<MapPoint> get _validPoints => widget.points
      .where((p) =>
          p.lat.isFinite &&
          p.lon.isFinite &&
          p.lat.abs() <= 90 &&
          p.lon.abs() <= 180)
      .toList();

  void _fitResults() {
    final pts = _validPoints;
    if (pts.isEmpty) return;
    _mapController.fitCamera(CameraFit.coordinates(
      coordinates: pts.map((p) => LatLng(p.lat, p.lon)).toList(),
      padding: EdgeInsets.fromLTRB(48, 48, 48,
          _selected >= 0 ? MediaQuery.sizeOf(context).height * .36 : 48),
      maxZoom: 16,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pts = _validPoints;
    final center = pts.isNotEmpty
        ? LatLng(pts[0].lat, pts[0].lon)
        : const LatLng(-2.5, 118);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        actions: [
          IconButton(
              tooltip: 'Tampilkan semua titik',
              icon: const Icon(Icons.fit_screen),
              onPressed: pts.isEmpty ? null : _fitResults),
          IconButton(
            tooltip: _satellite ? 'Street' : 'Satellite',
            icon: Icon(
                _satellite ? Icons.map_outlined : Icons.satellite_alt_outlined),
            onPressed: () => setState(() => _satellite = !_satellite),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14,
              onMapReady: _fitResults,
              onTap: (_, __) => setState(() => _selected = -1),
            ),
            children: [
              TileLayer(
                urlTemplate: _satellite
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.bizplan.bizplan_java_agent',
              ),
              MarkerLayer(markers: [
                for (int i = 0; i < pts.length; i++)
                  Marker(
                    point: LatLng(pts[i].lat, pts[i].lon),
                    width: 48,
                    height: 48,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() => _selected = i);
                      },
                      child: Container(
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: i == _selected ? IOH.magenta : IOH.teal,
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
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800))),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
          if (pts.length != widget.points.length || pts.isEmpty)
            Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Card(
                    child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(pts.isEmpty
                      ? 'Tidak ada koordinat valid untuk dipetakan.'
                      : '${widget.points.length - pts.length} koordinat tidak valid. Data asal tetap tersedia di tabel.'),
                ))),
          if (_selected >= 0 && _selected < pts.length)
            _detailCard(pts[_selected]),
        ],
      ),
    );
  }

  Widget _detailCard(MapPoint p) {
    return DraggableScrollableSheet(
      initialChildSize: .34,
      minChildSize: .18,
      maxChildSize: .8,
      builder: (context, controller) => Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
            top: false,
            child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Center(
                      child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                              color: context.vRule,
                              borderRadius: BorderRadius.circular(4)))),
                  Row(children: [
                    Expanded(
                        child: Text(p.label,
                            style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(
                        tooltip: 'Tutup detail',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _selected = -1)),
                  ]),
                  SelectableText(
                      '${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}',
                      style: TextStyle(fontSize: 12, color: context.vMute)),
                  const SizedBox(height: 10),
                  ReportAttributeTable(stackedBreakpoint: 320, attributes: [
                    for (final e in p.info.entries)
                      ReportAttribute(
                          label: e.key.replaceAll('_', ' '),
                          value: _fmt(e.key, e.value)),
                  ]),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: IOH.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.navigation_outlined, size: 18),
                      label: const Text('Buka di Google Maps',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () => launchUrl(
                          Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lon}'),
                          mode: LaunchMode.externalApplication),
                    ),
                  ),
                ])),
      ),
    );
  }

  String _fmt(String key, dynamic v) {
    if (v == null) return kReportNotAvailable;
    if (v is num) return reportValueForKey(key, v);
    return v.toString();
  }
}
