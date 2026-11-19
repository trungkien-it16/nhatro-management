// Chặng 3 — Màn hình đăng ký (/register) gọi POST /api/auth/register/ qua API Gateway.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nhatro_frontend/features/auth/presentation/register_page.dart';
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

/// AuthProvider thật (register/login gọi ApiClient), chỉ cố định trạng thái ban đầu.
class _AuthAs extends AuthProvider {
  final AuthStatus fixed;
  _AuthAs(this.fixed);

  @override
  AuthStatus get status => fixed;

  /// Người dùng đã đăng nhập trong test này là chủ trọ (vai trò quản lý).
  @override
  String get role => 'LANDLORD';

  @override
  bool get isAuthenticated => fixed == AuthStatus.authenticated;
}

class _OfflineRepo extends AppDataRepository {
  @override
  Future<void> syncWithBackend() async {}
}

/// Gateway giả cho /auth/register/. Ghi lại mọi request đăng ký để kiểm tra payload.
class _FakeGateway {
  final List<http.Request> registerRequests = [];
  int otherRequests = 0;
  Future<http.Response> Function(Map<String, dynamic> body)? onRegister;

  MockClient get client => MockClient((req) async {
        if (req.url.path == '/api/auth/register/') {
          registerRequests.add(req);
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          if (onRegister != null) return onRegister!(body);
          return _json({
            'username': body['username'],
            'email': body['email'] ?? '',
            'first_name': body['first_name'],
            'last_name': body['last_name'],
            'role': body['role'],
            'phone_number': body['phone_number'],
          }, 201);
        }
        otherRequests++;
        return _json({'detail': 'Not found'}, 404); // vd. /auth/test-users/ khi DEBUG tắt
      });

  Map<String, dynamic> get lastBody => jsonDecode(registerRequests.last.body) as Map<String, dynamic>;
}

void main() {
  late _FakeGateway gw;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiClient.resetForTest();
    gw = _FakeGateway();
    ApiClient.httpClient = gw.client;
  });

  tearDown(() {
    ApiClient.httpClient = http.Client();
    ApiClient.resetForTest();
  });

  void bigScreen(WidgetTester tester, [Size size = const Size(1440, 1800)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Mở app khi chưa đăng nhập rồi bấm "Đăng ký" ở màn đăng nhập để sang /register.
  Future<void> openRegister(WidgetTester tester) async {
    await tester.pumpWidget(NhaTroManagerApp(
      authProvider: _AuthAs(AuthStatus.unauthenticated),
      repository: _OfflineRepo(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('NHÀ TRỌ MANAGER'), findsOneWidget);
    await tester.tap(find.byKey(const Key('login_go_register')));
    await tester.pumpAndSettle();
    expect(find.text('Tạo tài khoản'), findsOneWidget);
  }

  Future<void> fill(
    WidgetTester tester, {
    String? role = 'landlord',
    String fullName = 'Nguyễn Văn Bình',
    String username = 'chumoi',
    String email = '',
    String phone = '',
    String password = 'abcdef12',
    String? confirm,
  }) async {
    if (role != null) {
      await tester.tap(find.byKey(Key('register_role_$role')));
      await tester.pump();
    }
    await tester.enterText(find.byKey(const Key('register_fullName')), fullName);
    await tester.enterText(find.byKey(const Key('register_username')), username);
    await tester.enterText(find.byKey(const Key('register_email')), email);
    await tester.enterText(find.byKey(const Key('register_phone')), phone);
    await tester.enterText(find.byKey(const Key('register_password')), password);
    await tester.enterText(find.byKey(const Key('register_confirm')), confirm ?? password);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('register_submit')));
    await tester.tap(find.byKey(const Key('register_submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('Đăng ký LANDLORD thành công: gửi đúng payload, không tự đăng nhập, quay lại đăng nhập',
      (tester) async {
    bigScreen(tester);
    await openRegister(tester);
    await fill(tester, email: 'chumoi@test.vn', phone: '0901234567');
    await submit(tester);

    expect(gw.registerRequests, hasLength(1));
    final req = gw.registerRequests.single;
    expect(req.method, 'POST');
    expect(req.headers.containsKey('Authorization'), isFalse, reason: 'đăng ký là endpoint công khai');
    expect(gw.lastBody, {
      'username': 'chumoi',
      'password': 'abcdef12',
      'first_name': 'Nguyễn Văn',
      'last_name': 'Bình',
      'role': 'LANDLORD',
      'email': 'chumoi@test.vn',
      'phone_number': '0901234567',
    });

    expect(find.byKey(const Key('register_success')), findsOneWidget);
    expect(find.text('Đăng ký thành công'), findsOneWidget);
    expect(find.textContaining('"chumoi" (Chủ nhà trọ)'), findsOneWidget);
    // Không tự đăng nhập: không lưu token nào.
    expect(await ApiClient.getAccessToken(), isNull);

    await tester.tap(find.text('Đến trang đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('NHÀ TRỌ MANAGER'), findsOneWidget);
  });

  testWidgets('Đăng ký TENANT thành công; email/SĐT để trống thì không gửi', (tester) async {
    bigScreen(tester);
    await openRegister(tester);
    await fill(tester, role: 'tenant', fullName: 'Lan', username: 'khachmoi');
    await submit(tester);

    expect(gw.lastBody['role'], 'TENANT');
    expect(gw.lastBody['first_name'], 'Lan');
    expect(gw.lastBody['last_name'], '');
    expect(gw.lastBody.containsKey('email'), isFalse);
    expect(gw.lastBody.containsKey('phone_number'), isFalse);
    expect(find.textContaining('"khachmoi" (Khách thuê)'), findsOneWidget);
  });

  testWidgets('Tên đăng nhập trùng: hiển thị lỗi backend dưới ô Tên đăng nhập', (tester) async {
    bigScreen(tester);
    gw.onRegister = (_) async => _json({
          'username': ['Tên đăng nhập đã được sử dụng']
        }, 400);
    await openRegister(tester);
    await fill(tester, username: 'chutro1');
    await submit(tester);

    expect(find.text('Tên đăng nhập đã được sử dụng'), findsOneWidget);
    expect(find.byKey(const Key('register_success')), findsNothing);
    expect(find.textContaining('kiểm tra các trường bị lỗi'), findsOneWidget);

    // Sửa ô bị lỗi -> lỗi backend của ô đó biến mất.
    await tester.enterText(find.byKey(const Key('register_username')), 'chutro_moi');
    await tester.pump();
    expect(find.text('Tên đăng nhập đã được sử dụng'), findsNothing);
  });

  testWidgets('Email trùng: hiển thị lỗi backend dưới ô Email', (tester) async {
    bigScreen(tester);
    gw.onRegister = (_) async => _json({
          'email': ['Email đã được sử dụng.']
        }, 400);
    await openRegister(tester);
    await fill(tester, email: 'chutro1@nhatro.vn');
    await submit(tester);

    expect(find.text('Email đã được sử dụng.'), findsOneWidget);
    expect(find.byKey(const Key('register_success')), findsNothing);
  });

  testWidgets('Mật khẩu không hợp lệ: chặn ở client (không gọi API) và hiển thị lỗi password từ backend',
      (tester) async {
    bigScreen(tester);
    await openRegister(tester);
    await fill(tester, password: 'abc');
    await submit(tester);
    expect(find.text('Mật khẩu phải có ít nhất 6 ký tự'), findsOneWidget);
    expect(gw.registerRequests, isEmpty);

    gw.onRegister = (_) async => _json({
          'password': ['Mật khẩu này quá phổ biến.']
        }, 400);
    await fill(tester, role: null, password: 'abcdef12');
    await submit(tester);
    expect(gw.registerRequests, hasLength(1));
    expect(find.text('Mật khẩu này quá phổ biến.'), findsOneWidget);
  });

  testWidgets('Nhập lại mật khẩu không khớp: không gọi API', (tester) async {
    bigScreen(tester);
    await openRegister(tester);
    await fill(tester, password: 'abcdef12', confirm: 'abcdef13');
    await submit(tester);

    expect(find.text('Mật khẩu nhập lại không khớp'), findsOneWidget);
    expect(gw.registerRequests, isEmpty);
  });

  testWidgets('Validation client: bắt buộc chọn vai trò, tên đăng nhập/email/SĐT sai định dạng', (tester) async {
    bigScreen(tester);
    await openRegister(tester);
    await fill(tester, role: null, username: 'co khoang trang', email: 'khong-phai-email', phone: 'abc');
    await submit(tester);

    expect(find.text('Vui lòng chọn vai trò'), findsOneWidget);
    expect(find.textContaining('Tên đăng nhập chỉ gồm chữ, số'), findsOneWidget);
    expect(find.text('Email không hợp lệ'), findsOneWidget);
    expect(find.text('Số điện thoại không hợp lệ'), findsOneWidget);
    expect(gw.registerRequests, isEmpty);
  });

  testWidgets('Không có lựa chọn ADMIN/STAFF; lỗi role từ backend được hiển thị', (tester) async {
    bigScreen(tester);
    await openRegister(tester);
    final segmented = tester.widget<SegmentedButton<String>>(find.byKey(const Key('register_role')));
    expect(segmented.segments.map((s) => s.value).toSet(), {'LANDLORD', 'TENANT'});
    expect(find.text('Quản trị viên'), findsNothing);
    expect(find.textContaining('Nhân viên'), findsNothing);

    gw.onRegister = (_) async => _json({
          'role': ['Chỉ được đăng ký vai trò LANDLORD hoặc TENANT.']
        }, 400);
    await fill(tester);
    await submit(tester);
    expect(find.text('Chỉ được đăng ký vai trò LANDLORD hoặc TENANT.'), findsOneWidget);
  });

  test('AuthProvider.register từ chối ADMIN/STAFF ngay ở client, không gửi request', () async {
    final auth = AuthProvider();
    for (final role in ['ADMIN', 'STAFF', null, 'landlord']) {
      await expectLater(
        auth.register({'username': 'x', 'password': 'abcdef12', 'role': role}),
        throwsA(isA<ApiException>()),
      );
    }
    expect(gw.registerRequests, isEmpty);
    expect(auth.status, AuthStatus.unknown, reason: 'đăng ký không làm thay đổi phiên');
  });

  testWidgets('Mất kết nối API Gateway: báo lỗi, giữ dữ liệu đã nhập, thử lại được', (tester) async {
    bigScreen(tester);
    var down = true;
    gw.onRegister = (body) async {
      if (down) throw http.ClientException('Connection refused');
      return _json({'username': body['username'], 'role': body['role']}, 201);
    };
    await openRegister(tester);
    await fill(tester);
    await submit(tester);

    expect(find.byKey(const Key('register_error')), findsOneWidget);
    expect(find.textContaining('Không kết nối được tới API Gateway'), findsOneWidget);
    expect(find.byKey(const Key('register_success')), findsNothing, reason: 'không báo thành công giả');
    expect(find.text('chumoi'), findsOneWidget, reason: 'không xóa dữ liệu đã nhập');

    down = false;
    await submit(tester);
    expect(find.byKey(const Key('register_success')), findsOneWidget);
  });

  testWidgets('Bấm Đăng ký liên tục: chỉ gửi 1 request, hiển thị loading, khóa form', (tester) async {
    bigScreen(tester);
    final hold = Completer<void>();
    gw.onRegister = (body) async {
      await hold.future;
      return _json({'username': body['username'], 'role': body['role']}, 201);
    };
    await openRegister(tester);
    await fill(tester);
    final button = find.byKey(const Key('register_submit'));
    await tester.ensureVisible(button);
    for (var i = 0; i < 5; i++) {
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
    }
    expect(gw.registerRequests, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final usernameField = tester.widget<TextFormField>(find.byKey(const Key('register_username')));
    expect(usernameField.enabled, isFalse);

    hold.complete();
    await tester.pumpAndSettle();
    expect(gw.registerRequests, hasLength(1));
    expect(find.byKey(const Key('register_success')), findsOneWidget);
  });

  testWidgets('Ẩn/hiện mật khẩu', (tester) async {
    bigScreen(tester);
    await openRegister(tester);
    EditableText editable(String key) => tester.widget<EditableText>(
          find.descendant(of: find.byKey(Key(key)), matching: find.byType(EditableText)),
        );
    expect(editable('register_password').obscureText, isTrue);
    await tester.tap(find.byKey(const Key('register_password_toggle')));
    await tester.pump();
    expect(editable('register_password').obscureText, isFalse);
    expect(editable('register_confirm').obscureText, isTrue);
  });

  testWidgets('Điều hướng: đăng nhập <-> đăng ký', (tester) async {
    bigScreen(tester);
    await openRegister(tester);
    await tester.tap(find.byKey(const Key('register_go_login')));
    await tester.pumpAndSettle();
    expect(find.text('NHÀ TRỌ MANAGER'), findsOneWidget);
    expect(find.text('Tạo tài khoản'), findsNothing);

    await tester.tap(find.byKey(const Key('login_go_register')));
    await tester.pumpAndSettle();
    expect(find.text('Tạo tài khoản'), findsOneWidget);
  });

  testWidgets('Màn đăng ký hiển thị được trên màn hình điện thoại (không tràn layout)', (tester) async {
    bigScreen(tester, const Size(375, 812));
    await openRegister(tester);
    // Ô nhập cũng có Scrollable riêng: chỉ định vùng cuộn ngoài cùng của trang.
    await tester.scrollUntilVisible(
      find.byKey(const Key('register_go_login')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Đã đăng nhập mà vào /register -> chuyển về Dashboard', (tester) async {
    bigScreen(tester, const Size(1440, 900));
    await tester.pumpWidget(NhaTroManagerApp(
      authProvider: _AuthAs(AuthStatus.authenticated),
      repository: _OfflineRepo(),
    ));
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.text('Tổng quan nhà trọ của bạn'))).go('/register');
    await tester.pumpAndSettle();
    expect(find.byType(RegisterPage), findsNothing);
    expect(find.text('Tổng quan nhà trọ của bạn'), findsOneWidget);
  });

  test('Tách Họ và tên theo quy ước first_name/last_name của dữ liệu hiện có', () {
    expect(splitFullName('Nguyễn Văn An'), ('Nguyễn Văn', 'An'));
    expect(splitFullName('  Trần   Thị  Lan '), ('Trần Thị', 'Lan'));
    expect(splitFullName('Lan'), ('Lan', ''));
    expect(splitFullName('   '), ('', ''));
  });
}
