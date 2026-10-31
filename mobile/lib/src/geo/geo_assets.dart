import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';

/// One choropleth-able region polygon loaded from the bundled GeoJSON.
class GeoFeature {
  final String id; // kec_id or kabkot_id (UPPER)
  final String label;
  final Map<String, dynamic> props;
  final List<GeoPolygon> parts;
  List<List<LatLng>> get rings => parts.map((part) => part.points).toList();
  GeoFeature(this.id, this.label, this.props, this.parts);
}

class GeoPolygon {
  final List<LatLng> points;
  final List<List<LatLng>> holes;
  GeoPolygon(this.points, this.holes);

  bool contains(LatLng point) =>
      (pointOnRing(point, points) || pointInRing(point, points)) &&
      !holes
          .any((hole) => !pointOnRing(point, hole) && pointInRing(point, hole));

  static bool pointOnRing(LatLng point, List<LatLng> ring) {
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      final cross =
          (point.longitude - a.longitude) * (b.latitude - a.latitude) -
              (point.latitude - a.latitude) * (b.longitude - a.longitude);
      if (cross.abs() <= 1e-10 &&
          point.longitude >=
              (a.longitude < b.longitude ? a.longitude : b.longitude) - 1e-10 &&
          point.longitude <=
              (a.longitude > b.longitude ? a.longitude : b.longitude) + 1e-10 &&
          point.latitude >=
              (a.latitude < b.latitude ? a.latitude : b.latitude) - 1e-10 &&
          point.latitude <=
              (a.latitude > b.latitude ? a.latitude : b.latitude) + 1e-10) {
        return true;
      }
    }
    return false;
  }

  static bool pointInRing(LatLng point, List<LatLng> ring) {
    var inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i], b = ring[j];
      if ((a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }
}

class GeoAssets {
  static final Map<String, List<GeoFeature>> _cache = {};
  static Map<String, Map<String, dynamic>>? _terrMap;

  /// kecamatan kec_id -> operational area/district, with legacy aliases.
  static Future<Map<String, Map<String, dynamic>>> territoryMap() async {
    if (_terrMap != null) return _terrMap!;
    final bytes = await rootBundle.load('assets/geo/territory_map.json.gz');
    final raw = gzip.decode(bytes.buffer.asUint8List());
    final m = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    _terrMap = m.map((k, v) =>
        MapEntry(k.toUpperCase(), (v as Map).cast<String, dynamic>()));
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
      final props =
          (f['props'] ?? f['properties'] ?? {}) as Map<String, dynamic>;
      final id = (props[idKey] ?? '').toString().toUpperCase();
      if (id.isEmpty) continue;
      final geom = f['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;
      final rings = parseGeometry(geom);
      if (rings.isEmpty) continue;
      feats.add(
          GeoFeature(id, (props[labelKey] ?? id).toString(), props, rings));
    }
    _cache[level] = feats;
    return feats;
  }

  static List<GeoPolygon> parseGeometry(Map<String, dynamic> geom) {
    final type = geom['type'];
    final coords = geom['coordinates'];
    final out = <GeoPolygon>[];
    void addPart(List rings) {
      if (rings.isEmpty) return;
      final outer = _ring(rings.first as List);
      if (outer.length < 4) return;
      final holes = rings
          .skip(1)
          .map((ring) => _ring(ring as List))
          .where((ring) => ring.length >= 4)
          .toList();
      out.add(GeoPolygon(outer, holes));
    }

    if (type == 'Polygon') {
      addPart(coords as List);
    } else if (type == 'MultiPolygon') {
      for (final poly in (coords as List)) {
        addPart(poly as List);
      }
    }
    return out;
  }

  static List<LatLng> _ring(List coords) {
    return coords
        .map<LatLng>(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
  }
}
