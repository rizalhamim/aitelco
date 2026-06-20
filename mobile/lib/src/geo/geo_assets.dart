import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

/// One choropleth-able region polygon loaded from the bundled GeoJSON.
class GeoFeature {
  final String id; // kec_id or kabkot_id (UPPER)
  final String label;
  final Map<String, dynamic> props;
  final List<List<LatLng>> rings; // exterior rings (multipolygon flattened)
  GeoFeature(this.id, this.label, this.props, this.rings);
}

class GeoAssets {
  static final Map<String, List<GeoFeature>> _cache = {};
  static Map<String, Map<String, dynamic>>? _terrMap;

  /// kecamatan kec_id -> {kabkota, province, region, circle, area, branch}
  static Future<Map<String, Map<String, dynamic>>> territoryMap() async {
    if (_terrMap != null) return _terrMap!;
    final bytes = await rootBundle.load('assets/geo/territory_map.json.gz');
    final raw = gzip.decode(bytes.buffer.asUint8List());
    final m = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    _terrMap = m.map((k, v) => MapEntry(k.toUpperCase(), (v as Map).cast<String, dynamic>()));
    return _terrMap!;
  }

  /// level = 'kecamatan' (idKey kec_id) or 'kabupaten' (idKey kabkot_id)
  static Future<List<GeoFeature>> load(String level) async {
    if (_cache.containsKey(level)) return _cache[level]!;
    final idKey = level == 'kecamatan' ? 'kec_id' : 'kabkot_id';
    final labelKey = level == 'kecamatan' ? 'kecamatan' : 'kabupaten';
    final bytes = await rootBundle.load('assets/geo/$level.geojson.gz');
    final raw = gzip.decode(bytes.buffer.asUint8List());
    final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    final feats = <GeoFeature>[];
    for (final f in (json['features'] as List)) {
      final props = (f['props'] ?? f['properties'] ?? {}) as Map<String, dynamic>;
      final id = (props[idKey] ?? '').toString().toUpperCase();
      if (id.isEmpty) continue;
      final geom = f['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;
      final rings = _parseGeom(geom);
      if (rings.isEmpty) continue;
      feats.add(GeoFeature(id, (props[labelKey] ?? id).toString(), props, rings));
    }
    _cache[level] = feats;
    return feats;
  }

  static List<List<LatLng>> _parseGeom(Map<String, dynamic> geom) {
    final type = geom['type'];
    final coords = geom['coordinates'];
    final out = <List<LatLng>>[];
    if (type == 'Polygon') {
      out.add(_ring((coords as List).first as List));
    } else if (type == 'MultiPolygon') {
      for (final poly in (coords as List)) {
        out.add(_ring((poly as List).first as List));
      }
    }
    return out;
  }

  static List<LatLng> _ring(List coords) {
    return coords
        .map<LatLng>((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
  }
}
