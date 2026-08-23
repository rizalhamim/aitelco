import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../format/report_format.dart';
import '../theme.dart';

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

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    final center = pts.isNotEmpty ? LatLng(pts[0].lat, pts[0].lon) : const LatLng(-7.25, 112.75);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: _satellite ? 'Street' : 'Satellite',
            icon: Icon(_satellite ? Icons.map_outlined : Icons.satellite_alt_outlined),
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
                    width: 36, height: 36,
                    child: GestureDetector(
                      onTap: () { setState(() => _selected = i); _mapController.move(LatLng(pts[i].lat, pts[i].lon), 15); },
                      child: Container(
                        decoration: BoxDecoration(
                          color: i == 0 ? IOH.danger : (i == _selected ? IOH.magenta : IOH.teal),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)],
                        ),
                        child: Center(child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
                      ),
                    ),
                  ),
              ]),
            ],
          ),
          if (_selected >= 0 && _selected < pts.length) _detailCard(pts[_selected]),
        ],
      ),
    );
  }

  Widget _detailCard(MapPoint p) {
    return Positioned(
      left: 12, right: 12, bottom: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: IOH.white,
          borderRadius: BorderRadius.circular(16),
          border: const Border(top: BorderSide(color: IOH.red, width: 4)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 16)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(p.label, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 16, color: IOH.ink))),
            IconButton(icon: const Icon(Icons.close, size: 18, color: IOH.mute), onPressed: () => setState(() => _selected = -1)),
          ]),
          Text('${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)}', style: const TextStyle(fontSize: 11, color: IOH.mute)),
          const SizedBox(height: 10),
          ...p.info.entries.where((e) => !['latitude', 'longitude', 'site_name', 'outlet_name'].contains(e.key)).take(8).map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(e.key, style: const TextStyle(fontSize: 12, color: IOH.mute)),
                  Text(_fmt(e.value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: IOH.ink)),
                ]),
              )),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: IOH.teal, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              icon: const Icon(Icons.navigation_outlined, size: 18),
              label: const Text('Buka di Google Maps', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lon}'), mode: LaunchMode.externalApplication),
            ),
          ),
        ]),
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return kReportNotAvailable;
    if (v is num) return reportMagnitude(v, decimals: 1, useThousand: false);
    return v.toString();
  }
}
