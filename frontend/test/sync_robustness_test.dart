// Chặng 5 – Bước 2 (E5.1): độ bền của AppDataRepository.syncWithBackend.
// Trạng thái từng nhóm dữ liệu, giữ dữ liệu khi lỗi, 403 = Forbidden, phiên đăng nhập (generation),
// gộp các yêu cầu đồng bộ liên tiếp, request ghi đang chờ khi đổi tài khoản.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/shared/models/app_models.dart';
import 'package:nhatro_frontend/shared/services/api_client.dart';
import 'package:nhatro_frontend/shared/services/app_data_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

typedef _Handler = FutureOr<http.Response> Function(http.Request req);

/// Gateway giả. Dữ liệu trả về phụ thuộc access token (tài khoản A / B) để phát hiện rò rỉ
/// dữ liệu giữa các tài khoản. Có thể "treo" response của một (token, path) bằng Completer.
class _FakeGateway {
  final Map<String, _Handler> overrides = {};
  final Map<String, Completer<void>> holds = {};
  final List<String> calls = [];
  bool gatewayDown = false;

  /// Số nhà trọ mỗi tài khoản đang có trên "backend" (thay đổi được để mô phỏng thao tác ghi).
  final Map<String, int> propertyCount = {'A': 1, 'B': 1};

  static String _account(http.Request req) =>
      (req.headers['Authorization'] ?? '').replaceFirst('Bearer access-', '');

  Map<String, dynamic> get _health => {
        'gateway': {'status': 'UP', 'port': 8000},
        'overall_status': 'UP',
        'services': [
          for (final k in ['identity', 'property', 'tenant', 'contract', 'billing'])
            {'key': k, 'name': k, 'port': 8000, 'status': 'UP'},
        ],
      };

  http.Response _default(http.Request req) {
    final acc = _account(req);
    if (req.method == 'POST' && req.url.path == '/api/properties/') {
      propertyCount[acc] = (propertyCount[acc] ?? 0) + 1;
      return _json({'id': 99}, 201);
    }
    switch (req.url.path) {
      case '/api/system/health/':
        return _json(_health);
      case '/api/dashboard/summary/':
        return _json({'total_properties': propertyCount[acc], 'total_rooms': 1, 'complete': true, 'errors': []});
      case '/api/properties/':
        return _json([
          for (var i = 1; i <= (propertyCount[acc] ?? 0); i++)
            {'id': i, 'code': 'NT-$acc$i', 'name': 'Nhà $acc$i', 'status': 'ACTIVE'},
        ]);
      case '/api/rooms/':
        return _json([
          {'id': 10, 'room_number': 'Phòng $acc', 'property': 1, 'status': 'AVAILABLE'},
        ]);
      case '/api/maintenance/':
        return _json([
          {'id': 70, 'title': 'Sửa điện $acc', 'room': 10, 'status': 'PENDING'},
        ]);
      case '/api/maintenance-history/':
        return _json([]);
      case '/api/tenants/':
        return _json([
          {'id': 20, 'full_name': 'Khách $acc', 'room_id': 10, 'status': 'ACTIVE'},
        ]);
      case '/api/contracts/':
        return _json([
          {'id': 30, 'contract_number': 'HD-$acc', 'room_id': 10, 'tenant_id': 20, 'status': 'ACTIVE'},
        ]);
      case '/api/billing/invoices/':
        return _json([
          {'id': 40, 'invoice_code': 'HDN-$acc', 'room_id': 10, 'tenant_id': 20, 'status': 'UNPAID'},
        ]);
      case '/api/notifications/':
        return _json([
          {'id': 50, 'title': 'Thông báo $acc', 'is_read': false},
        ]);
      case '/api/notifications/read-all/':
        return _json({'ok': true});
    }
    return _json({'detail': 'Not found'}, 404);
  }

  MockClient get client => MockClient((req) async {
        final acc = _account(req);
        calls.add('${req.method} ${req.url.path} [$acc]');
        final hold = holds['$acc ${req.method} ${req.url.path}'];
        if (hold != null) await hold.future;
        if (gatewayDown) throw http.ClientException('Connection refused');
        if (req.method == 'POST' && req.url.path == '/api/properties/') {
          final o = overrides['POST /api/properties/'];
          return o != null ? await o(req) : _default(req);
        }
        final o = overrides[req.url.path];
        return o != null ? await o(req) : _default(req);
      });

  /// Treo response của [path] cho tài khoản [acc] tới khi gọi complete().
  Completer<void> hold(String acc, String path, {String method = 'GET'}) =>
      holds['$acc $method $path'] = Completer<void>();
}

Future<void> _loginAs(String acc) => ApiClient.saveSession(access: 'access-$acc', refresh: 'refresh-$acc');

const _listSections = [
  DataSection.properties,
  DataSection.rooms,
  DataSection.maintenance,
  DataSection.maintenanceHistory,
  DataSection.tenants,
  DataSection.contracts,
  DataSection.invoices,
  DataSection.notifications,
];

void main() {
  late _FakeGateway gw;
  late AppDataRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient.resetForTest();
    gw = _FakeGateway();
    ApiClient.httpClient = gw.client;
    await _loginAs('A');
    repo = AppDataRepository();
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ApiClient.resetForTest();
  });

  /// Đăng xuất A (xóa phiên ở ApiClient + repository) rồi đăng nhập B.
  Future<void> switchToB() async {
    await ApiClient.clearSession();
    repo.resetAfterLogout();
    await _loginAs('B');
  }

  test('1. Tất cả service hoạt động: mọi nhóm Loaded với dữ liệu thật', () async {
    expect(repo.sectionState(DataSection.properties).status, LoadStatus.notLoaded);
    await repo.syncWithBackend();

    expect(repo.isBackendConnected, isTrue);
    expect(repo.lastSyncError, isNull);
    for (final s in DataSection.values) {
      expect(repo.sectionState(s).status, LoadStatus.loaded, reason: '$s');
    }
    expect(repo.properties.single.name, 'Nhà A1');
    expect(repo.rooms.single.name, 'Phòng A');
    expect(repo.tenants.single.fullName, 'Khách A');
    expect(repo.contracts.single.code, 'HD-A');
    expect(repo.invoices.single.code, 'HDN-A');
    expect(repo.notifications.single.title, 'Thông báo A');
    expect(repo.dashboardSummary?.totalProperties, 1);
    expect(repo.failedSections, isEmpty);
    expect(repo.isSyncing, isFalse);
  });

  test('2. Property trả 500 nhưng Notification và các nhóm khác vẫn tải thành công', () async {
    gw.overrides['/api/properties/'] = (_) => _json({'detail': 'Lỗi máy chủ'}, 500);
    await repo.syncWithBackend();

    final prop = repo.sectionState(DataSection.properties);
    expect(prop.status, LoadStatus.error);
    expect(prop.httpStatus, 500);
    expect(prop.hasData, isFalse, reason: 'chưa từng tải được -> không phải "danh sách rỗng thật"');
    expect(repo.sectionState(DataSection.notifications).status, LoadStatus.loaded);
    expect(repo.notifications.single.title, 'Thông báo A');
    expect(repo.sectionState(DataSection.rooms).status, LoadStatus.loaded);
    expect(repo.isBackendConnected, isTrue, reason: 'Gateway vẫn phản hồi');
    expect(repo.failedSections, [DataSection.properties]);
  });

  test('3. Tenant trả 500: giữ dữ liệu cũ, trạng thái Error, nhóm khác không ảnh hưởng', () async {
    await repo.syncWithBackend();
    expect(repo.tenants.single.fullName, 'Khách A');

    gw.overrides['/api/tenants/'] = (_) => _json({'detail': 'boom'}, 500);
    gw.propertyCount['A'] = 2;
    await repo.syncWithBackend();

    final t = repo.sectionState(DataSection.tenants);
    expect(t.status, LoadStatus.error);
    expect(t.hasData, isTrue);
    expect(t.message, isNotEmpty);
    expect(repo.tenants.single.fullName, 'Khách A', reason: 'không ghi đè bằng danh sách rỗng');
    expect(repo.properties, hasLength(2), reason: 'Property vẫn cập nhật bình thường');
    expect(repo.sectionState(DataSection.properties).status, LoadStatus.loaded);
  });

  test('4. Billing / Contract trả 403 (TENANT): Forbidden, không phải lỗi kết nối', () async {
    gw.overrides['/api/billing/invoices/'] =
        (_) => _json({'detail': 'Chỉ Quản trị viên, Nhân viên hoặc Chủ trọ được thực hiện thao tác này.'}, 403);
    gw.overrides['/api/contracts/'] = (_) => _json({'detail': 'Không có quyền.'}, 403);
    await repo.syncWithBackend();

    expect(repo.sectionState(DataSection.invoices).status, LoadStatus.forbidden);
    expect(repo.sectionState(DataSection.invoices).httpStatus, 403);
    expect(repo.sectionState(DataSection.contracts).status, LoadStatus.forbidden);
    expect(repo.invoices, isEmpty);
    expect(repo.contracts, isEmpty);
    expect(repo.failedSections, isEmpty, reason: 'Forbidden không tính là lỗi');
    expect(repo.isBackendConnected, isTrue);
    expect(repo.lastSyncError, isNull);
    expect(repo.sectionState(DataSection.notifications).status, LoadStatus.loaded);
  });

  test('5. Gateway UP nhưng Property Service DOWN (503 từ Gateway): chỉ nhóm của service đó lỗi', () async {
    for (final p in ['/api/properties/', '/api/rooms/', '/api/maintenance/', '/api/maintenance-history/']) {
      gw.overrides[p] = (_) => _json({'error': 'Property Service hiện không hoạt động (port 8002).'}, 503);
    }
    await repo.syncWithBackend();

    expect(repo.isBackendConnected, isTrue, reason: 'isBackendConnected chỉ phản ánh Gateway');
    for (final s in [
      DataSection.properties,
      DataSection.rooms,
      DataSection.maintenance,
      DataSection.maintenanceHistory
    ]) {
      expect(repo.sectionState(s).status, LoadStatus.error, reason: '$s');
      expect(repo.sectionState(s).httpStatus, 503);
      expect(repo.sectionState(s).message, contains('Property Service'));
    }
    for (final s in [DataSection.tenants, DataSection.contracts, DataSection.invoices, DataSection.notifications]) {
      expect(repo.sectionState(s).status, LoadStatus.loaded, reason: '$s');
    }
    // Thao tác ghi không bị chặn chỉ vì một service DOWN (backend sẽ tự báo lỗi nếu cần).
    expect(await repo.markAllNotificationsRead(), isNull);
  });

  test('6. Đăng xuất trong lúc sync đang chạy: không còn dữ liệu, không còn trạng thái đang tải', () async {
    final held = gw.hold('A', '/api/tenants/');
    final sync = repo.syncWithBackend();
    await pumpEventQueue();
    expect(repo.isSyncing, isTrue);

    await ApiClient.clearSession();
    repo.resetAfterLogout();
    held.complete();
    await sync;

    expect(repo.isSyncing, isFalse);
    expect(repo.isBackendConnected, isFalse);
    expect(repo.hasSyncedOnce, isFalse);
    expect(repo.properties, isEmpty);
    expect(repo.tenants, isEmpty);
    expect(repo.notifications, isEmpty);
    expect(repo.dashboardSummary, isNull);
    for (final s in DataSection.values) {
      expect(repo.sectionState(s).status, LoadStatus.notLoaded, reason: '$s');
    }
  });

  test('7. Đăng nhập B khi request của A chưa xong: B được đồng bộ ngay, chỉ thấy dữ liệu B', () async {
    final heldA = gw.hold('A', '/api/tenants/');
    final syncA = repo.syncWithBackend();
    await pumpEventQueue();

    await switchToB();
    final runsBefore = repo.syncRunCount;
    await repo.syncWithBackend(); // không bị bỏ qua dù lượt của A vẫn đang treo
    expect(repo.syncRunCount, runsBefore + 1);
    expect(repo.properties.single.name, 'Nhà B1');
    expect(repo.tenants.single.fullName, 'Khách B');
    expect(repo.isSyncing, isFalse);

    heldA.complete();
    await syncA;
    expect(gw.calls, contains('GET /api/tenants/ [A]'));
  });

  test('8. Response của A về SAU khi B đã đồng bộ không được ghi vào state của B', () async {
    await repo.syncWithBackend(); // A đã có dữ liệu
    final heldAll = [
      for (final p in [
        '/api/properties/',
        '/api/tenants/',
        '/api/notifications/',
        '/api/billing/invoices/',
        '/api/dashboard/summary/'
      ])
        gw.hold('A', p),
    ];
    final syncA = repo.syncWithBackend();
    await pumpEventQueue();

    await switchToB();
    await repo.syncWithBackend();
    final genB = repo.sessionGeneration;

    for (final h in heldAll) {
      h.complete();
    }
    await syncA;
    await pumpEventQueue();

    expect(repo.sessionGeneration, genB);
    expect(repo.properties.map((p) => p.name), ['Nhà B1']);
    expect(repo.tenants.map((t) => t.fullName), ['Khách B']);
    expect(repo.notifications.map((n) => n.title), ['Thông báo B']);
    expect(repo.invoices.map((i) => i.code), ['HDN-B']);
    expect(repo.dashboardSummary?.totalProperties, 1);
    for (final s in DataSection.values) {
      expect(repo.sectionState(s).status, LoadStatus.loaded, reason: '$s');
    }
  });

  test('8b. Request GHI của A còn đang chờ khi đổi sang B: không áp dụng, không đồng bộ cho B', () async {
    await repo.syncWithBackend();
    final heldWrite = gw.hold('A', '/api/properties/', method: 'POST');
    final write = repo.addProperty(const PropertyItem(
      id: 0,
      code: '',
      name: 'Nhà mới của A',
      address: '1 Lê Lợi',
      district: 'Quận 1',
      totalRooms: 0,
      occupiedRooms: 0,
      availableRooms: 0,
      status: 'ACTIVE',
    ));
    await pumpEventQueue();

    await switchToB();
    await repo.syncWithBackend();
    final runsAfterB = repo.syncRunCount;

    heldWrite.complete();
    final result = await write;

    expect(result, AppDataRepository.sessionChangedError, reason: 'không báo "thành công" cho phiên B');
    expect(repo.syncRunCount, runsAfterB, reason: 'không kích hoạt sync bằng kết quả của phiên A');
    expect(repo.properties.map((p) => p.name), ['Nhà B1']);
  });

  test('8c. Đọc phụ (lịch sử) của phiên A trả về sau khi đổi tài khoản -> báo lỗi, không trả dữ liệu', () async {
    await repo.syncWithBackend();
    gw.overrides['/api/tenants/20/history/'] = (_) => _json([]);
    final held = gw.hold('A', '/api/tenants/20/history/');
    final history = repo.fetchTenantHistory(20);
    await pumpEventQueue();
    await switchToB();
    held.complete();
    await expectLater(history, throwsA(isA<ApiException>()));
  });

  test('9. Ghi thành công trong lúc đang sync -> có thêm một lượt sync mới, danh sách cập nhật', () async {
    await repo.syncWithBackend();
    final runsBefore = repo.syncRunCount;

    final held = gw.hold('A', '/api/tenants/');
    final background = repo.syncWithBackend(); // lượt này đã lấy danh sách nhà trọ cũ (1 nhà)
    await pumpEventQueue();

    final write = repo.addProperty(const PropertyItem(
      id: 0,
      code: '',
      name: 'Nhà A2',
      address: '2 Lê Lợi',
      district: 'Quận 1',
      totalRooms: 0,
      occupiedRooms: 0,
      availableRooms: 0,
      status: 'ACTIVE',
    ));
    await pumpEventQueue();
    gw.holds.clear();
    held.complete();

    expect(await write, isNull);
    await background;
    expect(repo.syncRunCount, runsBefore + 2, reason: 'lượt đang chạy + đúng một lượt sau khi ghi');
    expect(repo.properties, hasLength(2), reason: 'danh sách phản ánh dữ liệu sau khi ghi');
    expect(repo.isSyncing, isFalse);
  });

  test('10. Nhiều yêu cầu sync liên tiếp: gộp lại, không mất yêu cầu cuối, không lặp vô hạn', () async {
    final held = gw.hold('A', '/api/tenants/');
    final first = repo.syncWithBackend();
    await pumpEventQueue();

    final more = [for (var i = 0; i < 5; i++) repo.syncWithBackend()];
    gw.propertyCount['A'] = 3; // dữ liệu thay đổi sau yêu cầu cuối cùng
    gw.holds.clear();
    held.complete();
    await Future.wait([first, ...more]);

    expect(repo.syncRunCount, 2, reason: '1 lượt đang chạy + 1 lượt gộp cho 5 yêu cầu');
    expect(repo.properties, hasLength(3), reason: 'kết quả phản ánh yêu cầu cuối');
    expect(repo.isSyncing, isFalse);

    // Không còn yêu cầu nào -> không tự chạy thêm.
    await pumpEventQueue();
    expect(repo.syncRunCount, 2);
  });

  test('11. Lỗi mạng (Gateway mất kết nối) không xóa dữ liệu đã tải; kết nối lại thì phục hồi', () async {
    await repo.syncWithBackend();
    gw.gatewayDown = true;
    await repo.syncWithBackend();

    expect(repo.isBackendConnected, isFalse);
    expect(repo.lastSyncError, isNotNull);
    expect(repo.properties.single.name, 'Nhà A1');
    expect(repo.tenants.single.fullName, 'Khách A');
    expect(repo.notifications, hasLength(1));
    expect(repo.dashboardSummary?.totalProperties, 1);
    for (final s in DataSection.values) {
      expect(repo.sectionState(s).status, LoadStatus.error, reason: '$s');
      expect(repo.sectionState(s).hasData, isTrue, reason: '$s');
    }
    expect(await repo.markAllNotificationsRead(), AppDataRepository.offlineWriteError);

    gw.gatewayDown = false;
    await repo.syncWithBackend();
    expect(repo.isBackendConnected, isTrue);
    expect(repo.lastSyncError, isNull);
    expect(repo.failedSections, isEmpty);
  });

  test('11b. Health UP nhưng mọi request dữ liệu đều mất kết nối -> coi Gateway mất phản hồi, giữ dữ liệu', () async {
    await repo.syncWithBackend();
    for (final p in [
      '/api/dashboard/summary/',
      '/api/properties/',
      '/api/rooms/',
      '/api/maintenance/',
      '/api/maintenance-history/',
      '/api/tenants/',
      '/api/contracts/',
      '/api/billing/invoices/',
      '/api/notifications/'
    ]) {
      gw.overrides[p] = (_) => throw http.ClientException('reset');
    }
    await repo.syncWithBackend();
    expect(repo.isBackendConnected, isFalse);
    expect(repo.properties, hasLength(1));
    expect(repo.sectionState(DataSection.properties).status, LoadStatus.error);
  });

  test('12. Logout xóa toàn bộ dữ liệu của phiên trước', () async {
    await repo.syncWithBackend();
    final genBefore = repo.sessionGeneration;

    repo.resetAfterLogout();

    expect(repo.sessionGeneration, genBefore + 1);
    expect(repo.properties, isEmpty);
    expect(repo.rooms, isEmpty);
    expect(repo.maintenances, isEmpty);
    expect(repo.tenants, isEmpty);
    expect(repo.contracts, isEmpty);
    expect(repo.invoices, isEmpty);
    expect(repo.notifications, isEmpty);
    expect(repo.dashboardSummary, isNull);
    expect(repo.dashboardError, isNull);
    expect(repo.isBackendConnected, isFalse);
    expect(repo.hasSyncedOnce, isFalse);
    for (final s in DataSection.values) {
      expect(repo.sectionState(s).status, LoadStatus.notLoaded, reason: '$s');
    }
  });

  test('13. Phản hồi không phải danh sách -> Error, không coi là danh sách rỗng', () async {
    await repo.syncWithBackend();
    gw.overrides['/api/rooms/'] = (_) => _json({'unexpected': true});
    await repo.syncWithBackend();
    expect(repo.sectionState(DataSection.rooms).status, LoadStatus.error);
    expect(repo.rooms.single.name, 'Phòng A');
  });

  test('14. Dashboard summary lỗi 500: giữ số liệu lần trước, báo lỗi; 403 -> Forbidden', () async {
    await repo.syncWithBackend();
    gw.overrides['/api/dashboard/summary/'] = (_) => _json({'error': 'Gateway lỗi'}, 500);
    await repo.syncWithBackend();
    expect(repo.sectionState(DataSection.dashboard).status, LoadStatus.error);
    expect(repo.dashboardSummary?.totalProperties, 1);
    expect(repo.dashboardError, 'Gateway lỗi');

    gw.overrides['/api/dashboard/summary/'] = (_) => _json({'detail': 'Không có quyền.'}, 403);
    await repo.syncWithBackend();
    expect(repo.sectionState(DataSection.dashboard).status, LoadStatus.forbidden);
    expect(repo.dashboardSummary, isNull);
  });

  test('Trong lúc đang tải: nhóm ở trạng thái Loading và vẫn giữ dữ liệu cũ', () async {
    await repo.syncWithBackend();
    final held = gw.hold('A', '/api/tenants/');
    final sync = repo.syncWithBackend();
    await pumpEventQueue();
    for (final s in _listSections) {
      expect(repo.sectionState(s).status, LoadStatus.loading, reason: '$s');
      expect(repo.sectionState(s).hasData, isTrue);
    }
    expect(repo.tenants.single.fullName, 'Khách A');
    held.complete();
    await sync;
    expect(repo.sectionState(DataSection.tenants).status, LoadStatus.loaded);
  });
}
