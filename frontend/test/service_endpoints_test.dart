// Sprint 1: nhấn vào từng service trên thẻ "Kiến trúc SOA" -> thông tin kết nối + API endpoint thực tế.
// Dùng AppDataRepository THẬT + Gateway giả (MockClient) trả đúng dạng GET /api/system/services/<key>/endpoints/.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/features/dashboard/presentation/dashboard_page.dart';
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

/// Sơ đồ SOA + catalog endpoint chỉ dành cho ADMIN (Giai đoạn 3).
class _RoleAuth extends AuthProvider {
  _RoleAuth([this._role = 'ADMIN']);
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

const _ports = {'identity': 8001, 'property': 8002, 'tenant': 8003, 'contract': 8004, 'billing': 8005};

Map<String, dynamic> _ep(String group, String method, String path, String description, int port) => {
      'group': group,
      'method': method,
      'path': path,
      'full_url': 'http://127.0.0.1:$port$path',
      'description': description,
    };

Map<String, dynamic> _catalog(String key, List<Map<String, dynamic>> endpoints, {String status = 'UP', String? error}) =>
    {
      'key': key,
      'name': '$key service',
      'port': _ports[key],
      'base_url': 'http://127.0.0.1:${_ports[key]}',
      'source': 'http://127.0.0.1:${_ports[key]}/api/schema/',
      'status': status,
      'endpoints': endpoints,
      'error': ?error,
    };

class _Gateway {
  final Map<String, FutureOr<http.Response> Function()> overrides = {};
  final List<String> requests = [];

  /// Header Authorization của từng request lấy catalog endpoint.
  final List<String?> catalogAuth = [];
  Map<String, String> health = {for (final k in _ports.keys) k: 'UP'};

  int count(String path) => requests.where((p) => p == path).length;

  MockClient get client => MockClient((req) async {
        final path = req.url.path;
        requests.add(path);
        if (path.startsWith('/api/system/services/')) {
          catalogAuth.add(req.headers['Authorization'] ?? req.headers['authorization']);
        }
        final o = overrides[path];
        if (o != null) return o();
        if (path == '/api/system/health/') {
          return _json({
            'gateway': {'status': 'UP', 'port': 8000},
            'overall_status': health.values.every((s) => s == 'UP') ? 'UP' : 'DEGRADED',
            'services': [
              for (final e in health.entries) {'key': e.key, 'name': e.key, 'port': _ports[e.key], 'status': e.value},
            ],
          });
        }
        if (path == '/api/system/services/tenant/endpoints/') {
          return _json(_catalog('tenant', [
            _ep('tenants', 'GET', '/api/tenants/', 'Danh sách', 8003),
            _ep('tenants', 'POST', '/api/tenants/', 'Tạo mới', 8003),
            _ep('tenants', 'DELETE', '/api/tenants/{id}/', 'Xóa', 8003),
            _ep('tenants', 'GET', '/api/tenants/{id}/history/', 'lịch sử thuê', 8003),
            _ep('health', 'GET', '/health/', 'GET /health/ — trạng thái thực tế của service đang chạy.', 8003),
          ]));
        }
        if (path == '/api/system/services/billing/endpoints/') {
          return _json(_catalog('billing', [
            _ep('billing', 'GET', '/api/billing/invoices/', 'Danh sách', 8005),
            _ep('billing', 'POST', '/api/billing/invoices/{id}/pay/', 'đánh dấu đã thanh toán', 8005),
            _ep('notifications', 'GET', '/api/notifications/', 'thông báo của tôi', 8005),
            _ep('notifications', 'POST', '/api/notifications/read-all/', 'đánh dấu tất cả đã đọc', 8005),
          ]));
        }
        if (path.startsWith('/api/system/services/')) {
          final key = path.split('/')[4];
          return _json(_catalog(key, [_ep('x', 'GET', '/api/$key/', 'Danh sách', _ports[key] ?? 0)]));
        }
        if (path == '/api/dashboard/summary/') return _json({'errors': [], 'complete': true});
        return _json([]);
      });
}

void main() {
  late _Gateway gw;
  late AppDataRepository repo;
  String? clipboard;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ApiClient.resetForTest();
    gw = _Gateway();
    ApiClient.httpClient = gw.client;
    await ApiClient.saveSession(access: 'access', refresh: 'refresh');
    repo = AppDataRepository();
    clipboard = null;
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ApiClient.resetForTest();
  });

  Future<void> pumpDashboard(WidgetTester tester, {String role = 'ADMIN'}) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(NhaTroManagerApp(authProvider: _RoleAuth(role), repository: repo));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardPage), findsOneWidget);
  }

  Future<void> openService(WidgetTester tester, String key, {bool settle = true}) async {
    final tile = find.byKey(Key('soa_service_$key'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Finder inDialog(Finder f) => find.descendant(of: find.byKey(const Key('service_endpoints_dialog')), matching: f);

  testWidgets('1. Nhấn Tenant: tên, trạng thái, Base URL, port và endpoint thật (method + mô tả + Full URL)',
      (tester) async {
    await pumpDashboard(tester);
    await openService(tester, 'tenant');

    expect(gw.count('/api/system/services/tenant/endpoints/'), 1);
    expect(inDialog(find.text('Tenant Service')), findsOneWidget);
    expect(tester.widget<Text>(inDialog(find.descendant(
            of: find.byKey(const Key('service_endpoints_status')), matching: find.byType(Text)))).data,
        'UP');
    expect(tester.widget<SelectableText>(find.byKey(const Key('service_endpoints_base_url'))).data,
        'http://127.0.0.1:8003');
    expect(tester.widget<Text>(find.byKey(const Key('service_endpoints_port'))).data, '8003');

    for (final (method, path, desc) in const [
      ('GET', '/api/tenants/', 'Danh sách'),
      ('POST', '/api/tenants/', 'Tạo mới'),
      ('DELETE', '/api/tenants/{id}/', 'Xóa'),
      ('GET', '/api/tenants/{id}/history/', 'lịch sử thuê'),
      ('GET', '/health/', 'GET /health/ — trạng thái thực tế của service đang chạy.'),
    ]) {
      final row = find.byKey(Key('endpoint_${method}_$path'));
      expect(row, findsOneWidget, reason: '$method $path');
      expect(find.descendant(of: row, matching: find.text(method)), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text(desc)), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('http://127.0.0.1:8003$path')), findsOneWidget);
    }
    expect(inDialog(find.textContaining('5 endpoint')), findsOneWidget);
  });

  testWidgets('2. Billing & Notification dùng chung :8005: hiển thị cả nhóm Billing và Notification', (tester) async {
    await pumpDashboard(tester);
    await openService(tester, 'billing');

    expect(find.byKey(const Key('service_endpoints_group_billing')), findsOneWidget);
    expect(find.byKey(const Key('service_endpoints_group_notifications')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('service_endpoints_group_notifications'))).data, 'Notification');
    expect(find.byKey(const Key('endpoint_GET_/api/notifications/')), findsOneWidget);
    expect(find.byKey(const Key('endpoint_POST_/api/billing/invoices/{id}/pay/')), findsOneWidget);
    expect(inDialog(find.text('http://127.0.0.1:8005/api/notifications/read-all/')), findsOneWidget);
  });

  testWidgets('3. Sao chép Full URL và Base URL vào clipboard', (tester) async {
    await pumpDashboard(tester);
    await openService(tester, 'tenant');

    final copyFull = find.byKey(const Key('copy_http://127.0.0.1:8003/api/tenants/{id}/history/'));
    await tester.tap(copyFull);
    await tester.pump();
    expect(clipboard, 'http://127.0.0.1:8003/api/tenants/{id}/history/');
    expect(find.descendant(of: copyFull, matching: find.byIcon(Icons.check_rounded)), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy_http://127.0.0.1:8003')));
    await tester.pump();
    expect(clipboard, 'http://127.0.0.1:8003');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('4. Đang tải: hộp thoại mở ngay với chỉ báo tải, chưa có endpoint', (tester) async {
    final hold = Completer<void>();
    gw.overrides['/api/system/services/contract/endpoints/'] = () async {
      await hold.future;
      return _json(_catalog('contract', [_ep('contracts', 'GET', '/api/contracts/', 'Danh sách', 8004)]));
    };
    await pumpDashboard(tester);
    await openService(tester, 'contract', settle: false);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('service_endpoints_loading')), findsOneWidget);
    expect(find.byKey(const Key('endpoint_GET_/api/contracts/')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('service_endpoints_port'))).data, '8004');

    hold.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('service_endpoints_loading')), findsNothing);
    expect(find.byKey(const Key('endpoint_GET_/api/contracts/')), findsOneWidget);
  });

  testWidgets('5. Service không hoạt động: DOWN + lý do, vẫn có URL/port, Thử lại chỉ gọi 1 lần rồi phục hồi',
      (tester) async {
    gw.health['tenant'] = 'DOWN';
    var down = true;
    gw.overrides['/api/system/services/tenant/endpoints/'] = () => down
        ? _json(_catalog('tenant', [], status: 'DOWN', error: 'Không kết nối được tới service.'))
        : _json(_catalog('tenant', [_ep('tenants', 'GET', '/api/tenants/', 'Danh sách', 8003)]));
    await pumpDashboard(tester);
    await openService(tester, 'tenant');

    expect(find.byKey(const Key('service_endpoints_down')), findsOneWidget);
    expect(inDialog(find.textContaining('Không kết nối được tới service.')), findsOneWidget);
    expect(tester.widget<Text>(inDialog(find.descendant(
            of: find.byKey(const Key('service_endpoints_status')), matching: find.byType(Text)))).data,
        'DOWN');
    expect(tester.widget<SelectableText>(find.byKey(const Key('service_endpoints_base_url'))).data,
        'http://127.0.0.1:8003');
    expect(find.byKey(const Key('endpoint_GET_/api/tenants/')), findsNothing);

    down = false;
    final before = gw.count('/api/system/services/tenant/endpoints/');
    await tester.tap(inDialog(find.text('Thử lại')));
    await tester.pumpAndSettle();
    expect(gw.count('/api/system/services/tenant/endpoints/'), before + 1);
    expect(find.byKey(const Key('endpoint_GET_/api/tenants/')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(gw.count('/api/system/services/tenant/endpoints/'), before + 1);
  });

  testWidgets('6. Gateway không phản hồi: báo lỗi + Thử lại, không hiển thị endpoint giả', (tester) async {
    await pumpDashboard(tester);
    gw.overrides['/api/system/services/identity/endpoints/'] = () => throw http.ClientException('refused');
    await openService(tester, 'identity');

    expect(find.byKey(const Key('service_endpoints_error')), findsOneWidget);
    expect(inDialog(find.textContaining('Không kết nối được tới API Gateway')), findsOneWidget);
    expect(find.byKey(const Key('service_endpoints_list')), findsNothing);
    expect(tester.widget<SelectableText>(find.byKey(const Key('service_endpoints_base_url'))).data, '—');
    expect(tester.widget<Text>(find.byKey(const Key('service_endpoints_port'))).data, '8001');
  });

  testWidgets('7. Cả 5 service đều nhấn được và gọi đúng service của mình; đóng hộp thoại', (tester) async {
    await pumpDashboard(tester);
    for (final key in _ports.keys) {
      await openService(tester, key);
      expect(gw.count('/api/system/services/$key/endpoints/'), 1, reason: key);
      expect(tester.widget<Text>(find.byKey(const Key('service_endpoints_port'))).data, '${_ports[key]}');
      await tester.tap(inDialog(find.byTooltip('Đóng')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('service_endpoints_dialog')), findsNothing);
    }
  });

  testWidgets('8. Catalog endpoint gửi kèm JWT (Bearer) — Gateway chỉ trả cho ADMIN', (tester) async {
    await pumpDashboard(tester);
    await openService(tester, 'tenant');
    expect(gw.catalogAuth, isNotEmpty);
    expect(gw.catalogAuth.every((h) => h == 'Bearer access'), isTrue, reason: '${gw.catalogAuth}');
  });

  testWidgets('9. LANDLORD: không có sơ đồ SOA / catalog endpoint trên Dashboard, không gọi catalog', (tester) async {
    await pumpDashboard(tester, role: 'LANDLORD');
    expect(find.byKey(const Key('soa_service_tenant')), findsNothing);
    expect(gw.requests.where((p) => p.startsWith('/api/system/services/')), isEmpty);
  });

  testWidgets('10. Gateway trả 403 cho catalog: báo lỗi, không hiển thị endpoint', (tester) async {
    gw.overrides['/api/system/services/tenant/endpoints/'] =
        () => _json({'error': 'Chỉ Quản trị viên (ADMIN) được xem danh mục endpoint.'}, 403);
    await pumpDashboard(tester);
    await openService(tester, 'tenant');
    expect(inDialog(find.textContaining('Chỉ Quản trị viên (ADMIN)')), findsWidgets);
    expect(inDialog(find.text('/api/tenants/')), findsNothing);
  });
}
