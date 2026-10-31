import 'dart:async';
import 'dart:convert';

import 'package:bizplan_java_agent/src/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final base = Uri.parse('https://agent.bizplan-java.com');
  final release = {
    'version_name': '1.48.1',
    'version_code': 64,
    'available': true,
    'download_url': '/api/app/download',
    'notes': 'Perbaikan update',
    'size_bytes': 100,
    'mandatory': false,
  };

  Future<UpdateInfo?> check(Map<String, dynamic> data, {int current = 62}) {
    return UpdateService.checkVersion(
      currentCode: current,
      baseUri: base,
      client: MockClient((request) async {
        expect(request.url, base.resolve('/api/app/version'));
        expect(request.headers['Cache-Control'], 'no-cache');
        return http.Response(jsonEncode(data), 200);
      }),
    );
  }

  test('legacy installed build receives available new release', () async {
    final info = await check(release);
    expect(info?.versionCode, 64);
    expect((await check(release, current: 63))?.versionCode, 64);
    expect(
        info?.downloadUrl, 'https://agent.bizplan-java.com/api/app/download');
  });
  test('same or newer installed build is up to date', () async {
    expect(await check(release, current: 64), isNull);
    expect(await check(release, current: 65), isNull);
  });
  test('unavailable newer APK is not reported as up to date', () async {
    await expectLater(check({...release, 'available': false}),
        throwsA(isA<UpdateCheckException>()));
  });
  test('absolute HTTPS download supports clients using the legacy host',
      () async {
    final info = await UpdateService.checkVersion(
      currentCode: 62,
      baseUri: Uri.parse('http://agent-02.bizplan-java.com:8000'),
      client: MockClient((_) async => http.Response(
          jsonEncode({
            ...release,
            'download_url': 'https://agent.bizplan-java.com/api/app/download',
          }),
          200)),
    );
    expect(
        info?.downloadUrl, 'https://agent.bizplan-java.com/api/app/download');
  });
  test('HTTP errors are explicit failures', () async {
    await expectLater(
        UpdateService.checkVersion(
          currentCode: 62,
          baseUri: base,
          client: MockClient((_) async => http.Response('Unavailable', 503)),
        ),
        throwsA(isA<UpdateCheckException>()));
  });
  test('HTML login response is not mistaken for up to date', () async {
    await expectLater(
        UpdateService.checkVersion(
          currentCode: 62,
          baseUri: base,
          client:
              MockClient((_) async => http.Response('<html>login</html>', 200)),
        ),
        throwsA(isA<UpdateCheckException>()));
  });
  test('missing or invalid version metadata is an explicit failure', () async {
    for (final version in [null, '64', 0, 64.5]) {
      await expectLater(check({...release, 'version_code': version}),
          throwsA(isA<UpdateCheckException>()));
    }
  });
  test('connection timeout is not mistaken for up to date', () async {
    await expectLater(
        UpdateService.checkVersion(
          currentCode: 62,
          baseUri: base,
          client: MockClient((_) async => throw TimeoutException('offline')),
        ),
        throwsA(isA<UpdateCheckException>()));
  });
}
