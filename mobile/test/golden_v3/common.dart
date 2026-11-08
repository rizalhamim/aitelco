// Agent Java v3 Android visual gate: each screen is rendered in the mockup frame
// (test/golden_v2/harness.dart) with the same data as the web gate
// (fixtures.json, exported from frontend/tools/visual/v3-fixtures.mjs) and
// compared with design/mockup-v3/png/<feature>/Android - <title>@2x.png.
//
//   flutter test test/golden_v3
import 'dart:convert';
import 'dart:io';

import 'package:bizplan_java_agent/src/api/api_client.dart';
import 'package:bizplan_java_agent/src/screens/v3/v3_nav.dart';

Map<String, dynamic>? _all;

/// A deep copy of one fixture route, so a test can adapt it to the phone copy.
Map<String, dynamic> fixture(String route) {
  _all ??= json.decode(File('test/golden_v3/fixtures.json').readAsStringSync()) as Map<String, dynamic>;
  return json.decode(json.encode(_all![route])) as Map<String, dynamic>;
}

void v3Setup() {
  AuthState.user = {'username': 'rizal', 'full_name': 'Rizal Hamim', 'role': 'admin'};
  V3Nav.alerts = 3;
}

const m3 = 'design/mockup-v3/png';
