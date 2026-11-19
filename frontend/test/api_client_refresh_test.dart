// Chặng 2 — Refresh token single-flight: nhiều request 401 đồng thời chỉ gọi refresh MỘT lần.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/core/constants/api_constants.dart';
import 'package:nhatro_frontend/shared/services/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

/// Trả về lỗi mà [future] ném ra (null nếu thành công).
Future<Object?> _errorOf(Future<dynamic> future) async {
  try {
    await future;
    return null;
  } catch (e) {
    return e;
  }
}

/// Gateway giả mô phỏng SimpleJWT: ROTATE_REFRESH_TOKENS + BLACKLIST_AFTER_ROTATION.
/// - Access token hợp lệ duy nhất: [validAccess]. Token khác -> 401.
/// - Refresh token đã dùng sẽ bị blacklist -> lần dùng lại trả 401 (giống backend thật).
class _FakeIdentityGateway {
  String validAccess = 'access-1';
  String validRefresh = 'refresh-1';
  final Set<String> blacklisted = {};
  int refreshRequests = 0;
  int protectedRequests = 0;
  final List<String> authHeadersSeen = [];

  /// Khi khác null, refresh chờ completer này (để dồn nhiều request vào cùng lúc).
  Completer<void>? holdRefresh;

  /// Ép kết quả refresh (vd. 401 hết hạn, 503, lỗi mạng).
  http.Response Function()? refreshOverride;
  bool refreshThrows = false;

  /// true: endpoint bảo vệ luôn trả 401 kể cả với token mới (tài khoản bị khóa).
  bool alwaysUnauthorized = false;

  MockClient get client => MockClient((req) async {
        if (req.url.path == '/api/auth/refresh/') {
          refreshRequests++;
          if (holdRefresh != null) await holdRefresh!.future;
          if (refreshThrows) throw http.ClientException('Connection refused');
          if (refreshOverride != null) return refreshOverride!();
          final sent = (jsonDecode(req.body) as Map)['refresh'] as String;
          if (blacklisted.contains(sent) || sent != validRefresh) {
            return _json({'detail': 'Token is blacklisted', 'code': 'token_not_valid'}, 401);
          }
          blacklisted.add(sent);
          final n = refreshRequests + 1;
          validAccess = 'access-$n';
          validRefresh = 'refresh-$n';
          return _json({'access': validAccess, 'refresh': validRefresh});
        }
        protectedRequests++;
        final auth = req.headers['Authorization'] ?? '';
        authHeadersSeen.add(auth);
        if (alwaysUnauthorized || auth != 'Bearer $validAccess') {
          return _json({'detail': 'Given token not valid for any token type'}, 401);
        }
        return _json([
          {'path': req.url.path}
        ]);
      });
}

void main() {
  late _FakeIdentityGateway gw;
  late int expiredCallbacks;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient.resetForTest();
    gw = _FakeIdentityGateway();
    ApiClient.httpClient = gw.client;
    expiredCallbacks = 0;
    ApiClient.onSessionExpired = () => expiredCallbacks++;
    // Access token đã hết hạn, refresh token còn hợp lệ.
    await ApiClient.saveSession(access: 'expired-access', refresh: 'refresh-1');
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ApiClient.onSessionExpired = null;
    ApiClient.resetForTest();
  });

  test('Nhiều request 401 đồng thời: refresh chỉ 1 lần, tất cả retry thành công', () async {
    gw.holdRefresh = Completer<void>();
    final futures = [
      ApiClient.get(ApiConstants.properties),
      ApiClient.get(ApiConstants.rooms),
      ApiClient.get(ApiConstants.maintenance),
      ApiClient.get(ApiConstants.dashboardSummary),
      ApiClient.get(ApiConstants.currentUser),
    ];
    // Chờ cho cả 5 request nhận 401 và cùng chờ lần refresh đang treo.
    await pumpEventQueue();
    expect(gw.refreshRequests, 1, reason: 'các request sau phải chờ refresh đang chạy');
    gw.holdRefresh!.complete();

    final results = await Future.wait(futures);
    expect(results, everyElement(isA<List>()));
    expect(gw.refreshRequests, 1);
    expect(ApiClient.refreshCallCount, 1);
    expect(expiredCallbacks, 0, reason: 'không được đăng xuất ngoài ý muốn');
    expect(await ApiClient.getAccessToken(), gw.validAccess);
    // Lần gửi lại đều dùng access token mới.
    expect(gw.authHeadersSeen.where((h) => h == 'Bearer ${gw.validAccess}').length, 5);
  });

  test('Refresh thành công: lưu access + refresh token mới (xoay vòng), request được gửi lại', () async {
    final res = await ApiClient.get(ApiConstants.properties);

    expect(res, isA<List>());
    expect(gw.refreshRequests, 1);
    expect(await ApiClient.getAccessToken(), gw.validAccess);
    expect(await ApiClient.getRefreshToken(), gw.validRefresh);
    expect(gw.blacklisted, contains('refresh-1'));
    expect(gw.authHeadersSeen, ['Bearer expired-access', 'Bearer ${gw.validAccess}']);
  });

  test('Hai đợt 401 liên tiếp: đợt sau dùng refresh token mới, không bị blacklist', () async {
    await ApiClient.get(ApiConstants.properties);
    // Access token mới lại hết hạn.
    gw.validAccess = 'access-expired-again';
    final res = await ApiClient.get(ApiConstants.rooms);
    expect(res, isA<List>());
    expect(gw.refreshRequests, 2);
    expect(expiredCallbacks, 0);
  });

  test('Request đã gửi bằng token cũ nhưng nhận 401 SAU khi refresh xong: chỉ gửi lại, không refresh thêm',
      () async {
    // Request A làm mới token xong.
    await ApiClient.get(ApiConstants.properties);
    final refreshesAfterA = gw.refreshRequests;
    // Mô phỏng request B đã lấy token cũ trước khi A refresh: gửi thẳng với token cũ qua client.
    // Ở đây kiểm tra nhánh "token hiện tại khác token đã gửi": đặt lại access cũ cho lần gửi đầu.
    final newAccess = await ApiClient.getAccessToken();
    var first = true;
    ApiClient.httpClient = MockClient((req) async {
      if (req.url.path == '/api/auth/refresh/') {
        gw.refreshRequests++;
        return _json({'detail': 'should not be called'}, 500);
      }
      if (first) {
        first = false;
        // Lần gửi đầu "đã dùng" token cũ -> 401; trong lúc đó token đã được làm mới.
        await ApiClient.saveSession(access: newAccess!);
        return _json({'detail': 'expired'}, 401);
      }
      expect(req.headers['Authorization'], 'Bearer $newAccess');
      return _json([]);
    });
    await ApiClient.saveSession(access: 'stale-access');

    final res = await ApiClient.get(ApiConstants.rooms);
    expect(res, isA<List>());
    expect(gw.refreshRequests, refreshesAfterA, reason: 'không gọi refresh lần nữa');
    expect(expiredCallbacks, 0);
  });

  test('Refresh token hết hạn / bị blacklist (401): xóa phiên, báo hết hạn đúng 1 lần', () async {
    gw.refreshOverride = () => _json({'detail': 'Token is invalid or expired', 'code': 'token_not_valid'}, 401);
    gw.holdRefresh = Completer<void>();
    final futures = [
      _errorOf(ApiClient.get(ApiConstants.properties)),
      _errorOf(ApiClient.get(ApiConstants.rooms)),
      _errorOf(ApiClient.get(ApiConstants.maintenance)),
    ];
    await pumpEventQueue();
    gw.holdRefresh!.complete();
    final errors = await Future.wait(futures);

    expect(gw.refreshRequests, 1);
    expect(errors, everyElement(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)));
    expect(expiredCallbacks, 1, reason: 'chỉ chuyển về màn đăng nhập một lần');
    expect(await ApiClient.getAccessToken(), isNull);
    expect(await ApiClient.getRefreshToken(), isNull);
  });

  test('Không có refresh token: không gọi refresh, kết thúc phiên', () async {
    SharedPreferences.setMockInitialValues({});
    await ApiClient.saveSession(access: 'expired-access');

    await expectLater(ApiClient.get(ApiConstants.properties), throwsA(isA<ApiException>()));
    expect(gw.refreshRequests, 0);
    expect(expiredCallbacks, 1);
  });

  test('Lỗi mạng khi refresh: GIỮ phiên, báo lỗi để thử lại (không đăng xuất)', () async {
    gw.refreshThrows = true;

    final error = await _errorOf(ApiClient.get(ApiConstants.properties));

    expect(error, isA<ApiException>());
    expect((error as ApiException).isUnauthorized, isFalse,
        reason: 'không được gắn 401, nếu không restoreSession sẽ xóa phiên');
    expect(error.message, contains('mất kết nối'));
    expect(expiredCallbacks, 0);
    expect(await ApiClient.getRefreshToken(), 'refresh-1');
  });

  test('Identity Service lỗi 503 khi refresh: giữ phiên, không đăng xuất', () async {
    gw.refreshOverride = () => _json({'error': 'Identity Service hiện không hoạt động.'}, 503);

    await expectLater(ApiClient.get(ApiConstants.properties), throwsA(isA<ApiException>()));
    expect(expiredCallbacks, 0);
    expect(await ApiClient.getRefreshToken(), 'refresh-1');
  });

  test('Không lặp vô hạn: token mới vẫn bị 401 -> chỉ 1 refresh, 2 lần gửi, rồi kết thúc phiên', () async {
    gw.alwaysUnauthorized = true;

    await expectLater(ApiClient.get(ApiConstants.properties), throwsA(isA<ApiException>()));
    expect(gw.refreshRequests, 1);
    expect(gw.protectedRequests, 2);
    expect(expiredCallbacks, 1);
  });

  test('Request không cho phép retry (login/logout) không kích hoạt refresh', () async {
    await expectLater(
      ApiClient.post(ApiConstants.logout, {'refresh': 'x'}, retryOnUnauthorized: false),
      throwsA(isA<ApiException>()),
    );
    expect(gw.refreshRequests, 0);
    expect(expiredCallbacks, 0);
  });

  test('Đăng nhập lại sau khi phiên hết hạn: lần hết hạn kế tiếp vẫn được báo', () async {
    gw.refreshOverride = () => _json({'detail': 'expired'}, 401);
    await expectLater(ApiClient.get(ApiConstants.properties), throwsA(isA<ApiException>()));
    expect(expiredCallbacks, 1);

    await ApiClient.saveSession(access: 'expired-again', refresh: 'refresh-x');
    await expectLater(ApiClient.get(ApiConstants.properties), throwsA(isA<ApiException>()));
    expect(expiredCallbacks, 2);
  });
}
