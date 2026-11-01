// 09 Statistik aplikasi (Android, opened from Profil > Admin): KPI tiles, charts,
// access requests, feature use, heatmap, access list and security must match the mockup.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/screens/stats_screen.dart';

import 'harness.dart';

/// Same seeded numbers as the web gate (frontend/tools/visual/stats-fixture.mjs).
/// The Android mockup lists Rizal, Dewi, Bayu, Sari and Hendra first.
Map<String, dynamic> mockupStats() {
  final src = File('../frontend/tools/visual/stats-fixture.mjs').readAsStringSync();
  final start = src.indexOf('{'), end = src.lastIndexOf('}');
  final data = json.decode(src.substring(start, end + 1)) as Map<String, dynamic>;
  final users = (data['users'] as List).cast<Map<String, dynamic>>();
  final andi = users.firstWhere((u) => u['full_name'] == 'Andi Saputra');
  users.remove(andi);
  users.insert(5, andi);
  return data;
}

void main() {
  setUp(() => AuthState.user = {'username': 'rizal', 'full_name': 'Rizal', 'role': 'admin'});

  testWidgets('statistik', (t) async {
    final data = mockupStats();
    await matchMockup(
      t,
      name: 'statistik',
      mockup: 'design/mockup-v2/09-statistik-unduh/png/Android - Statistik@2x.png',
      screen: StatsScreen(preview: data, previewNow: DateTime.parse(data['generated_at'] as String)),
      regions: const [
        Region('appbar', Rect.fromLTWH(0, 0, frameW, 96)),
        Region('kpi', Rect.fromLTWH(0, 96, frameW, 346)),
        Region('dau', Rect.fromLTWH(0, 448, frameW, 276)),
        Region('pending', Rect.fromLTWH(0, 724, frameW, 288)),
        Region('fitur', Rect.fromLTWH(0, 1012, frameW, 312)),
        Region('heat', Rect.fromLTWH(0, 1324, frameW, 200)),
        Region('adopsi', Rect.fromLTWH(0, 1524, frameW, 266)),
        Region('unduh', Rect.fromLTWH(0, 1790, frameW, 256)),
        Region('akses', Rect.fromLTWH(0, 2046, frameW, 418)),
        Region('keamanan', Rect.fromLTWH(0, 2464, frameW, 216)),
        Region('nav', Rect.fromLTWH(0, 2680, frameW, 81)),
      ],
    );
  });
}
