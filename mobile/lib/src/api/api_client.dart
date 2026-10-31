import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// Identifies this install to the backend (X-Client-Platform, X-App-Version,
/// X-App-Build, X-Device-Model, X-OS-Version) so admin Statistik can show
/// versions and devices. Filled once at startup; every request sends it.
class ClientInfo {
  static final Map<String, String> headers = {'X-Client-Platform': 'android'};

  static Future<void> init() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      headers['X-App-Version'] = pkg.version;
      headers['X-App-Build'] = pkg.buildNumber;
    } catch (_) {}
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        final maker = a.manufacturer.isEmpty ? '' : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
        headers['X-Device-Model'] = '$maker${a.model}'.trim();
        headers['X-OS-Version'] = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
      }
    } catch (_) {}
  }
}

class AuthState {
  static String? accessToken;
  static String? refreshToken;
  static Map<String, dynamic>? user;

  static bool remember = false;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    remember = p.getBool('remember') ?? false;
    final loginAt = p.getInt('login_at') ?? 0;
    final ageMs = DateTime.now().millisecondsSinceEpoch - loginAt;
    // Session valid for max 24h unless "remember me" was checked.
    final expired = !remember && ageMs > 24 * 60 * 60 * 1000;
    if (expired) {
      await clear();
      return;
    }
    accessToken = p.getString('access_token');
    refreshToken = p.getString('refresh_token');
    final u = p.getString('user');
    if (u != null) {
      try {
        user = jsonDecode(u) as Map<String, dynamic>;
      } catch (_) {}
    }
  }

  static Future<void> save(Map<String, dynamic> data,
      {bool rememberMe = false}) async {
    final p = await SharedPreferences.getInstance();
    accessToken = data['access_token'] as String?;
    refreshToken = data['refresh_token'] as String?;
    user = data['user'] as Map<String, dynamic>?;
    remember = rememberMe;
    if (accessToken != null) await p.setString('access_token', accessToken!);
    if (refreshToken != null) await p.setString('refresh_token', refreshToken!);
    if (user != null) await p.setString('user', jsonEncode(user));
    await p.setBool('remember', rememberMe);
    await p.setInt('login_at', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> mergeUser(Map<String, dynamic> data) async {
    user ??= {};
    user!.addAll(data);
    final p = await SharedPreferences.getInstance();
    await p.setString('user', jsonEncode(user));
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('access_token');
    await p.remove('refresh_token');
    await p.remove('user');
    accessToken = refreshToken = null;
    user = null;
  }

  static bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;
  static bool get isAdmin => (user?['role']) == 'admin';
  static String get role => (user?['role'] as String?) ?? 'end_user';
  static bool get canViewSql => role == 'admin' || role == 'analyst';
  static bool get canExport =>
      role == 'admin' || role == 'analyst' || role == 'data_user';
}

class ApiClient {
  static String get base => AppConfig.apiBase;

  static Map<String, String> _headers({bool json = true}) {
    final h = <String, String>{...ClientInfo.headers};
    if (json) h['Content-Type'] = 'application/json';
    if (AuthState.accessToken != null) {
      h['Authorization'] = 'Bearer ${AuthState.accessToken}';
    }
    return h;
  }

  /// Exchange the stored refresh token for a fresh access token. The mobile
  /// access token expires after 8h; without this, after expiry the history API
  /// returns 401 (empty history) and new chats get saved with no owner. Returns
  /// true if a new access token was obtained.
  /// Called once when the stored session can no longer be renewed (the refresh
  /// token was rejected). main.dart routes to the login screen from here, so an
  /// expired session asks the user to sign in again instead of failing every call.
  static void Function()? onSessionExpired;
  static bool _expiring = false;

  static Future<void> _expireSession() async {
    if (_expiring) return;
    _expiring = true;
    try {
      await AuthState.clear();
      onSessionExpired?.call();
    } finally {
      _expiring = false;
    }
  }

  static Future<bool> refreshAccessToken() async {
    final rt = AuthState.refreshToken;
    if (rt == null || rt.isEmpty) return false;
    try {
      final res = await http.post(Uri.parse('$base/api/auth/refresh'),
          headers: {...ClientInfo.headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': rt}));
      if (res.statusCode == 401) {
        await _expireSession();
        return false;
      }
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final at = data['access_token'] as String?;
      if (at == null || at.isEmpty) return false;
      AuthState.accessToken = at;
      final p = await SharedPreferences.getInstance();
      await p.setString('access_token', at);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Authenticated GET that transparently refreshes the access token once on a
  /// 401 (expired token) and retries, so history & other authed reads keep
  /// working across the 8h token lifetime.
  static Future<http.Response> _authGet(Uri uri) async {
    var res = await http.get(uri, headers: _headers());
    if (res.statusCode == 401 && await refreshAccessToken()) {
      res = await http.get(uri, headers: _headers());
    }
    return res;
  }

  static Future<Map<String, dynamic>> requestLoginToken(
      String username, String password) async {
    final res = await http.post(Uri.parse('$base/api/auth/login/request-token'),
        headers: {...ClientInfo.headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Gagal meminta token');
    }
    return data;
  }

  static Future<Map<String, dynamic>> verifyLoginToken(
      String username, String code,
      {bool rememberMe = false}) async {
    final res = await http.post(Uri.parse('$base/api/auth/login/verify'),
        headers: {...ClientInfo.headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'code': code}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Verifikasi gagal');
    }
    await AuthState.save(data, rememberMe: rememberMe);
    return data;
  }

  static Future<String> forgotPassword(String email) async {
    final res = await http.post(Uri.parse('$base/api/auth/forgot-password'),
        headers: {...ClientInfo.headers, 'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception(data['detail'] ?? 'Gagal');
    return (data['message'] ?? 'Link reset password telah dikirim.').toString();
  }

  static Future<List<dynamic>> domains() async {
    final res = await _authGet(Uri.parse('$base/api/domains'));
    final d = jsonDecode(res.body);
    return (d is Map && d['domains'] is List)
        ? d['domains'] as List
        : (d is List ? d : []);
  }

  // ── Daily Reports ──
  static Future<Map<String, dynamic>> reportMetrics() async {
    final res = await _authGet(Uri.parse('$base/api/reports/metrics'));
    if (res.statusCode != 200) {
      return {'metrics': [], 'categories': [], 'circles': []};
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> reportSnapshot({
    required String metric,
    String circle = 'JAVA',
    String filterType = 'all',
    String filterValue = '',
    int? monthId,
  }) async {
    final q = <String, String>{
      'metric': metric,
      'circle': circle,
      'filter_type': filterType,
      if (filterValue.isNotEmpty) 'filter_value': filterValue,
      if (monthId != null) 'month_id': '$monthId',
    };
    final uri =
        Uri.parse('$base/api/reports/snapshot').replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat laporan');
    }
    return data;
  }

  static Future<Map<String, dynamic>> reportMapExplore({
    required String metric,
    String circle = 'JAVA',
    String level = 'kecamatan',
    String brand = 'ioh',
    String valueMode = 'growth',
  }) async {
    final uri = Uri.parse('$base/api/reports/map-explore').replace(
      queryParameters: {
        'metric': metric,
        'circle': circle,
        'level': level,
        'brand': brand,
        'value_mode': valueMode,
      },
    );
    final res = await _authGet(uri).timeout(const Duration(seconds: 90));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat data map');
    }
    return data;
  }

  static Future<Map<String, dynamic>> appVersion() async {
    final res = await http
        .get(Uri.parse('$base/api/app/version'), headers: ClientInfo.headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> reportCacheClear() async {
    try {
      final uri = Uri.parse('$base/api/reports/cache/clear');
      var res = await http.post(uri, headers: _headers());
      if (res.statusCode == 401 && await refreshAccessToken()) {
        res = await http.post(uri, headers: _headers());
      }
    } catch (_) {}
  }

  static Future<String> reportDataVersion() async {
    try {
      final res = await _authGet(Uri.parse('$base/api/reports/data-version'));
      if (res.statusCode != 200) return '';
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      const families = [
        'highlevel',
        'data',
        'benchmark',
        'fwa',
        'ftth-summary',
        'network-catalog',
      ];
      return families.map((family) => '$family:${d[family] ?? ''}').join('|');
    } catch (_) {
      return '';
    }
  }

  static Future<List<String>> reportScopeOptions(
      {String circle = 'JAVA', String level = 'region'}) async {
    final uri = Uri.parse('$base/api/reports/scope-options')
        .replace(queryParameters: {'circle': circle, 'level': level});
    final res = await _authGet(uri);
    if (res.statusCode != 200) return [];
    final d = jsonDecode(res.body);
    final vals = (d is Map && d['values'] is List) ? d['values'] as List : [];
    return vals.map((e) => e.toString()).toList();
  }

  static Future<List<String>> reportFtthScopeOptions(
      {String circle = 'JAVA', String level = 'ftth_region'}) async {
    final uri = Uri.parse('$base/api/reports/ftth/scope-options')
        .replace(queryParameters: {'circle': circle, 'level': level});
    final res = await _authGet(uri);
    if (res.statusCode != 200) return [];
    final d = jsonDecode(res.body);
    final vals = (d is Map && d['values'] is List) ? d['values'] as List : [];
    return vals.map((e) => e.toString()).toList();
  }

  static Future<Map<String, dynamic>> reportLocate(
      {required double lat, required double lon}) async {
    final uri = Uri.parse('$base/api/reports/locate')
        .replace(queryParameters: {'lat': '$lat', 'lon': '$lon'});
    final res = await _authGet(uri);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> reportMyCoordinate(
      {required double lat, required double lon, int? monthId}) async {
    final q = <String, String>{
      'lat': '$lat',
      'lon': '$lon',
      if (monthId != null) 'month_id': '$monthId'
    };
    final uri = Uri.parse('$base/api/reports/my-coordinate')
        .replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat My Coordinate');
    }
    return data;
  }

  static Future<Map<String, dynamic>> reportComprehensive({
    String circle = 'JAVA',
    String filterType = 'all',
    String filterValue = '',
    int? monthId,
  }) async {
    final q = <String, String>{
      'circle': circle,
      'filter_type': filterType,
      if (filterValue.isNotEmpty) 'filter_value': filterValue,
      if (monthId != null) 'month_id': '$monthId',
    };
    final uri = Uri.parse('$base/api/reports/comprehensive')
        .replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat laporan');
    }
    return data;
  }

  static Future<Map<String, dynamic>> reportDataRevenue(
      {String circle = 'JAVA',
      String brand = 'ioh',
      String filterType = 'all',
      String filterValue = '',
      int? monthId}) async {
    final q = <String, String>{
      'circle': circle,
      'brand': brand,
      'filter_type': filterType,
      if (filterValue.isNotEmpty) 'filter_value': filterValue,
      if (monthId != null) 'month_id': '$monthId'
    };
    final uri =
        Uri.parse('$base/api/reports/data-revenue').replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat laporan');
    }
    return data;
  }

  static Future<Map<String, dynamic>> reportProductDemand(
      {String circle = 'JAVA',
      String scope = 'total',
      String brand = 'ioh',
      String filterType = 'all',
      String filterValue = '',
      int? monthId}) async {
    final q = <String, String>{
      'circle': circle,
      'scope': scope,
      'brand': brand,
      'filter_type': filterType,
      if (filterValue.isNotEmpty) 'filter_value': filterValue,
      if (monthId != null) 'month_id': '$monthId'
    };
    final uri = Uri.parse('$base/api/reports/product-demand')
        .replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat laporan');
    }
    return data;
  }

  static Future<Map<String, dynamic>> reportNetworkBenchmark(
      {String circle = 'JAVA',
      String filterType = 'all',
      String filterValue = ''}) async {
    final q = <String, String>{
      'circle': circle,
      'filter_type': filterType,
      if (filterValue.isNotEmpty) 'filter_value': filterValue
    };
    final uri = Uri.parse('$base/api/reports/network-benchmark')
        .replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat benchmark');
    }
    return data;
  }

  static Future<Map<String, dynamic>> reportFwa({
    String circle = 'JAVA',
    String brand = 'ioh',
    String filterType = 'all',
    String filterValue = '',
    int? monthId,
  }) async {
    final q = <String, String>{
      'circle': circle,
      'brand': brand,
      'filter_type': filterType,
      if (filterValue.isNotEmpty) 'filter_value': filterValue,
      if (monthId != null) 'month_id': '$monthId',
    };
    final uri = Uri.parse('$base/api/reports/fwa').replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat laporan FWA');
    }
    return data;
  }

  static Future<Map<String, dynamic>> reportInternalPerformance({
    String circle = 'JAVA',
    String brand = 'ioh',
    String filterType = 'all',
    String filterValue = '',
  }) async {
    final q = <String, String>{
      'circle': circle,
      'brand': brand,
      'filter_type': filterType,
      if (filterValue.isNotEmpty) 'filter_value': filterValue,
    };
    final uri = Uri.parse('$base/api/reports/internal-performance')
        .replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat Internal Performance');
    }
    return data;
  }

  static Future<Map<String, dynamic>> reportMarketInsight(
      {String circle = 'JAVA',
      String filterType = 'all',
      String filterValue = ''}) async {
    final q = <String, String>{
      'circle': circle,
      'filter_type': filterType,
      if (filterValue.isNotEmpty) 'filter_value': filterValue
    };
    final uri = Uri.parse('$base/api/reports/market-insight')
        .replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat Market Insight');
    }
    return data;
  }

  static Future<Map<String, dynamic>> reportFtth(
      {String circle = 'JAVA',
      String filterType = 'all',
      String filterValue = ''}) async {
    final q = <String, String>{
      'circle': circle,
      'filter_type': filterType,
      if (filterValue.isNotEmpty) 'filter_value': filterValue
    };
    final uri = Uri.parse('$base/api/reports/ftth').replace(queryParameters: q);
    final res = await _authGet(uri);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && data['error'] == null) {
      throw Exception(data['detail'] ?? 'Gagal memuat laporan FTTH');
    }
    return data;
  }

  // ── Chat history ──
  // ── Redesign v1 screens ──

  static Future<Map<String, dynamic>> _getJson(String path, [Map<String, String>? q]) async {
    final res = await _authGet(Uri.parse('$base$path').replace(queryParameters: q));
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200) {
      throw Exception(body is Map && body['detail'] != null ? body['detail'].toString() : 'HTTP ${res.statusCode}');
    }
    if (body is Map<String, dynamic> && body['error'] != null) throw Exception(body['error'].toString());
    return body as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _sendJson(String method, String path, [Object? body]) async {
    Future<http.Response> go() {
      final uri = Uri.parse('$base$path');
      final b = body == null ? null : jsonEncode(body);
      return switch (method) {
        'POST' => http.post(uri, headers: _headers(), body: b),
        'PATCH' => http.patch(uri, headers: _headers(), body: b),
        'PUT' => http.put(uri, headers: _headers(), body: b),
        _ => http.delete(uri, headers: _headers()),
      };
    }

    var res = await go();
    if (res.statusCode == 401 && await refreshAccessToken()) res = await go();
    final data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 300) {
      throw Exception(data is Map && data['detail'] != null ? data['detail'].toString() : 'HTTP ${res.statusCode}');
    }
    return data is Map<String, dynamic> ? data : {'data': data};
  }

  /// Dashboard Monitoring numbers (KPIs, sparklines, revenue per region, agent summary).
  static Future<Map<String, dynamic>> dashboardOverview({String region = ''}) =>
      _getJson('/api/dashboard/overview', {if (region.isNotEmpty) 'region': region});

  static Future<List<dynamic>> watchAlerts({String status = 'all'}) async =>
      (await _getJson('/api/watchlist/alerts', {'status': status}))['alerts'] as List? ?? [];

  static Future<List<dynamic>> watchRules() async =>
      (await _getJson('/api/watchlist/rules'))['rules'] as List? ?? [];

  static Future<Map<String, dynamic>> watchMeta() => _getJson('/api/watchlist/meta');

  static Future<int> alertCount() async {
    try {
      return ((await _getJson('/api/watchlist/alerts/count'))['active'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> ackAlert(int id) => _sendJson('POST', '/api/watchlist/alerts/$id/ack');

  static Future<Map<String, dynamic>> createWatchRule(Map<String, dynamic> body) => _sendJson('POST', '/api/watchlist/rules', body);

  static Future<Map<String, dynamic>> updateWatchRule(int id, Map<String, dynamic> patch) =>
      _sendJson('PATCH', '/api/watchlist/rules/$id', patch);

  static Future<void> deleteWatchRule(int id) => _sendJson('DELETE', '/api/watchlist/rules/$id');

  static Future<Map<String, dynamic>> mapKabupaten({String metric = 'revenue', String region = ''}) =>
      _getJson('/api/map/kabupaten', {'metric': metric, if (region.isNotEmpty) 'region': region});

  static Future<Map<String, dynamic>> mapKabupatenDetail(String kabupaten, String provinsi) =>
      _getJson('/api/map/kabupaten/detail', {'kabupaten': kabupaten, 'provinsi': provinsi});

  static Future<List<dynamic>> reportSchedules() async {
    final res = await _authGet(Uri.parse('$base/api/report-schedules'));
    if (res.statusCode != 200) return [];
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return body is List ? body : (body['schedules'] as List? ?? []);
  }

  static Future<Map<String, dynamic>> appStats({int days = 30}) => _getJson('/api/admin/app-stats', {'days': '$days'});

  static Future<int> remindUsers(List<int> ids) async =>
      ((await _sendJson('POST', '/api/admin/app-stats/remind', {'user_ids': ids}))['sent'] as num?)?.toInt() ?? 0;

  static Future<List<dynamic>> appReleases() async {
    final res = await http.get(Uri.parse('$base/api/app/releases'), headers: ClientInfo.headers);
    if (res.statusCode != 200) return [];
    return (jsonDecode(utf8.decode(res.bodyBytes))['releases'] as List?) ?? [];
  }

  /// Logged so admin Statistik can show exports in a user's timeline.
  static Future<List<dynamic>> reportRuns() async => (await _getJson('/api/report-schedules/runs'))['runs'] as List? ?? [];

  static Future<Map<String, dynamic>> createSchedule(Map<String, dynamic> body) => _sendJson('POST', '/api/report-schedules', body);

  static Future<Map<String, dynamic>> updateSchedule(int id, Map<String, dynamic> patch) =>
      _sendJson('PATCH', '/api/report-schedules/$id', patch);

  static Future<void> deleteSchedule(int id) => _sendJson('DELETE', '/api/report-schedules/$id');

  static Future<Map<String, dynamic>> sendScheduleNow(int id) => _sendJson('POST', '/api/report-schedules/$id/send-now');

  /// A read-only link to the live report that anyone can open for 7 days.
  /// With [columns] and [rows] the link shows that table as it is now (an ad-hoc answer).
  static Future<String> createReportLink(String title, {String region = '', List<String>? columns, List<Map<String, dynamic>>? rows}) async {
    final r = await _sendJson('POST', '/api/report-links', {
      'title': title,
      'region': region,
      if (columns != null) 'columns': columns,
      if (columns != null) 'rows': (rows ?? const []).take(2000).toList(),
    });
    return '$base${r['path']}';
  }

  static Future<void> logExport(String format, String title, {String? domain}) async {
    try {
      await _sendJson('POST', '/api/usage/export', {'format': format, 'title': title, if (domain != null) 'domain': domain});
    } catch (_) {}
  }

  static Future<List<dynamic>> historySessions() async {
    final res = await _authGet(Uri.parse('$base/api/history/sessions'));
    if (res.statusCode != 200) return [];
    final d = jsonDecode(res.body);
    return d is List ? d : (d['sessions'] as List? ?? []);
  }

  static Future<List<dynamic>> sessionMessages(String sid) async {
    final res = await _authGet(Uri.parse('$base/api/history/sessions/$sid'));
    if (res.statusCode != 200) return [];
    final d = jsonDecode(res.body);
    return d is List ? d : (d['messages'] as List? ?? []);
  }

  // ── Geo locate ──
  static Future<Map<String, dynamic>> geoLocate(double lat, double lon) async {
    final res = await http.post(Uri.parse('$base/api/geo/locate'),
        headers: _headers(), body: jsonEncode({'lat': lat, 'lon': lon}));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Site Performance ──
  static Future<List<Map<String, dynamic>>> siteSearch(String q) async {
    final res = await _authGet(
        Uri.parse('$base/api/site/search').replace(queryParameters: {'q': q}));
    if (res.statusCode != 200) return [];
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    return ((d['sites'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> siteNearest(
      double lat, double lon) async {
    final res = await http
        .post(Uri.parse('$base/api/site/nearest'),
            headers: _headers(), body: jsonEncode({'lat': lat, 'lon': lon}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) return [];
    final d = jsonDecode(res.body) as Map<String, dynamic>;
    return ((d['sites'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> siteDetail(String siteId,
      {String brand = 'ioh'}) async {
    final res = await _authGet(Uri.parse('$base/api/site/detail')
            .replace(queryParameters: {'site_id': siteId, 'brand': brand}))
        .timeout(const Duration(seconds: 90));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // Fix mode: nearest ~100 sites with attributes + perf + monthly history.
  static Future<Map<String, dynamic>> nearestSites(
      double lat, double lon) async {
    final res = await http
        .post(Uri.parse('$base/api/geo/nearest-sites'),
            headers: _headers(), body: jsonEncode({'lat': lat, 'lon': lon}))
        .timeout(const Duration(seconds: 60));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Profile / account ──
  static Future<Map<String, dynamic>> getMe() async {
    final res = await _authGet(Uri.parse('$base/api/auth/me'));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Gagal memuat profil');
    }
    AuthState.mergeUser(data);
    return data;
  }

  static Future<Map<String, dynamic>> updateProfile(
      {String? fullName, String? email, String? department}) async {
    final res = await http.put(Uri.parse('$base/api/auth/me/profile'),
        headers: _headers(),
        body: jsonEncode({
          if (fullName != null) 'full_name': fullName,
          if (email != null) 'email': email,
          if (department != null) 'department': department,
        }));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Gagal menyimpan profil');
    }
    AuthState.mergeUser(data);
    return data;
  }

  static Future<String> changePassword(
      String oldPassword, String newPassword) async {
    final res = await http.put(Uri.parse('$base/api/auth/me/password'),
        headers: _headers(),
        body: jsonEncode(
            {'old_password': oldPassword, 'new_password': newPassword}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Gagal mengubah password');
    }
    return (data['message'] ?? 'Password berhasil diubah.').toString();
  }

  static Future<List<dynamic>> notifications() async {
    final res = await http.get(Uri.parse('$base/api/auth/me/notifications'),
        headers: _headers());
    if (res.statusCode != 200) return [];
    final d = jsonDecode(res.body);
    if (d is List) return d;
    return (d['notifications'] as List?) ?? [];
  }

  static Future<void> markAllNotificationsRead() async {
    await http.put(Uri.parse('$base/api/auth/me/notifications/read-all'),
        headers: _headers());
  }

  // ── Summary email ──
  static Future<Map<String, dynamic>> summarizeChat(
      List<Map<String, dynamic>> messages, String lang) async {
    final res = await http.post(Uri.parse('$base/api/auth/me/summarize-chat'),
        headers: _headers(),
        body: jsonEncode({'messages': messages, 'language': lang}));
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw Exception(data['detail'] ?? 'Gagal');
    return data;
  }

  /// Stream the chat SSE. Yields (event, data) pairs.
  static Stream<MapEntry<String, Map<String, dynamic>>> chatStream(
      String message, String sessionId, String language,
      {List<Map<String, dynamic>>? history, bool mapContext = false}) async* {
    final body = jsonEncode({
      'message': message,
      'session_id': sessionId,
      'language': language,
      'history': history ?? [],
      if (mapContext) 'map_context': true,
    });
    final client = http.Client();
    try {
      http.Request buildReq() {
        final r = http.Request('POST', Uri.parse('$base/api/chat/stream'));
        r.headers.addAll(_headers());
        r.body = body;
        return r;
      }

      var resp = await client.send(buildReq());
      // If the access token expired (401), refresh once and retry so the chat
      // is attributed to the logged-in user (and thus saved to their history).
      if (resp.statusCode == 401 && await refreshAccessToken()) {
        resp = await client.send(buildReq());
      }
      var buffer = '';
      String event = 'message';
      await for (final chunk in resp.stream.transform(utf8.decoder)) {
        buffer += chunk;
        int sep;
        while ((sep = buffer.indexOf('\n\n')) != -1) {
          final raw = buffer.substring(0, sep);
          buffer = buffer.substring(sep + 2);
          event = 'message';
          var dataStr = '';
          for (final line in raw.split('\n')) {
            if (line.startsWith('event:')) {
              event = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              dataStr += line.substring(5).trim();
            }
          }
          if (dataStr.isEmpty) continue;
          try {
            final obj = jsonDecode(dataStr) as Map<String, dynamic>;
            yield MapEntry(event, obj);
          } catch (_) {}
        }
      }
    } finally {
      client.close();
    }
  }
}
