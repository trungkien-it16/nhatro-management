// Responsive: mọi route của từng vai trò, ở kích thước điện thoại / máy tính bảng / laptop / màn hình lớn,
// với dữ liệu thật dạng API — không được có lỗi layout (RenderFlex overflow...) hay exception.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/core/auth/role_access.dart';
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
  String get displayName => 'Nguyễn Văn Người Dùng Có Tên Dài $_role';
  @override
  String get roleDisplay => _role;
}

final Map<String, Object?> _data = {
  '/api/properties/': [
    {'id': 2, 'code': 'NT002', 'name': 'Căn hộ Mini Happy House - Quận 7', 'address': '88 Đường số 7, KDC Tân Quy Đông',
      'district': 'Quận 7', 'city': 'TP. Hồ Chí Minh', 'status': 'ACTIVE', 'total_rooms_count': 3},
  ],
  '/api/rooms/': [
    {'id': 9, 'code': 'NT002-301', 'property': 2, 'property_name': 'Căn hộ Mini Happy House - Quận 7',
      'room_number': 'Căn 301', 'floor': 3, 'area': 20, 'rent_price': 3500000, 'max_occupants': 2,
      'current_occupants': 1, 'status': 'OCCUPIED'},
    {'id': 10, 'code': 'NT002-302', 'property': 2, 'property_name': 'Căn hộ Mini Happy House - Quận 7',
      'room_number': 'Căn 302', 'floor': 3, 'area': 25, 'rent_price': 4200000, 'max_occupants': 3,
      'current_occupants': 0, 'status': 'AVAILABLE'},
  ],
  '/api/tenants/': [
    {'id': 1, 'full_name': 'Trần Thị Mai Hương Nguyễn', 'phone_number': '0912345678', 'email': 'mai.huong@example.com',
      'status': 'ACTIVE', 'room_id': 9, 'user_id': 3, 'landlord_id': 2, 'identity_card': '079123456789'},
  ],
  '/api/contracts/': [
    {'id': 1, 'contract_number': 'HD-SEED-002', 'status': 'ACTIVE', 'room_id': 9, 'tenant_id': 1,
      'start_date': '2026-01-01', 'end_date': '2026-12-31', 'rent_price': 3500000, 'deposit': 3500000},
  ],
  '/api/billing/invoices/': [
    {'id': 1, 'invoice_code': 'HDN-SEED-002', 'status': 'UNPAID', 'total_amount': 4329000, 'billing_month': 11,
      'billing_year': 2026, 'room_id': 9, 'tenant_id': 1, 'room_fee': 3500000},
  ],
  '/api/users/': [
    {'id': 1, 'username': 'admin', 'role': 'ADMIN', 'first_name': 'Hệ Thống', 'last_name': 'Admin',
      'email': 'admin@nhatro.vn', 'is_active': true},
    {'id': 3, 'username': 'khach1', 'role': 'TENANT', 'first_name': 'Trần Thị', 'last_name': 'Mai',
      'email': 'khach1@gmail.com', 'is_active': true},
  ],
  '/api/dashboard/summary/': {
    'complete': true, 'errors': [], 'total_properties': 1, 'total_rooms': 2, 'occupied_rooms': 1,
    'available_rooms': 1, 'maintenance_rooms': 0, 'occupancy_rate_percent': 50, 'total_tenants': 1,
    'active_tenants': 1, 'active_contracts': 1, 'unpaid_invoices': 1, 'unpaid_amount': 4329000,
    'estimated_monthly_revenue': 3500000,
  },
  '/api/system/health/': {
    'gateway': {'status': 'UP', 'port': 8000}, 'overall_status': 'UP',
    'services': [
      for (final (k, n, p) in [('identity', 'Identity Service', 8001), ('property', 'Property & Maintenance', 8002),
        ('tenant', 'Tenant Service', 8003), ('contract', 'Contract Service', 8004),
        ('billing', 'Billing & Notification', 8005)])
        {'key': k, 'name': n, 'port': p, 'status': 'UP', 'database': {'status': 'UP'}, 'response_time_ms': 3},
    ],
  },
};

void main() {
  const sizes = {
    'điện thoại 375': Size(375, 812),
    'máy tính bảng 800': Size(800, 1000),
    'tablet ngang 1024': Size(1024, 768),
    'laptop 1280': Size(1280, 800),
    'màn hình lớn 1920': Size(1920, 1080),
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient.resetForTest();
    ApiClient.httpClient = MockClient((req) async {
      if (req.method != 'GET') return _json({'id': 1}, 201);
      return _json(_data[req.url.path] ?? const []);
    });
    await ApiClient.saveSession(access: 'access', refresh: 'refresh');
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ApiClient.resetForTest();
  });

  testWidgets('Desktop 1440: không bảng nào phải cuộn ngang (mọi cột, kể cả THAO TÁC, đều thấy ngay)',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scrolling = <String>[];
    for (final role in ['ADMIN', 'LANDLORD', 'TENANT']) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(NhaTroManagerApp(authProvider: _RoleAuth(role), repository: AppDataRepository()));
      await tester.pumpAndSettle();
      for (final route in RoleAccess.allowedRoutes(role)) {
        GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
        await tester.pumpAndSettle();
        if (find.byKey(const Key('app_table_hscrollbar')).evaluate().isNotEmpty) scrolling.add('$role $route');
      }
    }
    expect(scrolling, isEmpty, reason: scrolling.join(', '));
  });

  for (final role in ['ADMIN', 'LANDLORD', 'TENANT']) {
    testWidgets('$role: mọi route không lỗi layout ở ${sizes.length} kích thước màn hình', (tester) async {
      final routes = RoleAccess.allowedRoutes(role).toList();
      final failures = <String>[];
      var where = '';
      final originalOnError = FlutterError.onError;
      // Ghi lại MỌI lỗi layout kèm chuỗi widget tạo ra nó (để biết chính xác chỗ cần sửa).
      FlutterError.onError = (details) {
        final info = [
          for (final node in details.informationCollector?.call() ?? const <DiagnosticsNode>[])
            node.toStringDeep(),
        ].join(' ');
        final creator = (RegExp(r'creator: ([\s\S]*?)parentData').firstMatch(info)?.group(1) ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .split(' ← ')
            .take(9)
            .join(' ← ');
        failures.add('$where: ${details.exceptionAsString().split('\n').first} | $creator');
      };
      for (final MapEntry(key: label, value: size) in sizes.entries) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const SizedBox());
        where = '$label / (khởi động)';
        await tester.pumpWidget(NhaTroManagerApp(authProvider: _RoleAuth(role), repository: AppDataRepository()));
        await tester.pumpAndSettle();
        for (final route in routes) {
          where = '$label $route';
          GoRouter.of(tester.element(find.byType(Scaffold).first)).go(route);
          await tester.pumpAndSettle();
        }
      }
      FlutterError.onError = originalOnError;
      final unique = failures.toSet().toList();
      expect(unique, isEmpty, reason: unique.join('\n'));
    });
  }
}
