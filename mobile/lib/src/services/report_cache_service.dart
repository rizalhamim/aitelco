import 'dart:async';

/// App wide cache for report payloads.
///
/// This lives outside the reports screen state on purpose. A screen-scoped map
/// is dropped the moment the user visits the map or a site, so coming back
/// re-fetched everything. Here the warm data survives navigation for the whole
/// session.
///
/// Two properties matter beyond plain storage:
///
///  * in-flight de-duplication, so a tab switch that lands mid prefetch joins
///    the request already running instead of starting a second one;
///  * a bounded LRU, so sweeping through many territories cannot grow the heap
///    without limit.
class ReportCacheService {
  ReportCacheService._();

  static final ReportCacheService I = ReportCacheService._();

  /// Nine report tabs times a couple of scopes, with room to move back and
  /// forth between two territories without evicting the active set.
  static const int maxEntries = 24;

  final Map<String, Map<String, dynamic>> _entries = {};
  final Map<String, Future<Map<String, dynamic>>> _inflight = {};
  String _dataVersion = '';

  /// Cached payload for [key], or null. Never triggers a fetch.
  Map<String, dynamic>? peek(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    // Touch for LRU: re-inserting moves the key to the end of the map order.
    _entries.remove(key);
    _entries[key] = entry;
    return entry;
  }

  bool contains(String key) => _entries.containsKey(key);

  /// True when a request for [key] is already running.
  bool isLoading(String key) => _inflight.containsKey(key);

  /// Returns the cached payload, the in-flight request, or starts a new one.
  ///
  /// Payloads carrying an `error` key are returned to the caller but never
  /// cached, so a transient failure does not poison the tab for the session.
  Future<Map<String, dynamic>> fetch(
    String key,
    Future<Map<String, dynamic>> Function() call,
  ) {
    final cached = peek(key);
    if (cached != null) return Future<Map<String, dynamic>>.value(cached);

    final running = _inflight[key];
    if (running != null) return running;

    // The callback body must not return the removed entry. Map.remove hands
    // back the stored Future, and whenComplete would then wait on the very
    // future it is completing, which deadlocks the caller.
    final request = call().then((payload) {
      if (payload['error'] == null) _store(key, payload);
      return payload;
    }).whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = request;
    return request;
  }

  void _store(String key, Map<String, dynamic> payload) {
    _entries.remove(key);
    _entries[key] = payload;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Drops everything when the server data marker moves.
  ///
  /// Returns true when the cache was cleared, so the caller knows the screen
  /// has to refetch rather than repaint.
  bool invalidateIfVersionChanged(String version) {
    if (version.isEmpty || version == _dataVersion) return false;
    final hadEntries = _entries.isNotEmpty;
    _dataVersion = version;
    _entries.clear();
    return hadEntries;
  }

  String get dataVersion => _dataVersion;

  void clear() => _entries.clear();
}
