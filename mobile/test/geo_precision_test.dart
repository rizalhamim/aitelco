import 'package:bizplan_java_agent/src/geo/geo_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  final geometry = <String, dynamic>{
    'type': 'Polygon',
    'coordinates': [
      [
        [0, 0],
        [4, 0],
        [4, 4],
        [0, 4],
        [0, 0]
      ],
      [
        [1, 1],
        [3, 1],
        [3, 3],
        [1, 3],
        [1, 1]
      ],
    ],
  };
  test('polygon retains holes and excludes their interiors', () {
    final parts = GeoAssets.parseGeometry(geometry);
    expect(parts.length, 1);
    expect(parts.single.holes.length, 1);
    expect(parts.single.contains(const LatLng(.5, .5)), isTrue);
    expect(parts.single.contains(const LatLng(2, 2)), isFalse);
    expect(parts.single.contains(const LatLng(5, 5)), isFalse);
  });
  test('polygon boundaries agree with server covers semantics', () {
    final polygon = GeoAssets.parseGeometry(geometry).single;
    expect(polygon.contains(const LatLng(0, 2)), isTrue);
    expect(polygon.contains(const LatLng(2, 1)), isTrue);
  });
  test('multipolygon preserves each part and its holes', () {
    final parts = GeoAssets.parseGeometry({
      'type': 'MultiPolygon',
      'coordinates': [
        geometry['coordinates'],
        [
          [
            [6, 0],
            [8, 0],
            [8, 2],
            [6, 2],
            [6, 0]
          ]
        ]
      ],
    });
    expect(parts.length, 2);
    expect(parts.first.holes.length, 1);
    expect(parts.last.contains(const LatLng(1, 7)), isTrue);
  });
}
