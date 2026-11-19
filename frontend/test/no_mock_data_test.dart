// Chặng 1 — Không dùng dữ liệu mẫu: repository, Dashboard, CRUD khi offline/lỗi API.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/core/widgets/app_sidebar.dart';
import 'package:nhatro_frontend/main.dart';
import 'package:nhatro_frontend/models/dashboard_summary_model.dart';
import 'package:nhatro_frontend/providers/auth_provider.dart';
import 'package:nhatro_frontend/shared/models/app_models.dart';
import 'package:nhatro_frontend/shared/services/api_client.dart';
import 'package:nhatro_frontend/shared/services/app_data_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ----------------------------------------------------------------- helpers
http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

const _healthUp = {
  'gateway': {'status': 'UP', 'port': 8000},
  'overall_status': 'UP',
  'services': [
    {'key': 'identity', 'name': 'Identity', 'port': 8001, 'status': 'UP'},
    {'key': 'property', 'name': 'Property', 'port': 8002, 'status': 'UP'},
  ],
};

const _property = {
  'id': 1,
  'code': 'NT-REAL',
  'name': 'Nhà trọ thật',
  'address': '1 Lê Lợi',
  'district': 'Quận 1',
  'status': 'ACTIVE',
  'total_rooms_count': 1,
  'occupied_rooms_count': 0,
  'available_rooms_count': 1,
};

const _room = {
  'id': 10,
  'code': 'P-REAL',
  'property': 1,
  'property_name': 'Nhà trọ thật',
  'room_number': 'Phòng thật',
  'floor': 1,
  'area': 20,
  'rent_price': 3000000,
  'max_occupants': 2,
  'current_occupants': 0,
  'status': 'AVAILABLE',
};

/// Gateway giả: trả dữ liệu thật tối thiểu; [writeHandler] quyết định kết quả thao tác ghi.
MockClient _gateway({
  required List<String> calls,
  bool gatewayUp = true,
  bool Function()? isUp,
  http.Response Function(http.Request req)? writeHandler,
}) {
  return MockClient((req) async {
    if (!(isUp?.call() ?? gatewayUp)) throw http.ClientException('Connection refused');
    calls.add('${req.method} ${req.url.path}');
    if (req.method != 'GET') {
      return writeHandler?.call(req) ?? _json({'ok': true}, 201);
    }
    if (req.url.path == '/api/system/health/') {
      return _json(_healthUp);
    }
    return switch (req.url.path) {
      '/api/dashboard/summary/' => _json({'total_properties': 1, 'total_rooms': 1}),
      '/api/properties/' => _json([_property]),
      '/api/rooms/' => _json([_room]),
      _ => _json([]),
    };
  });
}

const _formerMockCodes = ['NT-001', 'NT-002', 'NT-003', 'NT-004'];

class _FakeAuth extends AuthProvider {
  @override
  AuthStatus get status => AuthStatus.authenticated;
  @override
  bool get isAuthenticated => true;
  @override
  String get displayName => 'Chủ trọ Test';
  @override
  String get roleDisplay => 'Chủ nhà trọ';
  @override
  String get role => 'LANDLORD';
}

/// Repository mô phỏng Gateway lỗi: sync thất bại cho tới khi [recoverOnNextSync].
class _FailingRepository extends AppDataRepository {
  int syncCalls = 0;
  bool recoverOnNextSync = false;

  @override
  Future<void> syncWithBackend() async {
    syncCalls++;
    if (recoverOnNextSync) {
      isBackendConnected = true;
      hasSyncedOnce = true;
      lastSyncError = null;
      dashboardSummary = DashboardSummary.fromJson({'total_properties': 7, 'total_rooms': 21});
    } else {
      isBackendConnected = false;
      lastSyncError = 'Không kết nối được tới API Gateway (http://127.0.0.1:8000).';
    }
    notifyListeners();
  }
}

/// Repository mô phỏng đã kết nối, Dashboard có số liệu thật.
class _ConnectedRepository extends AppDataRepository {
  bool _synced = false;

  /// Như repository thật sau một lượt đồng bộ thành công: mọi nhóm dữ liệu ở trạng thái Loaded.
  @override
  SectionState sectionState(DataSection section) =>
      _synced ? const SectionState(LoadStatus.loaded, hasData: true) : SectionState.notLoaded;

  @override
  Future<void> syncWithBackend() async {
    isBackendConnected = true;
    hasSyncedOnce = true;
    _synced = true;
    dashboardSummary = DashboardSummary.fromJson({
      'total_properties': 3,
      'total_rooms': 9,
      'occupied_rooms': 4,
      'available_rooms': 5,
      'active_contracts': 2,
      'unpaid_invoices': 1,
      'estimated_monthly_revenue': 12000000,
      'unpaid_amount': '3500000',
    });
    notifyListeners();
  }
}

void _desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

PropertyItem _newProperty() => const PropertyItem(
      id: 99,
      code: 'NT-NEW',
      name: 'Nhà trọ mới',
      address: '2 Lê Lợi',
      district: 'Quận 1',
      totalRooms: 0,
      occupiedRooms: 0,
      availableRooms: 0,
      status: 'ACTIVE',
    );

RoomItem _newRoom() => const RoomItem(
      id: 99,
      code: 'P-NEW',
      name: 'Phòng mới',
      propertyId: 1,
      propertyName: 'Nhà trọ thật',
      floor: 1,
      rentPrice: 3000000,
      area: 20,
      currentOccupants: 0,
      maxOccupants: 2,
      status: 'AVAILABLE',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ApiClient.httpClient = http.Client());

  // =============================================================== REPOSITORY
  group('Repository không có dữ liệu mẫu', () {
    test('Khởi tạo: mọi danh sách rỗng, chưa kết nối, chưa đồng bộ', () {
      final repo = AppDataRepository();
      expect(repo.properties, isEmpty);
      expect(repo.rooms, isEmpty);
      expect(repo.tenants, isEmpty);
      expect(repo.contracts, isEmpty);
      expect(repo.invoices, isEmpty);
      expect(repo.maintenances, isEmpty);
      expect(repo.maintenanceHistories, isEmpty);
      expect(repo.notifications, isEmpty);
      expect(repo.revenuePoints, isEmpty);
      expect(repo.isBackendConnected, isFalse);
      expect(repo.hasSyncedOnce, isFalse);
    });

    test('Gateway không phản hồi: báo lỗi, không nạp dữ liệu mẫu', () async {
      final calls = <String>[];
      ApiClient.httpClient = _gateway(calls: calls, gatewayUp: false);
      await ApiClient.saveSession(access: 'token');

      final repo = AppDataRepository();
      await repo.syncWithBackend();

      expect(repo.isBackendConnected, isFalse);
      expect(repo.hasSyncedOnce, isFalse);
      expect(repo.lastSyncError, isNotNull);
      expect(repo.properties, isEmpty);
      expect(repo.rooms, isEmpty);
      expect(repo.dashboardSummary, isNull);
    });

    test('Đồng bộ thành công: chỉ có dữ liệu thật từ Gateway', () async {
      final calls = <String>[];
      ApiClient.httpClient = _gateway(calls: calls);
      await ApiClient.saveSession(access: 'token');

      final repo = AppDataRepository();
      await repo.syncWithBackend();

      expect(repo.isBackendConnected, isTrue);
      expect(repo.hasSyncedOnce, isTrue);
      expect(repo.properties.map((p) => p.code), ['NT-REAL']);
      expect(repo.rooms.map((r) => r.code), ['P-REAL']);
      for (final code in _formerMockCodes) {
        expect(repo.properties.any((p) => p.code == code), isFalse);
      }
    });

    test('Thử lại sau khi kết nối được khôi phục', () async {
      final calls = <String>[];
      var up = false;
      ApiClient.httpClient = _gateway(calls: calls, isUp: () => up);
      await ApiClient.saveSession(access: 'token');

      final repo = AppDataRepository();
      await repo.syncWithBackend();
      expect(repo.isBackendConnected, isFalse);
      expect(repo.lastSyncError, isNotNull);

      up = true;
      await repo.syncWithBackend();
      expect(repo.isBackendConnected, isTrue);
      expect(repo.lastSyncError, isNull);
      expect(repo.properties.single.code, 'NT-REAL');
    });

    test('Mất kết nối sau khi đã đồng bộ: giữ dữ liệu thật gần nhất và báo lỗi', () async {
      final calls = <String>[];
      var up = true;
      ApiClient.httpClient = _gateway(calls: calls, isUp: () => up);
      await ApiClient.saveSession(access: 'token');

      final repo = AppDataRepository();
      await repo.syncWithBackend();
      up = false;
      await repo.syncWithBackend();

      expect(repo.isBackendConnected, isFalse);
      expect(repo.hasSyncedOnce, isTrue);
      expect(repo.lastSyncError, isNotNull);
      expect(repo.properties.single.code, 'NT-REAL');
    });

    test('Đăng xuất: xóa dữ liệu phiên, không nạp lại dữ liệu mẫu', () async {
      final calls = <String>[];
      ApiClient.httpClient = _gateway(calls: calls);
      await ApiClient.saveSession(access: 'token');

      final repo = AppDataRepository();
      await repo.syncWithBackend();
      repo.resetAfterLogout();

      expect(repo.properties, isEmpty);
      expect(repo.rooms, isEmpty);
      expect(repo.isBackendConnected, isFalse);
      expect(repo.hasSyncedOnce, isFalse);
    });
  });

  // =============================================================== CRUD OFFLINE
  group('CRUD khi chưa kết nối: không báo thành công giả', () {
    test('Nhà trọ / phòng: trả lỗi, không gửi request, không đổi dữ liệu', () async {
      final calls = <String>[];
      ApiClient.httpClient = _gateway(calls: calls);
      final repo = AppDataRepository();

      final results = [
        await repo.addProperty(_newProperty()),
        await repo.updateProperty(_newProperty()),
        await repo.deleteProperty(1),
        await repo.updatePropertyStatus(1, 'INACTIVE'),
        await repo.addRoom(_newRoom()),
        await repo.updateRoom(_newRoom()),
        await repo.deleteRoom(10),
        await repo.updateRoomStatus(10, 'MAINTENANCE'),
      ];

      for (final r in results) {
        expect(r, AppDataRepository.offlineWriteError);
      }
      expect(calls, isEmpty);
      expect(repo.properties, isEmpty);
      expect(repo.rooms, isEmpty);
    });

    test('Các thao tác ghi khác cũng trả lỗi khi offline', () async {
      final calls = <String>[];
      ApiClient.httpClient = _gateway(calls: calls);
      final repo = AppDataRepository();

      final results = [
        await repo.deleteTenant(1),
        await repo.activateContract(1),
        await repo.extendContract(1, newEndDate: '2027-01-01'),
        await repo.terminateContract(1),
        await repo.payInvoice(1),
        await repo.cancelInvoice(1),
        await repo.deleteMaintenance(1),
        await repo.recordMaintenanceCost(1, estimatedCost: 1, actualCost: 1),
        await repo.completeMaintenance(1, actualCost: 1, roomStatus: 'AVAILABLE', repairInfo: ''),
        await repo.markAllNotificationsRead(),
        await repo.markNotificationRead(1),
        await repo.addTenantHistory(1, roomId: 1, moveInDate: '2026-01-01'),
      ];
      for (final r in results) {
        expect(r, AppDataRepository.offlineWriteError);
      }
      expect(calls, isEmpty);
    });

    test('Thao tác đọc phụ khi offline ném lỗi thay vì tự bịa kết quả', () async {
      final repo = AppDataRepository();
      await expectLater(repo.checkRoomRentable(_newRoom()), throwsA(isA<ApiException>()));
      await expectLater(repo.fetchTenantHistory(1), throwsA(isA<ApiException>()));
      await expectLater(repo.fetchContractHistory(1), throwsA(isA<ApiException>()));
    });
  });

  // =============================================================== CRUD API LỖI
  group('CRUD khi API thất bại: hiển thị lỗi backend, không đổi dữ liệu', () {
    Future<AppDataRepository> connectedRepo(http.Response Function(http.Request) onWrite,
        List<String> calls) async {
      ApiClient.httpClient = _gateway(calls: calls, writeHandler: onWrite);
      await ApiClient.saveSession(access: 'token');
      final repo = AppDataRepository();
      await repo.syncWithBackend();
      expect(repo.isBackendConnected, isTrue);
      return repo;
    }

    test('Thêm nhà trọ bị backend từ chối (400): trả thông báo lỗi validate', () async {
      final calls = <String>[];
      final repo = await connectedRepo(
          (_) => _json({'name': ['Tên nhà trọ không được để trống.']}, 400), calls);

      final err = await repo.addProperty(_newProperty());

      expect(err, contains('Tên nhà trọ không được để trống.'));
      expect(calls, contains('POST /api/properties/'));
      expect(repo.properties.map((p) => p.code), ['NT-REAL']);
    });

    test('Xóa phòng khi Property Service DOWN (503): trả lỗi, phòng vẫn còn', () async {
      final calls = <String>[];
      final repo = await connectedRepo(
          (_) => _json({'error': 'Property & Room Service hiện không hoạt động (port 8002).'}, 503), calls);

      final err = await repo.deleteRoom(10);

      expect(err, contains('không hoạt động'));
      expect(calls, contains('DELETE /api/rooms/10/'));
      expect(repo.rooms.single.code, 'P-REAL');
    });

    test('Thêm phòng thành công chỉ khi backend xác nhận, rồi đồng bộ lại', () async {
      final calls = <String>[];
      final repo = await connectedRepo((_) => _json({'id': 11}, 201), calls);
      calls.clear();

      final err = await repo.addRoom(_newRoom());

      expect(err, isNull);
      expect(calls.first, 'POST /api/rooms/');
      expect(calls, contains('GET /api/rooms/'), reason: 'phải tải lại dữ liệu thật sau khi ghi');
    });
  });

  // =============================================================== DASHBOARD UI
  group('Dashboard', () {
    testWidgets('Chưa kết nối: không hiển thị số liệu mẫu, có lỗi + nút Thử lại', (tester) async {
      _desktop(tester);
      final repo = _FailingRepository();
      await tester.pumpWidget(NhaTroManagerApp(authProvider: _FakeAuth(), repository: repo));
      await tester.pumpAndSettle();

      expect(find.text('Tổng quan nhà trọ của bạn'), findsOneWidget);
      expect(find.textContaining('Chưa có số liệu tổng quan'), findsOneWidget);
      expect(find.textContaining('Không kết nối được API Gateway'), findsOneWidget);
      // 8 thẻ KPI (6 cũ + "Doanh thu dự kiến / tháng" + "Tổng tiền chưa thanh toán" của Chặng 5).
      expect(find.text('—'), findsNWidgets(8), reason: '8 thẻ KPI đều chưa có số liệu');
      expect(find.text('Chưa có dữ liệu doanh thu theo tháng'), findsOneWidget);
      for (final code in _formerMockCodes) {
        expect(find.text(code), findsNothing);
      }

      // Kết nối được khôi phục -> bấm Thử lại -> hiển thị số liệu thật.
      repo.recoverOnNextSync = true;
      final before = repo.syncCalls;
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(repo.syncCalls, before + 1);
      expect(find.textContaining('Không kết nối được API Gateway'), findsNothing);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
    });

    testWidgets('Đã kết nối: hiển thị số liệu từ /api/dashboard/summary/', (tester) async {
      _desktop(tester);
      await tester.pumpWidget(
          NhaTroManagerApp(authProvider: _FakeAuth(), repository: _ConnectedRepository()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Chưa có số liệu tổng quan'), findsNothing);
      expect(find.text('—'), findsNothing, reason: 'mọi thẻ KPI đều có số liệu thật');
      expect(find.text('3'), findsWidgets); // tổng tòa nhà
      expect(find.text('9'), findsWidgets); // tổng phòng (thẻ KPI + biểu đồ tỷ lệ)
      expect(find.text('Chưa có tòa nhà nào.'), findsOneWidget);
      expect(find.text('Chưa có hóa đơn nào.'), findsOneWidget);
    });
  });

  // =============================================================== PAGE STATES
  group('Trang Nhà trọ / Phòng khi lỗi kết nối', () {
    testWidgets('Hiển thị trạng thái lỗi kèm Thử lại thay vì "danh sách rỗng"', (tester) async {
      _desktop(tester);
      final repo = _FailingRepository();
      await tester.pumpWidget(NhaTroManagerApp(authProvider: _FakeAuth(), repository: repo));
      await tester.pumpAndSettle();

      for (final nav in ['Nhà trọ', 'Phòng']) {
        await tester.tap(find.descendant(of: find.byType(AppSidebar), matching: find.text(nav)).first);
        await tester.pumpAndSettle();
        expect(find.text('Không thể tải dữ liệu'), findsOneWidget, reason: nav);
        expect(find.text('Không tìm thấy tòa nhà nào'), findsNothing);
        expect(find.text('Không có phòng nào phù hợp'), findsNothing);
      }

      final before = repo.syncCalls;
      // Nút "Thử lại" có ở cả banner chung (MainLayout) và ErrorState của trang.
      expect(find.text('Thử lại'), findsNWidgets(2));
      await tester.tap(find.text('Thử lại').last);
      await tester.pumpAndSettle();
      expect(repo.syncCalls, greaterThan(before));
    });
  });
}
