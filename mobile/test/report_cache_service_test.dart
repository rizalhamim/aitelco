import 'dart:async';

import 'package:bizplan_java_agent/src/services/report_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    ReportCacheService.I.clear();
    ReportCacheService.I.invalidateIfVersionChanged('reset');
    ReportCacheService.I.clear();
  });

  test('a fetched payload is served from cache on the next call', () async {
    final cache = ReportCacheService.I;
    var calls = 0;
    Future<Map<String, dynamic>> call() async {
      calls++;
      return {'value': calls};
    }

    expect(await cache.fetch('k', call), {'value': 1});
    expect(await cache.fetch('k', call), {'value': 1});
    expect(calls, 1);
    expect(cache.peek('k'), {'value': 1});
  });

  test('concurrent callers join one in-flight request', () async {
    final cache = ReportCacheService.I;
    var calls = 0;
    final gate = Completer<void>();
    Future<Map<String, dynamic>> call() async {
      calls++;
      await gate.future;
      return {'ok': true};
    }

    final a = cache.fetch('slow', call);
    final b = cache.fetch('slow', call);
    expect(cache.isLoading('slow'), isTrue);
    gate.complete();
    await Future.wait([a, b]);

    // One network call, two satisfied callers.
    expect(calls, 1);
    expect(cache.isLoading('slow'), isFalse);
  });

  test('an error payload is returned but never cached', () async {
    final cache = ReportCacheService.I;
    var calls = 0;
    Future<Map<String, dynamic>> call() async {
      calls++;
      return calls == 1 ? {'error': 'boom'} : {'value': 'good'};
    }

    expect(await cache.fetch('e', call), {'error': 'boom'});
    expect(cache.peek('e'), isNull);
    // A transient failure must not poison the key for the session.
    expect(await cache.fetch('e', call), {'value': 'good'});
    expect(cache.peek('e'), {'value': 'good'});
  });

  test('a moved data version drops everything', () async {
    final cache = ReportCacheService.I;
    await cache.fetch('a', () async => {'v': 1});
    expect(cache.invalidateIfVersionChanged('2026-08-19'), isTrue);
    expect(cache.peek('a'), isNull);
    // Same marker again is a no-op, so a repeated check does not thrash.
    await cache.fetch('a', () async => {'v': 2});
    expect(cache.invalidateIfVersionChanged('2026-08-19'), isFalse);
    expect(cache.peek('a'), {'v': 2});
  });

  test('the cache is bounded and evicts the least recently used key', () async {
    final cache = ReportCacheService.I;
    for (var i = 0; i < ReportCacheService.maxEntries; i++) {
      await cache.fetch('k$i', () async => {'i': i});
    }
    // Touch the oldest so it is no longer the eviction candidate.
    expect(cache.peek('k0'), isNotNull);
    await cache.fetch('overflow', () async => {'i': -1});

    expect(cache.peek('k0'), isNotNull);
    expect(cache.peek('k1'), isNull);
    expect(cache.peek('overflow'), isNotNull);
  });
}
