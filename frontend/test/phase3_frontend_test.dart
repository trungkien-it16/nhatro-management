// Giai đoạn 3 — Frontend: Dashboard theo vai trò, trang TENANT chỉ xem, liên kết tài khoản TENANT
// trong form người thuê, ẩn nút gọi API đang khóa Sprint, bộ lọc tháng hóa đơn lấy từ dữ liệu thật.
// Dùng AppDataRepository + AuthProvider THẬT, Gateway giả (MockClient).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/core/widgets/status_badge.dart';
import 'package:nhatro_frontend/features/tenant_portal/presentation/tenant_dashboard.dart';
import 'package:nhatro_frontend/main.dart';
import 'package:nhatro_frontend/providers/auth_provider.dart';
import 'package:nhatro_frontend/shared/services/api_client.dart';
import 'package:nhatro_frontend/shared/services/app_data_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

class _RoleAuth extends AuthProvider {
  _RoleAuth(this._role);
  final String _role;
  @override
  AuthStatus get status => AuthStatus.authenticated;
  @override
  bool get isAuthenticated => true;
  @override
  String get role => _role;
  @override
  String get displayName => 'Test $_role';
  @override
  String get roleDisplay => _role;
}

/// Gateway giả: dữ liệu theo đường dẫn, ghi lại request (method, path, body).
class _Gateway {
  final Map<String, Object?> data = {};
  final Map<String, FutureOr<http.Response> Function(Map<String, dynamic>? body)> overrides = {};
  final List<(String, String, Map<String, dynamic>?)> requests = [];

  List<Map<String, dynamic>?> bodies(String method, String path) =>
      [for (final r in requests) if (r.$1 == method && r.$2 == path) r.$3];

  MockClient get client => MockClient((req) async {
        final path = req.url.path;
        Map<String, dynamic>? body;
        if (req.body.isNotEmpty) {
          final decoded = jsonDecode(req.body);
          if (decoded is Map<String, dynamic>) body = decoded;
        }
        requests.add((req.method, path, body));
        final o = overrides['${req.method} $path'];
        if (o != null) return o(body);
        if (path == '/api/system/health/') {
          return _json({'gateway': {'status': 'UP', 'port': 8000}, 'overall_status': 'UP', 'services': []});
        }
        if (path == '/api/dashboard/summary/') return _json({'complete': true, 'errors': []});
        if (req.method != 'GET') return _json({'id': 1}, 201);
        return _json(data[path] ?? const []);
      });
}

const _room9 = {
  'id': 9,
  'code': 'NT002-301',
  'property': 2,
  'property_name': 'Nhà trọ B',
  'room_number': 'Phòng 301',
  'floor': 3,
  'area': 20,
  'rent_price': 3500000,
  'max_occupants': 2,
  'current_occupants': 1,
  'status': 'OCCUPIED',
};

void main() {
  late _Gateway gw;
  late AppDataRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient.resetForTest();
    gw = _Gateway();
    ApiClient.httpClient = gw.client;
    await ApiClient.saveSession(access: 'access', refresh: 'refresh');
    repo = AppDataRepository();
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ApiClient.resetForTest();
  });

  Finder key(String k) => find.byKey(Key(k));

  Future<void> openApp(WidgetTester tester, String location, {required String role}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(NhaTroManagerApp(authProvider: _RoleAuth(role), repository: repo));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, Finder select, String option) async {
    await tapVisible(tester, select);
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillTenantBasics(WidgetTester tester) async {
    final dialog = find.byType(AlertDialog);
    final fields = find.descendant(of: dialog, matching: find.byType(TextFormField));
    await tester.enterText(fields.at(0), 'Trần Thị Mai'); // Họ và tên
    await tester.enterText(fields.at(2), '0901234567'); // Số điện thoại
    await tester.pumpAndSettle();
  }

  // ------------------------------------------------------------------ Dashboard theo vai trò
  group('Dashboard theo vai trò', () {
    testWidgets('ADMIN: thẻ Tài khoản đếm từ Identity, có sơ đồ SOA, danh sách khách thuê', (tester) async {
      gw.data['/api/users/'] = [
        {'id': 1, 'username': 'admin', 'role': 'ADMIN'},
        {'id': 2, 'username': 'chutro1', 'role': 'LANDLORD'},
        {'id': 3, 'username': 'khach1', 'role': 'TENANT'},
      ];
      gw.data['/api/tenants/'] = [
        {'id': 1, 'full_name': 'Khách Một', 'status': 'ACTIVE', 'room_id': 9},
      ];
      await openApp(tester, '/', role: 'ADMIN');
      expect(find.text('Tổng quan hệ thống'), findsOneWidget);
      expect(find.descendant(of: key('dashboard_account_count'), matching: find.text('3')), findsOneWidget);
      expect(find.textContaining('ADMIN 1 · Chủ trọ 1 · Khách 1'), findsOneWidget);
      expect(key('soa_service_identity'), findsOneWidget);
      expect(find.descendant(of: key('dashboard_tenant_overview'), matching: find.text('Khách Một')), findsOneWidget);
    });

    testWidgets('LANDLORD: không có thẻ Tài khoản / sơ đồ SOA, không gọi /api/users/', (tester) async {
      await openApp(tester, '/', role: 'LANDLORD');
      expect(find.text('Tổng quan nhà trọ của bạn'), findsOneWidget);
      expect(key('dashboard_account_count'), findsNothing);
      expect(key('soa_service_identity'), findsNothing);
      expect(gw.bodies('GET', '/api/users/'), isEmpty);
      // Không có khách thuê -> trạng thái rỗng thật, không lỗi.
      expect(find.descendant(of: key('dashboard_tenants_status'), matching: find.text('Chưa có khách thuê nào.')),
          findsOneWidget);
    });

    testWidgets('TENANT: Dashboard cá nhân chỉ với dữ liệu của mình; rỗng không vỡ trang', (tester) async {
      await openApp(tester, '/', role: 'TENANT');
      expect(find.byType(TenantDashboard), findsOneWidget);
      expect(find.text('Bạn chưa có phòng đang thuê.'), findsOneWidget);
      expect(find.text('Bạn chưa có hợp đồng nào.'), findsOneWidget);
      expect(find.text('Bạn chưa có hóa đơn nào.'), findsOneWidget);
      expect(find.text('Chưa có thông báo nào.'), findsOneWidget);
      expect(key('soa_service_identity'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TENANT có dữ liệu: phòng, hợp đồng, hóa đơn cần thanh toán', (tester) async {
      gw.data['/api/rooms/'] = [_room9];
      gw.data['/api/properties/'] = [
        {'id': 2, 'code': 'NT002', 'name': 'Nhà trọ B', 'address': '12 Lê Lợi', 'status': 'ACTIVE'},
      ];
      gw.data['/api/contracts/'] = [
        {'id': 1, 'contract_number': 'HD-001', 'status': 'ACTIVE', 'room_id': 9, 'tenant_id': 1},
      ];
      gw.data['/api/billing/invoices/'] = [
        {'id': 1, 'invoice_code': 'HDN-1', 'status': 'UNPAID', 'total_amount': 4500000, 'billing_month': 10,
          'billing_year': 2026, 'room_id': 9},
      ];
      await openApp(tester, '/', role: 'TENANT');
      expect(find.textContaining('Phòng 301'), findsWidgets);
      expect(find.textContaining('HD-001'), findsOneWidget);
      expect(find.textContaining('HDN-1 · Kỳ 10/2026'), findsOneWidget);
      expect(find.text('Hệ thống chưa cung cấp thông tin liên hệ chủ trọ cho khách thuê.'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------ Trang TENANT chỉ xem
  group('Trang TENANT (/my-*)', () {
    testWidgets('Rỗng: mỗi trang hiển thị trạng thái rỗng thật, không có nút thao tác', (tester) async {
      for (final (route, emptyKey) in [
        ('/my-room', 'my_room_empty'),
        ('/my-profile', 'my_profile_empty'),
        ('/my-contracts', 'my_contracts_empty'),
        ('/my-bills', 'my_bills_empty'),
      ]) {
        await openApp(tester, route, role: 'TENANT');
        expect(key(emptyKey), findsOneWidget, reason: route);
        expect(find.byTooltip('Chỉnh sửa'), findsNothing, reason: route);
        expect(find.byTooltip('Xóa'), findsNothing, reason: route);
        expect(find.textContaining('+ '), findsNothing, reason: route);
      }
    });

    testWidgets('Có dữ liệu: hiển thị đúng, chỉ xem; 403 báo không có quyền', (tester) async {
      gw.data['/api/rooms/'] = [_room9];
      gw.data['/api/tenants/'] = [
        {'id': 1, 'full_name': 'Trần Thị Mai', 'status': 'ACTIVE', 'room_id': 9, 'user_id': 3},
      ];
      gw.data['/api/billing/invoices/'] = [
        {'id': 1, 'invoice_code': 'HDN-1', 'status': 'OVERDUE', 'total_amount': 100, 'billing_month': 9,
          'billing_year': 2026},
      ];
      gw.overrides['GET /api/contracts/'] = (_) => _json({'detail': 'Không có quyền.'}, 403);

      await openApp(tester, '/my-room', role: 'TENANT');
      expect(key('my_room_card_9'), findsOneWidget);
      await openApp(tester, '/my-profile', role: 'TENANT');
      expect(find.text('Trần Thị Mai'), findsOneWidget);
      expect(find.text('Đang thuê'), findsOneWidget);
      await openApp(tester, '/my-bills', role: 'TENANT');
      expect(find.text('HDN-1'), findsOneWidget);
      expect(find.textContaining('1 hóa đơn cần thanh toán'), findsOneWidget);
      await openApp(tester, '/my-contracts', role: 'TENANT');
      expect(key('my_contracts_forbidden'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------ Nút gọi API đang khóa
  group('Ẩn nút gọi API đang khóa Sprint', () {
    testWidgets('Hợp đồng: không có tạo/sửa/xóa/kích hoạt/gia hạn/chấm dứt; vẫn xem lịch sử', (tester) async {
      gw.data['/api/contracts/'] = [
        {'id': 1, 'contract_number': 'HD-1', 'status': 'ACTIVE'},
        {'id': 2, 'contract_number': 'HD-2', 'status': 'DRAFT'},
      ];
      await openApp(tester, '/contracts', role: 'LANDLORD');
      expect(find.text('HD-1'), findsOneWidget);
      expect(find.text('+ Tạo hợp đồng'), findsNothing);
      for (final t in ['Kích hoạt hợp đồng', 'Gia hạn hợp đồng', 'Thanh lý / Kết thúc', 'Chỉnh sửa', 'Xóa']) {
        expect(find.byTooltip(t), findsNothing, reason: t);
      }
      expect(find.byTooltip('Lịch sử hợp đồng'), findsNWidgets(2));
    });

    testWidgets('Hóa đơn: không có lập/sửa/xóa/thu tiền/hủy (cả khi danh sách rỗng)', (tester) async {
      await openApp(tester, '/bills', role: 'ADMIN');
      expect(key('invoice_list_empty'), findsOneWidget);
      expect(find.text('+ Lập hóa đơn'), findsNothing);

      gw.data['/api/billing/invoices/'] = [
        {'id': 1, 'invoice_code': 'HDN-1', 'status': 'UNPAID', 'total_amount': 1, 'billing_month': 10,
          'billing_year': 2026},
      ];
      await repo.syncWithBackend();
      await tester.pumpAndSettle();
      expect(find.text('HDN-1'), findsOneWidget);
      expect(find.text('THAO TÁC'), findsNothing);
      for (final t in ['Xác nhận đã thu tiền', 'Hủy hóa đơn', 'Chỉnh sửa', 'Xóa']) {
        expect(find.byTooltip(t), findsNothing, reason: t);
      }
    });

    testWidgets('Không request ghi nào tới API đang khóa khi duyệt các trang', (tester) async {
      await openApp(tester, '/contracts', role: 'LANDLORD');
      await openApp(tester, '/bills', role: 'LANDLORD');
      await openApp(tester, '/notifications', role: 'LANDLORD');
      expect(gw.requests.where((r) => r.$1 != 'GET'), isEmpty);
    });
  });

  // ------------------------------------------------------------------ Bộ lọc tháng
  testWidgets('Bộ lọc tháng hóa đơn lấy từ kỳ thu thật, mới nhất trước, không cố định 10–11/2026', (tester) async {
    gw.data['/api/billing/invoices/'] = [
      {'id': 1, 'invoice_code': 'A', 'status': 'PAID', 'total_amount': 1, 'billing_month': 1, 'billing_year': 2027},
      {'id': 2, 'invoice_code': 'B', 'status': 'UNPAID', 'total_amount': 1, 'billing_month': 9, 'billing_year': 2026},
      {'id': 3, 'invoice_code': 'C', 'status': 'UNPAID', 'total_amount': 1, 'billing_month': 12, 'billing_year': 2026},
    ];
    await openApp(tester, '/bills', role: 'LANDLORD');
    await tapVisible(tester, find.text('Tất cả các tháng'));
    final labels = tester
        .widgetList<Text>(find.textContaining('Tháng '))
        .map((t) => t.data)
        .where((t) => t != null && RegExp(r'^Tháng \d').hasMatch(t))
        .toSet()
        .toList();
    expect(labels, ['Tháng 1/2027', 'Tháng 12/2026', 'Tháng 9/2026']);
    expect(find.text('Tháng 11/2026'), findsNothing);
    await tester.tap(find.text('Tháng 9/2026').last);
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  test('StatusBadge người thuê dùng đúng trạng thái backend (không còn TEMPORARY_ABSENT)', () {
    expect(StatusBadge.fromTenantStatus('ACTIVE').label, 'Đang thuê');
    expect(StatusBadge.fromTenantStatus('INACTIVE').label, 'Chưa thuê / Tạm ngưng');
    expect(StatusBadge.fromTenantStatus('MOVED_OUT').label, 'Đã chuyển đi');
  });

  // ------------------------------------------------------------------ Form người thuê + tài khoản
  group('Form người thuê: liên kết tài khoản TENANT', () {
    setUp(() {
      gw.data['/api/rooms/'] = [_room9];
    });

    testWidgets('Trạng thái chỉ gồm ACTIVE / INACTIVE / MOVED_OUT', (tester) async {
      await openApp(tester, '/tenants', role: 'LANDLORD');
      await tapVisible(tester, find.text('+ Thêm người thuê').first);
      await tapVisible(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Đang thuê')));
      expect(find.text('Chưa thuê / Tạm ngưng'), findsWidgets);
      expect(find.text('Đã chuyển đi'), findsWidgets);
      expect(find.text('Tạm vắng'), findsNothing);
    });

    testWidgets('LANDLORD tạo tài khoản rồi tạo hồ sơ có user_id + room_id', (tester) async {
      gw.overrides['POST /api/users/'] = (_) => _json({'id': 42, 'username': 'mai01', 'role': 'TENANT'}, 201);
      gw.overrides['POST /api/tenants/'] = (_) => _json({'id': 7}, 201);
      await openApp(tester, '/tenants', role: 'LANDLORD');
      await tapVisible(tester, find.text('+ Thêm người thuê').first);
      await fillTenantBasics(tester);

      await choose(tester, key('tenant_form_account_mode'), 'Tạo tài khoản đăng nhập mới');
      expect(find.text('Chọn tài khoản TENANT có sẵn'), findsNothing, reason: 'chỉ ADMIN');
      await tester.enterText(find.descendant(of: key('tenant_form_username'), matching: find.byType(TextFormField)), 'mai01');
      await tester.enterText(find.descendant(of: key('tenant_form_password'), matching: find.byType(TextFormField)), 'matkhau123');
      await tapVisible(tester, find.text('Thêm người thuê'));

      final users = gw.bodies('POST', '/api/users/');
      expect(users, hasLength(1));
      expect(users.single, containsPair('username', 'mai01'));
      expect(users.single, containsPair('role', 'TENANT'));
      expect(users.single, containsPair('first_name', 'Trần Thị'));
      expect(users.single, containsPair('last_name', 'Mai'));
      final tenants = gw.bodies('POST', '/api/tenants/');
      expect(tenants, hasLength(1));
      expect(tenants.single, containsPair('user_id', 42));
      expect(tenants.single, containsPair('room_id', 9));
      expect(find.byType(AlertDialog), findsNothing, reason: 'thành công thì đóng form');
      expect(find.textContaining('liên kết tài khoản #42'), findsOneWidget);
    });

    testWidgets('Trùng tên đăng nhập: báo lỗi, KHÔNG tạo hồ sơ', (tester) async {
      gw.overrides['POST /api/users/'] =
          (_) => _json({'username': ['A user with that username already exists.']}, 400);
      await openApp(tester, '/tenants', role: 'LANDLORD');
      await tapVisible(tester, find.text('+ Thêm người thuê').first);
      await fillTenantBasics(tester);
      await choose(tester, key('tenant_form_account_mode'), 'Tạo tài khoản đăng nhập mới');
      await tester.enterText(find.descendant(of: key('tenant_form_username'), matching: find.byType(TextFormField)), 'khach1');
      await tester.enterText(find.descendant(of: key('tenant_form_password'), matching: find.byType(TextFormField)), 'matkhau123');
      await tapVisible(tester, find.text('Thêm người thuê'));

      expect(key('tenant_form_account_message'), findsOneWidget);
      expect(find.textContaining('Chưa tạo được tài khoản đăng nhập'), findsOneWidget);
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(gw.bodies('POST', '/api/tenants/'), isEmpty);
    });

    testWidgets('Tạo tài khoản xong nhưng hồ sơ lỗi: báo rõ, lưu lại KHÔNG tạo thêm tài khoản', (tester) async {
      gw.overrides['POST /api/users/'] = (_) => _json({'id': 42, 'username': 'mai01'}, 201);
      var failTenant = true;
      gw.overrides['POST /api/tenants/'] = (_) => failTenant
          ? _json({'room_id': ['Phòng không tồn tại hoặc không thuộc phạm vi quản lý của bạn.']}, 400)
          : _json({'id': 7}, 201);
      await openApp(tester, '/tenants', role: 'LANDLORD');
      await tapVisible(tester, find.text('+ Thêm người thuê').first);
      await fillTenantBasics(tester);
      await choose(tester, key('tenant_form_account_mode'), 'Tạo tài khoản đăng nhập mới');
      await tester.enterText(find.descendant(of: key('tenant_form_username'), matching: find.byType(TextFormField)), 'mai01');
      await tester.enterText(find.descendant(of: key('tenant_form_password'), matching: find.byType(TextFormField)), 'matkhau123');
      await tapVisible(tester, find.text('Thêm người thuê'));

      expect(find.textContaining('ĐÃ được tạo nhưng chưa lưu được'), findsOneWidget);
      expect(find.textContaining('không thuộc phạm vi quản lý'), findsWidgets);
      expect(find.textContaining('không tạo tài khoản mới'), findsOneWidget);
      expect(gw.bodies('POST', '/api/users/'), hasLength(1));
      expect(gw.bodies('POST', '/api/tenants/'), hasLength(1), reason: 'không tự gửi lại');

      // Người dùng sửa và bấm lưu lại: chỉ gửi lại hồ sơ với tài khoản đã tạo.
      failTenant = false;
      await tapVisible(tester, find.text('Thêm người thuê'));
      expect(gw.bodies('POST', '/api/users/'), hasLength(1), reason: 'không tạo trùng tài khoản');
      expect(gw.bodies('POST', '/api/tenants/'), hasLength(2));
      expect(gw.bodies('POST', '/api/tenants/').last, containsPair('user_id', 42));
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Đóng form sau khi hồ sơ lỗi: mở lại dùng lại tài khoản đã tạo', (tester) async {
      gw.overrides['POST /api/users/'] = (_) => _json({'id': 42, 'username': 'mai01'}, 201);
      gw.overrides['POST /api/tenants/'] = (_) => _json({'error': 'Tenant DOWN'}, 503);
      await openApp(tester, '/tenants', role: 'LANDLORD');
      await tapVisible(tester, find.text('+ Thêm người thuê').first);
      await fillTenantBasics(tester);
      await choose(tester, key('tenant_form_account_mode'), 'Tạo tài khoản đăng nhập mới');
      await tester.enterText(find.descendant(of: key('tenant_form_username'), matching: find.byType(TextFormField)), 'mai01');
      await tester.enterText(find.descendant(of: key('tenant_form_password'), matching: find.byType(TextFormField)), 'matkhau123');
      await tapVisible(tester, find.text('Thêm người thuê'));
      await tapVisible(tester, find.text('Hủy'));

      await tapVisible(tester, find.text('+ Thêm người thuê').first);
      expect(key('tenant_form_account_reuse'), findsOneWidget);
      expect(find.textContaining('"mai01" (ID #42)'), findsOneWidget);
      expect(key('tenant_form_username'), findsNothing);
    });

    testWidgets('ADMIN chọn tài khoản TENANT có sẵn: chỉ TENANT đang hoạt động, chưa liên kết', (tester) async {
      gw.data['/api/users/'] = [
        {'id': 1, 'username': 'admin', 'role': 'ADMIN', 'full_name': 'Admin'},
        {'id': 2, 'username': 'chutro1', 'role': 'LANDLORD', 'full_name': 'Chủ trọ'},
        {'id': 4, 'username': 'staff1', 'role': 'STAFF', 'full_name': 'Nhân viên'},
        {'id': 5, 'username': 'dalienket', 'role': 'TENANT', 'full_name': 'Đã liên kết'},
        {'id': 6, 'username': 'khachmoi', 'role': 'TENANT', 'full_name': 'Khách Mới'},
        {'id': 7, 'username': 'bikhoa', 'role': 'TENANT', 'full_name': 'Bị khóa', 'is_active': false},
        {'id': 8, 'username': 'dachuyen', 'role': 'TENANT', 'full_name': 'Đã chuyển'},
      ];
      gw.data['/api/tenants/'] = [
        {'id': 1, 'full_name': 'Đã liên kết', 'status': 'ACTIVE', 'user_id': 5},
        {'id': 2, 'full_name': 'Đã chuyển', 'status': 'MOVED_OUT', 'user_id': 8},
      ];
      gw.overrides['POST /api/tenants/'] = (_) => _json({'id': 9}, 201);
      await openApp(tester, '/tenants', role: 'ADMIN');
      await tapVisible(tester, find.text('+ Thêm người thuê').first);
      await fillTenantBasics(tester);
      await choose(tester, key('tenant_form_account_mode'), 'Chọn tài khoản TENANT có sẵn');
      await tapVisible(tester, key('tenant_form_existing_account'));
      expect(find.textContaining('khachmoi'), findsWidgets);
      expect(find.textContaining('dachuyen'), findsWidgets, reason: 'hồ sơ cũ đã chuyển đi -> được liên kết lại');
      for (final u in ['admin', 'chutro1', 'staff1', 'dalienket', 'bikhoa']) {
        expect(find.textContaining('$u —'), findsNothing, reason: u);
      }
      await tester.tap(find.textContaining('khachmoi').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Thêm người thuê'));

      expect(gw.bodies('POST', '/api/users/'), isEmpty, reason: 'dùng tài khoản có sẵn');
      expect(gw.bodies('POST', '/api/tenants/').single, containsPair('user_id', 6));
    });

    testWidgets('Chọn chế độ "có sẵn" mà chưa chọn tài khoản: báo, không gửi request', (tester) async {
      gw.data['/api/users/'] = const [];
      await openApp(tester, '/tenants', role: 'ADMIN');
      await tapVisible(tester, find.text('+ Thêm người thuê').first);
      await fillTenantBasics(tester);
      await choose(tester, key('tenant_form_account_mode'), 'Chọn tài khoản TENANT có sẵn');
      expect(key('tenant_form_no_accounts'), findsOneWidget);
      await tapVisible(tester, find.text('Thêm người thuê'));
      expect(find.text('Chọn tài khoản TENANT cần liên kết.'), findsOneWidget);
      expect(gw.requests.where((r) => r.$1 == 'POST'), isEmpty);
    });

    testWidgets('Hồ sơ đã liên kết: chỉ hiển thị, sửa hồ sơ giữ nguyên user_id', (tester) async {
      gw.data['/api/tenants/'] = [
        {'id': 1, 'full_name': 'Trần Thị Mai', 'phone_number': '090', 'status': 'ACTIVE', 'user_id': 3, 'room_id': 9},
      ];
      gw.overrides['PATCH /api/tenants/1/'] = (_) => _json({'id': 1});
      await openApp(tester, '/tenants', role: 'LANDLORD');
      await tapVisible(tester, find.byTooltip('Chỉnh sửa'));
      expect(key('tenant_form_account_linked'), findsOneWidget);
      expect(key('tenant_form_account_mode'), findsNothing);
      await tapVisible(tester, find.text('Lưu thay đổi'));
      expect(gw.bodies('PATCH', '/api/tenants/1/').single, containsPair('user_id', 3));
      expect(gw.bodies('POST', '/api/users/'), isEmpty);
    });
  });
}
