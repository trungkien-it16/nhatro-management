import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/api_constants.dart';

/// Lỗi gọi API qua Gateway (HTTP != 2xx, timeout, mất kết nối...).
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic body;

  ApiException(this.message, {this.statusCode, this.body});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Kết quả một lần làm mới access token.
enum _RefreshResult {
  /// Đã có access token mới (và refresh token mới nếu backend xoay vòng).
  refreshed,

  /// Refresh token không còn hợp lệ (hết hạn / bị blacklist / không có) -> phải đăng nhập lại.
  rejected,

  /// Không liên lạc được Identity Service (mất mạng, timeout, 5xx) -> giữ phiên, báo lỗi.
  unavailable,
}

/// HTTP client duy nhất của Frontend.
/// - Mọi request đi qua API Gateway ([ApiConstants.baseUrl]); không gọi trực tiếp port 8001–8005.
/// - Lưu cặp JWT (access + refresh) và tự làm mới access token khi nhận 401.
/// - Không có tài khoản/mật khẩu hardcode: người dùng phải đăng nhập.
class ApiClient {
  ApiClient._();

  static const _accessKey = 'soa_jwt_access_token';
  static const _refreshKey = 'soa_jwt_refresh_token';
  static const _userKey = 'soa_current_user';
  static const Duration timeout = Duration(seconds: 15);

  /// Cho phép test thay thế HTTP client.
  static http.Client httpClient = http.Client();

  /// Được gọi khi phiên đăng nhập hết hạn (refresh thất bại) để UI chuyển về màn đăng nhập.
  static void Function()? onSessionExpired;

  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ------------------------------------------------------------------ TOKEN STORAGE
  static Future<String?> getAccessToken() async => (await _prefs).getString(_accessKey);

  static Future<String?> getRefreshToken() async => (await _prefs).getString(_refreshKey);

  static Future<void> saveSession({
    required String access,
    String? refresh,
    Map<String, dynamic>? user,
  }) async {
    _sessionExpired = false;
    final prefs = await _prefs;
    await prefs.setString(_accessKey, access);
    if (refresh != null) await prefs.setString(_refreshKey, refresh);
    if (user != null) await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<Map<String, dynamic>?> getSavedUser() async {
    final raw = (await _prefs).getString(_userKey);
    if (raw == null) return null;
    try {
      final data = jsonDecode(raw);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearSession() async {
    final prefs = await _prefs;
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
    await prefs.remove(_userKey);
  }

  // ------------------------------------------------------------------ AUTH
  /// POST /api/auth/login/ -> lưu access/refresh + thông tin user, trả về user.
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final data = await post(
      ApiConstants.login,
      {'username': username, 'password': password},
      requireAuth: false,
      retryOnUnauthorized: false,
    );
    if (data is! Map<String, dynamic> || data['access'] is! String) {
      throw ApiException('Phản hồi đăng nhập không hợp lệ từ API Gateway.');
    }
    final user = data['user'] is Map<String, dynamic> ? data['user'] as Map<String, dynamic> : <String, dynamic>{};
    await saveSession(access: data['access'] as String, refresh: data['refresh'] as String?, user: user);
    return user;
  }

  /// Thu hồi refresh token ở Identity Service (qua Gateway). Lỗi mạng không chặn đăng xuất cục bộ.
  static Future<void> logout() async {
    try {
      final refresh = await getRefreshToken();
      if (refresh != null && refresh.isNotEmpty) {
        await post(ApiConstants.logout, {'refresh': refresh}, retryOnUnauthorized: false);
      }
    } catch (_) {
      // bỏ qua: vẫn xóa phiên cục bộ
    }
    await clearSession();
  }

  /// Lần refresh đang chạy (single-flight). Mọi request nhận 401 trong lúc này dùng chung kết quả,
  /// vì backend xoay vòng + blacklist refresh token: gửi cùng một refresh token 2 lần sẽ bị từ chối.
  static Future<_RefreshResult>? _refreshInFlight;

  /// Số lần gọi POST /auth/refresh/ (phục vụ kiểm thử).
  @visibleForTesting
  static int refreshCallCount = 0;

  /// Đặt lại trạng thái tĩnh giữa các test.
  @visibleForTesting
  static void resetForTest() {
    _refreshInFlight = null;
    _sessionExpired = false;
    refreshCallCount = 0;
  }

  static Future<_RefreshResult> _refreshAccessToken() {
    return _refreshInFlight ??= _performRefresh().whenComplete(() => _refreshInFlight = null);
  }

  static Future<_RefreshResult> _performRefresh() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return _RefreshResult.rejected;
    refreshCallCount++;
    final http.Response res;
    try {
      res = await httpClient
          .post(
            Uri.parse(ApiConstants.refreshToken),
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({'refresh': refresh}),
          )
          .timeout(timeout);
    } catch (_) {
      // Mất mạng / timeout: chưa biết refresh token còn hợp lệ hay không -> KHÔNG đăng xuất.
      return _RefreshResult.unavailable;
    }
    // 400/401: refresh token hết hạn, sai hoặc đã bị blacklist -> phiên thực sự kết thúc.
    if (res.statusCode == 400 || res.statusCode == 401) return _RefreshResult.rejected;
    if (res.statusCode != 200) return _RefreshResult.unavailable;
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map<String, dynamic> || data['access'] is! String) return _RefreshResult.unavailable;
      await saveSession(access: data['access'] as String, refresh: data['refresh'] as String?);
      return _RefreshResult.refreshed;
    } on FormatException {
      return _RefreshResult.unavailable;
    }
  }

  /// true khi phiên hiện tại đã bị kết thúc; đặt lại khi lưu phiên mới (đăng nhập / refresh).
  static bool _sessionExpired = false;

  /// Kết thúc phiên đúng một lần dù nhiều request cùng thất bại. Cờ được đặt trước mọi `await`
  /// nên các request chạy song song không gọi [onSessionExpired] lặp lại.
  static Future<void> _expireSession() async {
    if (_sessionExpired) return;
    _sessionExpired = true;
    await clearSession();
    onSessionExpired?.call();
  }

  // ------------------------------------------------------------------ HTTP VERBS
  static Future<dynamic> get(String url, {bool requireAuth = true}) =>
      _send('GET', url, requireAuth: requireAuth);

  static Future<dynamic> post(
    String url,
    Object? body, {
    bool requireAuth = true,
    bool retryOnUnauthorized = true,
  }) =>
      _send('POST', url, body: body, requireAuth: requireAuth, retryOnUnauthorized: retryOnUnauthorized);

  static Future<dynamic> patch(String url, Object? body) => _send('PATCH', url, body: body);

  static Future<dynamic> delete(String url) => _send('DELETE', url);

  static Future<dynamic> _send(
    String method,
    String url, {
    Object? body,
    bool requireAuth = true,
    bool retryOnUnauthorized = true,
  }) async {
    String? sentToken;
    Future<http.Response> doRequest() async {
      final headers = <String, String>{'Accept': 'application/json'};
      if (body != null) headers['Content-Type'] = 'application/json';
      sentToken = null;
      if (requireAuth) {
        final token = await getAccessToken();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
          sentToken = token;
        }
      }
      final request = http.Request(method, Uri.parse(url))..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await httpClient.send(request).timeout(timeout);
      return http.Response.fromStream(streamed);
    }

    http.Response res;
    try {
      res = await doRequest();
      // Tối đa MỘT lần làm mới + MỘT lần gửi lại cho mỗi request (không lặp vô hạn).
      if (res.statusCode == 401 && requireAuth && retryOnUnauthorized) {
        final current = await getAccessToken();
        final _RefreshResult outcome;
        if (current != null && current.isNotEmpty && current != sentToken) {
          // Request khác đã làm mới token trong lúc request này đang chạy: chỉ cần gửi lại.
          outcome = _RefreshResult.refreshed;
        } else {
          outcome = await _refreshAccessToken();
        }
        switch (outcome) {
          case _RefreshResult.refreshed:
            res = await doRequest();
            // Token mới vẫn bị từ chối (vd. tài khoản bị khóa) -> kết thúc phiên.
            if (res.statusCode == 401) await _expireSession();
          case _RefreshResult.rejected:
            await _expireSession();
          case _RefreshResult.unavailable:
            // Không đăng xuất khi chỉ là lỗi mạng tạm thời; báo lỗi để người dùng thử lại.
            // Cố ý không gắn statusCode 401 để nơi gọi (vd. restoreSession) không xóa phiên.
            throw ApiException(
              'Không làm mới được phiên đăng nhập do mất kết nối tới API Gateway. Vui lòng thử lại.',
            );
        }
      }
    } on TimeoutException {
      throw ApiException('API Gateway không phản hồi kịp (timeout).');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Không kết nối được tới API Gateway (${ApiConstants.gatewayUrl}).');
    }

    dynamic decoded;
    if (res.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        decoded = null;
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    throw ApiException(_errorMessage(res.statusCode, decoded), statusCode: res.statusCode, body: decoded);
  }

  /// Rút gọn thông báo lỗi DRF/Gateway: {"detail": ...}, {"error": ...}, {"field": ["msg"]}.
  static String _errorMessage(int status, dynamic body) {
    if (body is Map) {
      for (final key in ['error', 'detail', 'message']) {
        final v = body[key];
        if (v is String && v.isNotEmpty) return v;
      }
      for (final entry in body.entries) {
        final v = entry.value;
        if (v is List && v.isNotEmpty) return '${entry.key}: ${v.first}';
        if (v is String) return '${entry.key}: $v';
      }
    }
    return switch (status) {
      401 => 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.',
      403 => 'Bạn không có quyền thực hiện thao tác này.',
      404 => 'Không tìm thấy dữ liệu.',
      503 || 504 => 'Service phụ trách đang không hoạt động.',
      _ => 'Lỗi máy chủ (HTTP $status).',
    };
  }
}
