// Chặng 5 – Bước 5 (E5.4): trạng thái giao diện của Tenant, Contract, Billing, Notification,
// Maintenance và Maintenance History. Dùng AppDataRepository THẬT + Gateway giả (MockClient).
// Mỗi module chạy cùng một bộ trường hợp: đang tải, có dữ liệu, rỗng thật, lỗi 500/503, lỗi mạng,
// giữ dữ liệu cũ, thử lại (không lặp request), 403, đổi tài khoản.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/features/maintenance/presentation/maintenance_page.dart';
import 'package:nhatro_frontend/main.dart';
import 'package:nhatro_frontend/providers/auth_provider.dart';
import 'package:nhatro_frontend/shared/services/api_client.dart';
import 'package:nhatro_frontend/shared/services/app_data_repository.dart';
import 'package:provider/provider.dart';
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
  String get displayName => 'Người dùng Test';
  @override
  String get roleDisplay => _role;
}

/// Một module cần kiểm tra: route trang, endpoint Gateway, tiền tố key trạng thái và dữ liệu mẫu theo tài khoản.
class _Module {
  const _Module({
    required this.name,
    required this.route,
    required this.apiPath,
    required this.keyPrefix,
    required this.row,
    required this.label,
  });
  final String name;
  final String route;
  final String apiPath;
  final String keyPrefix;

  /// Bản ghi backend của tài khoản [acc] ("A" hoặc "B").
  final Map<String, dynamic> Function(String acc) row;

  /// Chữ hiển thị trên trang cho bản ghi của tài khoản [acc].
  final String Function(String acc) label;
}

final _modules = <_Module>[
  _Module(
    name: 'Tenant',
    route: '/tenants',
    apiPath: '/api/tenants/',
    keyPrefix: 'tenant_list',
    row: (a) => {'id': 1, 'full_name': 'Khách $a', 'phone_number': '090000000$a', 'status': 'ACTIVE'},
    label: (a) => 'Khách $a',
  ),
  _Module(
    name: 'Contract',
    route: '/contracts',
    apiPath: '/api/contracts/',
    keyPrefix: 'contract_list',
    row: (a) => {'id': 1, 'contract_number': 'HD-$a', 'status': 'ACTIVE', 'rental_price': 3000000},
    label: (a) => 'HD-$a',
  ),
  _Module(
    name: 'Billing',
    route: '/bills',
    apiPath: '/api/billing/invoices/',
    keyPrefix: 'invoice_list',
    row: (a) => {
      'id': 1,
      'invoice_code': 'HDN-$a',
      'status': 'UNPAID',
      'total_amount': 4500000,
      'due_date': '2026-11-25',
      'billing_month': 11,
      'billing_year': 2026,
    },
    label: (a) => 'HDN-$a',
  ),
  _Module(
    name: 'Notification',
    route: '/notifications',
    apiPath: '/api/notifications/',
    keyPrefix: 'notification_list',
    row: (a) => {'id': 1, 'title': 'Thông báo $a', 'content': 'Nội dung $a', 'is_read': false},
    label: (a) => 'Thông báo $a',
  ),
  _Module(
    name: 'Maintenance',
    route: '/maintenance',
    apiPath: '/api/maintenance/',
    keyPrefix: 'maintenance_list',
    row: (a) => {'id': 1, 'code': 'BT-$a', 'title': 'Sửa vòi $a', 'status': 'PENDING', 'room': 10},
    label: (a) => 'BT-$a',
  ),
  _Module(
    name: 'Maintenance History',
    route: '/maintenance',
    apiPath: '/api/maintenance-history/',
    keyPrefix: 'maintenance_history',
    row: (a) => {'id': 1, 'request_code': 'LS-$a', 'action': 'CREATED', 'room_number': 'P1'},
    label: (a) => 'LS-$a',
  ),
];

/// Gateway giả: dữ liệu trả theo access token (tài khoản A / B); có thể thay phản hồi, giữ request, đếm request.
class _Gateway {
  final Map<String, List<Map<String, dynamic>>> Function(String acc) dataFor;
  _Gateway(this.dataFor);

  final Map<String, FutureOr<http.Response> Function(http.Request req)> overrides = {};
  final requests = <http.Request>[];
  Completer<void>? hold;

  int count(String method, String path) =>
      requests.where((r) => r.method == method && r.url.path == path).length;

  MockClient get client => MockClient((req) async {
        if (hold != null) await hold!.future;
        requests.add(req);
        final path = req.url.path;
        final o = overrides['${req.method} $path'];
        if (o != null) return o(req);
        if (path == '/api/system/health/') {
          return _json({'gateway': {'status': 'UP', 'port': 8000}, 'overall_status': 'UP', 'services': []});
        }
        if (path == '/api/dashboard/summary/') return _json({'complete': true, 'errors': []});
        final auth = req.headers['Authorization'] ?? req.headers['authorization'] ?? '';
        final acc = auth.endsWith('access-B') ? 'B' : 'A';
        return _json(dataFor(acc)[path] ?? const []);
      });
}

void main() {
  late _Gateway gw;
  late AppDataRepository repo;
  late Map<String, List<Map<String, dynamic>>> Function(String acc) data;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient.resetForTest();
    data = (acc) => {for (final m in _modules) m.apiPath: [m.row(acc)]};
    gw = _Gateway((acc) => data(acc));
    ApiClient.httpClient = gw.client;
    await ApiClient.saveSession(access: 'access-A', refresh: 'refresh-A');
    repo = AppDataRepository();
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ApiClient.resetForTest();
  });

  Finder key(String k) => find.byKey(Key(k));

  Future<void> openApp(WidgetTester tester, String location, {String role = 'LANDLORD', bool settle = true}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (location == '/maintenance') {
      // Trang Bảo trì đã ẩn khỏi menu/route ở Sprint hiện tại (RoleAccess chặn mọi vai trò) nhưng
      // source vẫn giữ cho Sprint sau -> kiểm thử trực tiếp widget để không làm hỏng mã nguồn.
      final auth = _RoleAuth(role);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<AppDataRepository>.value(value: repo),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: SingleChildScrollView(child: MaintenancePage())),
            ),
          ]),
        ),
      ));
      unawaited(repo.syncWithBackend());
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      }
      return;
    }
    await tester.pumpWidget(NhaTroManagerApp(authProvider: _RoleAuth(role), repository: repo));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  for (final m in _modules) {
    final p = m.keyPrefix;
    group(m.name, () {
      testWidgets('1. Đang tải: chỉ báo tải, chưa kết luận rỗng', (tester) async {
        gw.hold = Completer<void>();
        await openApp(tester, m.route, settle: false);

        expect(key('${p}_loading'), findsOneWidget);
        expect(key('${p}_empty'), findsNothing);

        gw.hold!.complete();
        await tester.pumpAndSettle();
        expect(key('${p}_loading'), findsNothing);
        expect(find.text(m.label('A')), findsWidgets);
      });

      testWidgets('2. Có dữ liệu: hiển thị đúng dữ liệu backend', (tester) async {
        await openApp(tester, m.route);
        expect(find.text(m.label('A')), findsWidgets);
        for (final s in ['loading', 'error', 'forbidden', 'empty', 'stale', 'not_loaded']) {
          expect(key('${p}_$s'), findsNothing, reason: s);
        }
      });

      testWidgets('3. Rỗng thật: chỉ khi backend trả danh sách rỗng', (tester) async {
        final base = data;
        data = (acc) => {...base(acc), m.apiPath: <Map<String, dynamic>>[]};
        await openApp(tester, m.route);
        expect(key('${p}_empty'), findsOneWidget);
        expect(key('${p}_error'), findsNothing);
      });

      testWidgets('4. Service lỗi 503: báo lỗi + Thử lại, không hiển thị rỗng', (tester) async {
        gw.overrides['GET ${m.apiPath}'] = (_) => _json({'error': '${m.name} Service DOWN'}, 503);
        await openApp(tester, m.route);

        expect(repo.isBackendConnected, isTrue, reason: 'chỉ một service lỗi, Gateway vẫn chạy');
        expect(key('${p}_error'), findsOneWidget);
        expect(find.textContaining('${m.name} Service DOWN'), findsOneWidget);
        expect(key('${p}_empty'), findsNothing);
      });

      testWidgets('4b. Service lỗi 500: báo lỗi, không hiển thị rỗng', (tester) async {
        gw.overrides['GET ${m.apiPath}'] = (_) => _json({'detail': 'Lỗi máy chủ'}, 500);
        await openApp(tester, m.route);
        expect(key('${p}_error'), findsOneWidget);
        expect(key('${p}_empty'), findsNothing);
      });

      testWidgets('5. Lỗi mạng: báo không kết nối được, không hiển thị rỗng', (tester) async {
        gw.overrides['GET ${m.apiPath}'] = (_) => throw http.ClientException('Connection refused');
        await openApp(tester, m.route);

        expect(key('${p}_error'), findsOneWidget);
        expect(find.textContaining('Không kết nối được tới API Gateway'), findsOneWidget);
        expect(key('${p}_empty'), findsNothing);
      });

      testWidgets('6. Đồng bộ lại thất bại: giữ dữ liệu cũ kèm cảnh báo', (tester) async {
        await openApp(tester, m.route);
        gw.overrides['GET ${m.apiPath}'] = (_) => _json({'error': 'Timeout'}, 504);
        await repo.syncWithBackend();
        await tester.pumpAndSettle();

        expect(find.text(m.label('A')), findsWidgets);
        expect(key('${p}_stale'), findsOneWidget);
        expect(key('${p}_error'), findsNothing);
        expect(key('${p}_empty'), findsNothing);
      });

      testWidgets('7. Thử lại thành công; mỗi lần bấm chỉ một request, không lặp', (tester) async {
        gw.overrides['GET ${m.apiPath}'] = (_) => _json({'error': 'DOWN'}, 503);
        await openApp(tester, m.route);
        expect(key('${p}_error'), findsOneWidget);

        gw.overrides.remove('GET ${m.apiPath}');
        final before = gw.count('GET', m.apiPath);
        await tapVisible(tester, find.descendant(of: key('${p}_error'), matching: find.text('Thử lại')));

        expect(find.text(m.label('A')), findsWidgets);
        expect(key('${p}_error'), findsNothing);
        expect(gw.count('GET', m.apiPath), before + 1);

        // Không có vòng lặp tự gọi lại.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(gw.count('GET', m.apiPath), before + 1);
      });

      testWidgets('8. 403: báo không có quyền, phân biệt với lỗi hệ thống và rỗng', (tester) async {
        gw.overrides['GET ${m.apiPath}'] = (_) => _json({'detail': 'Bạn không có quyền.'}, 403);
        await openApp(tester, m.route);

        expect(key('${p}_forbidden'), findsOneWidget);
        expect(key('${p}_error'), findsNothing);
        expect(key('${p}_empty'), findsNothing);
        expect(find.text(m.label('A')), findsNothing);
      });

      testWidgets('9. Đổi tài khoản: không còn dữ liệu của tài khoản trước', (tester) async {
        await openApp(tester, m.route);
        expect(find.text(m.label('A')), findsWidgets);

        repo.resetAfterLogout();
        await ApiClient.saveSession(access: 'access-B', refresh: 'refresh-B');
        await repo.syncWithBackend();
        await tester.pumpAndSettle();

        expect(find.text(m.label('A')), findsNothing);
        expect(find.text(m.label('B')), findsWidgets);
      });
    });
  }

  // ------------------------------------------------------------ bổ sung
  group('Bổ sung', () {
    testWidgets('Rỗng do bộ lọc khác rỗng thật (Tenant)', (tester) async {
      await openApp(tester, '/tenants');
      await tester.enterText(find.byType(TextField).last, 'không-tồn-tại');
      await tester.pumpAndSettle();
      expect(key('tenant_list_no_match'), findsOneWidget);
      expect(key('tenant_list_empty'), findsNothing);
    });

    testWidgets('Form người thuê: Room Service lỗi thì báo rõ, không âm thầm bỏ ô chọn phòng', (tester) async {
      gw.overrides['GET /api/rooms/'] = (_) => _json({'error': 'Room DOWN'}, 503);
      await openApp(tester, '/tenants');
      await tapVisible(tester, find.text('+ Thêm người thuê').first);

      expect(key('tenant_form_rooms_status'), findsOneWidget);
      expect(find.textContaining('Không tải được danh sách phòng: Room DOWN'), findsOneWidget);
    });

    testWidgets('Form người thuê: thật sự chưa có phòng thì nói đúng như vậy', (tester) async {
      await openApp(tester, '/tenants');
      await tapVisible(tester, find.text('+ Thêm người thuê').first);
      expect(find.text('Hệ thống chưa có phòng nào để gán.'), findsOneWidget);
    });

    testWidgets('Lịch sử người thuê: mở ngay với trạng thái tải, rồi hiện dữ liệu', (tester) async {
      final gate = Completer<void>();
      gw.overrides['GET /api/tenants/1/history/'] = (_) async {
        await gate.future;
        return _json([
          {'id': 1, 'move_in_date': '2026-01-01', 'note': 'Vào ở'},
        ]);
      };
      await openApp(tester, '/tenants');
      await tester.ensureVisible(find.byTooltip('Lịch sử cư trú & Hồ sơ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lịch sử cư trú & Hồ sơ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Lịch sử cư trú: Khách A'), findsOneWidget, reason: 'hộp thoại mở ngay');
      expect(key('history_loading'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(key('history_loading'), findsNothing);
      expect(find.textContaining('Vào ở: 2026-01-01'), findsOneWidget);
    });

    testWidgets('Lịch sử người thuê: lỗi có Thử lại; 403 báo không có quyền', (tester) async {
      gw.overrides['GET /api/tenants/1/history/'] = (_) => _json({'error': 'Tenant DOWN'}, 503);
      await openApp(tester, '/tenants');
      await tapVisible(tester, find.byTooltip('Lịch sử cư trú & Hồ sơ'));

      expect(key('history_error'), findsOneWidget);
      expect(find.text('Chưa có bản ghi lịch sử thuê phòng.'), findsNothing);

      gw.overrides['GET /api/tenants/1/history/'] = (_) => _json({'detail': 'Không có quyền.'}, 403);
      await tapVisible(tester, find.descendant(of: key('history_error'), matching: find.text('Thử lại')));
      expect(key('history_forbidden'), findsOneWidget);
      expect(key('history_error'), findsNothing);
    });

    testWidgets('Lịch sử hợp đồng: mở ngay, lỗi có Thử lại, phục hồi hiển thị sự kiện', (tester) async {
      final gate = Completer<void>();
      var fail = true;
      gw.overrides['GET /api/contracts/1/history/'] = (_) async {
        await gate.future;
        if (fail) return _json({'error': 'Contract DOWN'}, 503);
        return _json([
          {'id': 1, 'event_type': 'CREATED', 'event_type_display': 'Tạo hợp đồng', 'new_end_date': '2027-01-01'},
        ]);
      };
      await openApp(tester, '/contracts');
      await tester.ensureVisible(find.byTooltip('Lịch sử hợp đồng').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lịch sử hợp đồng').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Lịch sử hợp đồng: HD-A'), findsOneWidget, reason: 'hộp thoại mở ngay');
      expect(key('history_loading'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(key('history_error'), findsOneWidget);
      expect(find.text('Chưa có sự kiện nào.'), findsNothing, reason: 'lỗi không phải rỗng');

      fail = false;
      await tapVisible(tester, find.descendant(of: key('history_error'), matching: find.text('Thử lại')));
      expect(find.text('Tạo hợp đồng'), findsOneWidget);
    });

    testWidgets('Lịch sử hợp đồng 403: báo không có quyền', (tester) async {
      gw.overrides['GET /api/contracts/1/history/'] = (_) => _json({'detail': 'Không có quyền.'}, 403);
      await openApp(tester, '/contracts');
      await tapVisible(tester, find.byTooltip('Lịch sử hợp đồng').first);
      expect(key('history_forbidden'), findsOneWidget);
      expect(key('history_error'), findsNothing);
    });

    testWidgets('TENANT: dữ liệu quản lý bị backend từ chối không được giữ / hiển thị', (tester) async {
      for (final path in ['/api/tenants/', '/api/contracts/', '/api/billing/invoices/', '/api/maintenance/']) {
        gw.overrides['GET $path'] = (_) => _json({'detail': 'Bạn không có quyền.'}, 403);
      }
      await openApp(tester, '/notifications', role: 'TENANT');

      expect(repo.tenants, isEmpty);
      expect(repo.contracts, isEmpty);
      expect(repo.invoices, isEmpty);
      expect(repo.sectionState(DataSection.tenants).isForbidden, isTrue);
      expect(repo.sectionState(DataSection.contracts).isForbidden, isTrue);
      expect(find.text('Thông báo A'), findsOneWidget, reason: 'thông báo của chính TENANT vẫn hiển thị');
    });
  });
}
