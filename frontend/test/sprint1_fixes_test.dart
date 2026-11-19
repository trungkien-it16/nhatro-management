// Nghiệm thu Sprint 1 — các lỗi tồn đọng sau Giai đoạn 3:
// biểu đồ phòng khớp tổng số phòng, nhãn Gateway lấy từ cấu hình, nút lưu đơn giá không báo thành công giả,
// bảng rộng có thanh cuộn ngang, TENANT không thấy ô tìm kiếm chết trên top bar.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/core/constants/api_constants.dart';
import 'package:nhatro_frontend/core/widgets/app_button.dart';
import 'package:nhatro_frontend/core/widgets/app_table.dart';
import 'package:nhatro_frontend/core/widgets/app_top_bar.dart';
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

void main() {
  late AppDataRepository repo;
  Map<String, dynamic> summary = {};

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient.resetForTest();
    summary = {'complete': true, 'errors': []};
    ApiClient.httpClient = MockClient((req) async {
      final path = req.url.path;
      if (path == '/api/system/health/') {
        return _json({'gateway': {'status': 'UP', 'port': 8000}, 'overall_status': 'UP', 'services': []});
      }
      if (path == '/api/dashboard/summary/') return _json(summary);
      if (req.method != 'GET') return _json({'id': 1}, 201);
      return _json(const []);
    });
    await ApiClient.saveSession(access: 'access', refresh: 'refresh');
    repo = AppDataRepository();
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ApiClient.resetForTest();
  });

  Future<void> openApp(WidgetTester tester, String location, {required String role, Size size = const Size(1440, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(NhaTroManagerApp(authProvider: _RoleAuth(role), repository: repo));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
    await tester.pumpAndSettle();
  }

  testWidgets('Biểu đồ trạng thái phòng có cùng tổng với thẻ "Tổng số phòng" (gồm phòng đặt trước / ngưng)',
      (tester) async {
    summary = {
      'complete': true,
      'errors': [],
      'total_rooms': 9,
      'occupied_rooms': 4,
      'available_rooms': 3,
      'maintenance_rooms': 1,
      'reserved_rooms': 1,
      'inactive_rooms': 0,
      'occupancy_rate_percent': 44.4,
    };
    await openApp(tester, '/', role: 'LANDLORD');
    final total = tester.widget<Text>(find.byKey(const Key('room_ratio_total')));
    expect(total.data, '9');
    expect(find.text('Đặt trước / ngưng khai thác'), findsOneWidget);
    expect(find.text('1 phòng (11%)'), findsWidgets);
  });

  testWidgets('Biểu đồ không thêm mục "khác" khi mọi phòng thuộc 3 trạng thái chính', (tester) async {
    summary = {
      'complete': true,
      'errors': [],
      'total_rooms': 8,
      'occupied_rooms': 4,
      'available_rooms': 3,
      'maintenance_rooms': 1,
    };
    await openApp(tester, '/', role: 'ADMIN');
    expect(tester.widget<Text>(find.byKey(const Key('room_ratio_total'))).data, '8');
    expect(find.text('Đặt trước / ngưng khai thác'), findsNothing);
  });

  test('Nhãn Gateway lấy từ API_GATEWAY_URL (mặc định http://127.0.0.1:8000 -> ":8000")', () {
    expect(ApiConstants.gatewayUrl, 'http://127.0.0.1:8000');
    expect(ApiConstants.gatewayLabel, ':8000');
  });

  testWidgets('Top bar: nhãn Gateway theo cấu hình; TENANT không có ô tìm kiếm nhanh', (tester) async {
    await openApp(tester, '/', role: 'LANDLORD');
    final bar = find.byType(AppTopBar);
    expect(find.descendant(of: bar, matching: find.textContaining('Gateway ${ApiConstants.gatewayLabel} →')),
        findsOneWidget);
    expect(find.descendant(of: bar, matching: find.byType(TextField)), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await openApp(tester, '/', role: 'TENANT');
    expect(find.descendant(of: find.byType(AppTopBar), matching: find.byType(TextField)), findsNothing);
    expect(find.text('Tìm nhanh phòng, người thuê...'), findsNothing);
  });

  testWidgets('Cài đặt: "Lưu cấu hình" đơn giá bị vô hiệu hóa, không báo lưu thành công giả', (tester) async {
    await openApp(tester, '/settings', role: 'LANDLORD');
    final save = find.byKey(const Key('settings_rate_save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(save).onPressed, isNull);
    expect(find.byKey(const Key('settings_rate_not_saved_note')), findsOneWidget);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã lưu cấu hình'), findsNothing);
  });

  testWidgets('Desktop 1440: bảng Người thuê hiện đủ cột THAO TÁC, không cần cuộn ngang', (tester) async {
    ApiClient.httpClient = MockClient((req) async {
      final path = req.url.path;
      if (path == '/api/system/health/') {
        return _json({'gateway': {'status': 'UP', 'port': 8000}, 'overall_status': 'UP', 'services': []});
      }
      if (path == '/api/tenants/') {
        return _json([
          {'id': 1, 'full_name': 'Trần Thị Mai', 'phone_number': '0912345678', 'status': 'ACTIVE', 'room_id': 9},
        ]);
      }
      if (path == '/api/dashboard/summary/') return _json(summary);
      return _json(const []);
    });
    await openApp(tester, '/tenants', role: 'LANDLORD', size: const Size(1440, 900));
    final header = find.text('THAO TÁC');
    expect(header, findsOneWidget);
    expect(tester.getRect(header).right, lessThanOrEqualTo(1440));
    expect(find.byKey(const Key('app_table_hscrollbar')), findsNothing);
    expect(find.byTooltip('Chỉnh sửa'), findsOneWidget);
  });

  testWidgets('Trang "Không có quyền": nói đúng vai trò được phép theo từng URL', (tester) async {
    await openApp(tester, '/accounts', role: 'LANDLORD');
    expect(find.textContaining('chỉ dành cho Quản trị viên (ADMIN)'), findsOneWidget);
    expect(find.textContaining('Nhân viên'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await openApp(tester, '/tenants', role: 'TENANT');
    expect(find.textContaining('chỉ dành cho Quản trị viên hoặc Chủ nhà trọ'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await openApp(tester, '/my-bills', role: 'ADMIN');
    expect(find.textContaining('dành cho Khách thuê'), findsOneWidget);
  });

  Widget table(double width) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: AppTable<String>(
              columns: [
                AppTableColumn<String>(label: 'A', flex: 2, cellBuilder: (s) => Text(s)),
                AppTableColumn<String>(label: 'THAO TÁC', width: 300, cellBuilder: (s) => const Text('Sửa')),
              ],
              items: const ['x', 'y'],
            ),
          ),
        ),
      );

  testWidgets('Bảng rộng hơn màn hình: cuộn ngang với thanh cuộn luôn hiển thị, cột cuối vẫn truy cập được',
      (tester) async {
    await tester.pumpWidget(table(400));
    expect(find.byKey(const Key('app_table_hscrollbar')), findsOneWidget);
    await tester.drag(find.text('x'), const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('THAO TÁC')).right, lessThanOrEqualTo(400));

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(table(1400));
    expect(find.byKey(const Key('app_table_hscrollbar')), findsNothing);
  });
}
