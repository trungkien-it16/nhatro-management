// Giai đoạn 3 — Phân quyền giao diện theo vai trò: route chuẩn, redirect route cũ, menu theo vai trò,
// URL trực tiếp bị cấm, chưa đăng nhập, token hết hạn.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/core/auth/role_access.dart';
import 'package:nhatro_frontend/core/constants/api_constants.dart';
import 'package:nhatro_frontend/core/widgets/app_sidebar.dart';
import 'package:nhatro_frontend/features/account/presentation/accounts_page.dart';
import 'package:nhatro_frontend/features/auth/presentation/forbidden_page.dart';
import 'package:nhatro_frontend/features/auth/presentation/login_page.dart';
import 'package:nhatro_frontend/features/billing/presentation/billing_page.dart';
import 'package:nhatro_frontend/features/contract/presentation/contract_page.dart';
import 'package:nhatro_frontend/features/dashboard/presentation/dashboard_page.dart';
import 'package:nhatro_frontend/features/maintenance/presentation/maintenance_page.dart';
import 'package:nhatro_frontend/features/notification/presentation/notification_page.dart';
import 'package:nhatro_frontend/features/notification/presentation/settings_page.dart';
import 'package:nhatro_frontend/features/property/presentation/property_page.dart';
import 'package:nhatro_frontend/features/room/presentation/room_create_page.dart';
import 'package:nhatro_frontend/features/room/presentation/room_detail_page.dart';
import 'package:nhatro_frontend/features/room/presentation/room_page.dart';
import 'package:nhatro_frontend/features/system/presentation/system_page.dart';
import 'package:nhatro_frontend/features/tenant/presentation/tenant_page.dart';
import 'package:nhatro_frontend/features/tenant_portal/presentation/my_bills_page.dart';
import 'package:nhatro_frontend/features/tenant_portal/presentation/my_contracts_page.dart';
import 'package:nhatro_frontend/features/tenant_portal/presentation/my_profile_page.dart';
import 'package:nhatro_frontend/features/tenant_portal/presentation/my_room_page.dart';
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

/// AuthProvider có vai trò cố định; login() mô phỏng đăng nhập thành công với vai trò đó.
class _RoleAuth extends AuthProvider {
  AuthStatus _s;
  final String _role;
  _RoleAuth(this._role, [this._s = AuthStatus.authenticated]);

  @override
  AuthStatus get status => _s;
  @override
  bool get isAuthenticated => _s == AuthStatus.authenticated;
  @override
  String get role => _s == AuthStatus.authenticated ? _role : '';
  @override
  String get displayName => 'Test $_role';

  @override
  Future<List<Map<String, dynamic>>> fetchUsers() async => const [];

  @override
  Future<bool> login(String username, String password) async {
    _s = AuthStatus.authenticated;
    notifyListeners();
    return true;
  }

  @override
  Future<void> logout() async {
    _s = AuthStatus.unauthenticated;
    notifyListeners();
  }
}

class _OfflineRepo extends AppDataRepository {
  @override
  Future<void> syncWithBackend() async {}
}

/// Trang quản lý dữ liệu (ADMIN + LANDLORD).
const _managerRoutes = <String, Type>{
  '/properties': PropertyPage,
  '/rooms': RoomPage,
  '/rooms/create': RoomCreatePage,
  '/rooms/5': RoomDetailPage,
  '/tenants': TenantPage,
  '/contracts': ContractPage,
  '/bills': BillingPage,
};

/// Trang chỉ ADMIN.
const _adminRoutes = <String, Type>{
  '/accounts': AccountsPage,
  '/system': SystemPage,
};

/// Trang chỉ TENANT (dữ liệu của chính mình).
const _tenantRoutes = <String, Type>{
  '/my-room': MyRoomPage,
  '/my-profile': MyProfilePage,
  '/my-contracts': MyContractsPage,
  '/my-bills': MyBillsPage,
};

const _adminMenu = [
  'Dashboard', 'Tài khoản', 'Nhà trọ', 'Phòng', 'Khách thuê', 'Hợp đồng', 'Hóa đơn', 'Thông báo',
  'Quản trị hệ thống', 'Cài đặt',
];
const _landlordMenu = [
  'Dashboard', 'Nhà trọ', 'Phòng', 'Khách thuê', 'Hợp đồng', 'Hóa đơn', 'Thông báo', 'Cài đặt',
];
const _tenantMenu = [
  'Dashboard cá nhân', 'Phòng đang thuê', 'Hồ sơ của tôi', 'Hợp đồng của tôi', 'Hóa đơn của tôi',
  'Thông báo', 'Cài đặt',
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiClient.resetForTest();
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ApiClient.onSessionExpired = null;
    ApiClient.resetForTest();
  });

  void screen(WidgetTester tester, [Size size = const Size(1440, 900)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpApp(WidgetTester tester, AuthProvider auth) async {
    // Gỡ app cũ (nếu có) để State mới nhận đúng AuthProvider của vai trò mới.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(NhaTroManagerApp(authProvider: auth, repository: _OfflineRepo()));
    await tester.pumpAndSettle();
  }

  /// Mô phỏng gõ thẳng URL vào thanh địa chỉ (router chạy lại redirect).
  Future<void> goTo(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
    await tester.pumpAndSettle();
  }

  String currentPath(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path;

  Finder inSidebar(String text) => find.descendant(of: find.byType(AppSidebar), matching: find.text(text));

  List<String?> sidebarLabels(WidgetTester tester) => tester
      .widgetList<Text>(find.descendant(of: find.byType(ListView), matching: find.byType(Text)))
      .map((t) => t.data)
      .where((t) => t != null && !t.startsWith(':'))
      .toList();

  group('RoleAccess (ma trận quyền)', () {
    test('ADMIN mở được mọi trang quản lý + Tài khoản + Quản trị hệ thống, không mở trang /my-*', () {
      for (final path in [..._managerRoutes.keys, ..._adminRoutes.keys, '/', '/notifications', '/settings']) {
        expect(RoleAccess.canAccess('ADMIN', path), isTrue, reason: path);
      }
      for (final path in _tenantRoutes.keys) {
        expect(RoleAccess.canAccess('ADMIN', path), isFalse, reason: path);
      }
      expect(RoleAccess.homeFor('ADMIN'), '/');
    });

    test('LANDLORD: trang quản lý trong phạm vi; KHÔNG có Tài khoản / Quản trị hệ thống / /my-*', () {
      for (final path in [..._managerRoutes.keys, '/', '/notifications', '/settings']) {
        expect(RoleAccess.canAccess('LANDLORD', path), isTrue, reason: path);
      }
      for (final path in [..._adminRoutes.keys, ..._tenantRoutes.keys]) {
        expect(RoleAccess.canAccess('LANDLORD', path), isFalse, reason: path);
      }
      expect(RoleAccess.homeFor('LANDLORD'), '/');
    });

    test('TENANT, STAFF (legacy) và vai trò không xác định: chỉ Dashboard cá nhân + /my-* + chung', () {
      for (final role in ['TENANT', 'STAFF', '', null, 'admin', 'SUPERUSER']) {
        for (final path in [..._managerRoutes.keys, ..._adminRoutes.keys]) {
          expect(RoleAccess.canAccess(role, path), isFalse, reason: '$role -> $path');
        }
        for (final path in [..._tenantRoutes.keys, '/', '/notifications', '/settings']) {
          expect(RoleAccess.canAccess(role, path), isTrue, reason: '$role -> $path');
        }
        expect(RoleAccess.canAccess(role, '/propertiesX'), isFalse, reason: 'không khớp tiền tố lỏng');
        expect(RoleAccess.canAccess(role, '/trang-moi'), isFalse, reason: 'mặc định từ chối');
        expect(RoleAccess.homeFor(role), '/');
      }
    });

    test('Bảo trì: source giữ lại nhưng chưa mở cho vai trò nào (Sprint hiện tại)', () {
      for (final role in ['ADMIN', 'LANDLORD', 'TENANT', 'STAFF']) {
        expect(RoleAccess.canAccess(role, '/maintenance'), isFalse, reason: role);
        expect(RoleAccess.menuFor(role).any((m) => m.route == '/maintenance'), isFalse, reason: role);
      }
    });

    test('Route cũ được ánh xạ sang route chuẩn', () {
      expect(RoleAccess.legacyRedirects, {
        '/dashboard': '/',
        '/property': '/properties',
        '/tenant': '/tenants',
        '/contract': '/contracts',
        '/billing': '/bills',
      });
    });
  });

  testWidgets('ADMIN: menu đầy đủ theo thứ tự, mở trực tiếp mọi URL quản lý + ADMIN', (tester) async {
    screen(tester);
    await pumpApp(tester, _RoleAuth('ADMIN'));
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(currentPath(tester), '/');
    expect(sidebarLabels(tester), _adminMenu);
    for (final MapEntry(key: path, value: page) in {..._managerRoutes, ..._adminRoutes}.entries) {
      await goTo(tester, path);
      expect(find.byType(ForbiddenPage), findsNothing, reason: path);
      expect(find.byType(page), findsOneWidget, reason: path);
    }
    for (final path in _tenantRoutes.keys) {
      await goTo(tester, path);
      expect(find.byType(ForbiddenPage), findsOneWidget, reason: path);
    }
  });

  testWidgets('LANDLORD: không thấy Tài khoản / Quản trị hệ thống; URL ADMIN -> Không có quyền', (tester) async {
    screen(tester);
    await pumpApp(tester, _RoleAuth('LANDLORD'));
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(sidebarLabels(tester), _landlordMenu);
    expect(inSidebar('Tài khoản'), findsNothing);
    expect(inSidebar('Quản trị hệ thống'), findsNothing);
    expect(inSidebar('Bảo trì & sửa chữa'), findsNothing);
    for (final MapEntry(key: path, value: page) in _managerRoutes.entries) {
      await goTo(tester, path);
      expect(find.byType(page), findsOneWidget, reason: path);
    }
    for (final MapEntry(key: path, value: page) in {..._adminRoutes, ..._tenantRoutes}.entries) {
      await goTo(tester, path);
      expect(find.byType(page), findsNothing, reason: path);
      expect(find.byType(ForbiddenPage), findsOneWidget, reason: path);
    }
    // Cài đặt không còn chứa quản lý tài khoản toàn hệ thống / bảng service SOA.
    await goTo(tester, '/settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.textContaining('Danh sách tài khoản'), findsNothing);
    expect(find.text('Danh sách Microservices (Kiến trúc SOA)'), findsNothing);
  });

  testWidgets('TENANT: vào Dashboard cá nhân, menu chỉ có trang của mình', (tester) async {
    screen(tester);
    await pumpApp(tester, _RoleAuth('TENANT'));

    expect(currentPath(tester), '/');
    expect(find.byType(TenantDashboard), findsOneWidget);
    expect(sidebarLabels(tester), _tenantMenu);
    for (final MapEntry(key: path, value: page) in _tenantRoutes.entries) {
      await goTo(tester, path);
      expect(find.byType(page), findsOneWidget, reason: path);
    }
  });

  testWidgets('TENANT gõ thẳng URL trang quản lý / ADMIN -> trang "Không có quyền truy cập"', (tester) async {
    screen(tester);
    await pumpApp(tester, _RoleAuth('TENANT'));

    for (final MapEntry(key: path, value: page) in {..._managerRoutes, ..._adminRoutes, '/maintenance': MaintenancePage}.entries) {
      await goTo(tester, path);
      expect(find.byType(page), findsNothing, reason: path);
      expect(find.byType(ForbiddenPage), findsOneWidget, reason: path);
      expect(find.text('Không có quyền truy cập'), findsWidgets);
      expect(find.textContaining('"$path"'), findsOneWidget);
    }

    await tester.tap(find.text('Về trang chính'));
    await tester.pumpAndSettle();
    expect(find.byType(TenantDashboard), findsOneWidget);

    await goTo(tester, '/settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Đơn giá dịch vụ mặc định'), findsNothing, reason: 'cấu hình của chủ trọ');
  });

  testWidgets('Route cũ chuyển sang route chuẩn (không báo lỗi quyền)', (tester) async {
    screen(tester);
    await pumpApp(tester, _RoleAuth('LANDLORD'));
    for (final MapEntry(key: from, value: to) in RoleAccess.legacyRedirects.entries) {
      await goTo(tester, from);
      expect(currentPath(tester), to, reason: from);
      expect(find.byType(ForbiddenPage), findsNothing, reason: from);
    }
    // TENANT mở link cũ /dashboard -> Dashboard cá nhân (không còn bị đẩy sang trang không phù hợp).
    await pumpApp(tester, _RoleAuth('TENANT'));
    await goTo(tester, '/dashboard');
    expect(currentPath(tester), '/');
    expect(find.byType(TenantDashboard), findsOneWidget);
  });

  testWidgets('Bảo trì bị ẩn: mọi vai trò mở /maintenance đều bị chặn', (tester) async {
    screen(tester);
    for (final role in ['ADMIN', 'LANDLORD']) {
      await pumpApp(tester, _RoleAuth(role));
      await goTo(tester, '/maintenance');
      expect(find.byType(MaintenancePage), findsNothing, reason: role);
      expect(find.byType(ForbiddenPage), findsOneWidget, reason: role);
    }
  });

  testWidgets('TENANT đăng nhập từ màn Login -> về Dashboard cá nhân', (tester) async {
    screen(tester);
    await pumpApp(tester, _RoleAuth('TENANT', AuthStatus.unauthenticated));
    expect(find.byType(LoginPage), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'khach1');
    await tester.enterText(find.byKey(const Key('login_password')), 'x');
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();

    expect(currentPath(tester), '/');
    expect(find.byType(TenantDashboard), findsOneWidget);
    expect(find.byType(NotificationPage), findsNothing);
  });

  testWidgets('TENANT trên điện thoại: thanh điều hướng dưới chỉ có trang của mình', (tester) async {
    screen(tester, const Size(760, 1000)); // <768 = mobile
    await pumpApp(tester, _RoleAuth('TENANT'));
    final labels = find.descendant(of: find.byType(NavigationBar), matching: find.byType(Text));
    expect(tester.widgetList<Text>(labels).map((t) => t.data), ['Tổng quan', 'Phòng', 'Hóa đơn', 'Thông báo', 'Cài đặt']);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Hóa đơn')));
    await tester.pumpAndSettle();
    expect(find.byType(MyBillsPage), findsOneWidget);
  });

  testWidgets('LANDLORD trên điện thoại: thanh điều hướng dưới là trang quản lý', (tester) async {
    screen(tester, const Size(760, 1000));
    await pumpApp(tester, _RoleAuth('LANDLORD'));
    final labels = find.descendant(of: find.byType(NavigationBar), matching: find.byType(Text));
    expect(tester.widgetList<Text>(labels).map((t) => t.data), ['Tổng quan', 'Nhà trọ', 'Phòng', 'Khách thuê', 'Cài đặt']);
  });

  testWidgets('Chưa đăng nhập: mọi URL cần đăng nhập đều về màn Login', (tester) async {
    screen(tester);
    await pumpApp(tester, _RoleAuth('LANDLORD', AuthStatus.unauthenticated));
    for (final path in [
      ..._managerRoutes.keys, ..._adminRoutes.keys, ..._tenantRoutes.keys,
      '/notifications', '/settings', '/forbidden', '/', '/dashboard', '/property',
    ]) {
      await goTo(tester, path);
      expect(find.byType(LoginPage), findsOneWidget, reason: path);
      expect(find.byType(AppSidebar), findsNothing, reason: path);
    }
  });

  group('Phiên thật (AuthProvider + /auth/me/)', () {
    late bool expired;
    late String meRole;

    setUp(() {
      expired = false;
      meRole = 'TENANT';
      ApiClient.httpClient = MockClient((req) async {
        if (req.url.path == '/api/auth/refresh/') {
          return _json({'detail': 'Token is blacklisted', 'code': 'token_not_valid'}, 401);
        }
        if (expired) return _json({'detail': 'Given token not valid for any token type'}, 401);
        if (req.url.path == '/api/auth/me/') {
          return _json({'id': 7, 'username': 'khach1', 'role': meRole, 'full_name': 'Khách Test'});
        }
        return _json([]);
      });
    });

    Future<AuthProvider> restored() async {
      await ApiClient.saveSession(
        access: 'access-ok',
        refresh: 'refresh-ok',
        user: {'username': 'khach1', 'role': 'LANDLORD'}, // bản lưu cũ: phải lấy role mới từ /auth/me/
      );
      final auth = AuthProvider();
      await auth.restoreSession();
      return auth;
    }

    testWidgets('Vai trò lấy từ Identity (/auth/me/), không tin bản lưu cục bộ', (tester) async {
      screen(tester);
      final auth = await restored();
      expect(auth.role, 'TENANT');
      await pumpApp(tester, auth);
      expect(find.byType(TenantDashboard), findsOneWidget);
      await goTo(tester, '/bills');
      expect(find.byType(ForbiddenPage), findsOneWidget);
    });

    testWidgets('Token hết hạn (refresh bị từ chối) -> về Login, không vào lại được trang nào', (tester) async {
      screen(tester);
      meRole = 'LANDLORD';
      final auth = await restored();
      await pumpApp(tester, auth);
      expect(find.byType(DashboardPage), findsOneWidget);

      expired = true;
      await expectLater(ApiClient.get(ApiConstants.notifications), throwsA(isA<ApiException>()));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại.'), findsOneWidget);
      expect(auth.role, '');
      expect(await ApiClient.getAccessToken(), isNull);

      await goTo(tester, '/properties');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(PropertyPage), findsNothing);
    });
  });
}
